{ hostPath }:
let
  # 统一处理相对路径或绝对路径
  resolvedHostPath =
    if builtins.isPath hostPath then
      hostPath
    else
      /. + builtins.unsafeDiscardStringContext (toString hostPath);

  # 导入目标主机目录下的 npins 源
  sources = import (resolvedHostPath + "/npins");
  pkgs = import sources.nixpkgs {
    system = "x86_64-linux";
    config.allowUnfree = true;
  };
  lib = pkgs.lib;

  # 1. 评估目标主机系统配置 (如 virtual-box/coding) 并构建 Disko Raw 镜像
  targetHost = (import (sources.nixpkgs + "/nixos/lib/eval-config.nix") {
    inherit pkgs;
    modules = [ (resolvedHostPath + "/configuration.nix") ];
  });

  targetDiskoImages = targetHost.config.system.build.diskoImages;
  targetDisk = targetHost.config.exts.hardware.disk.btrfs.device;
  hostName = targetHost.config.networking.hostName;

  # 2. 将 raw 镜像压缩为 raw.zst 并生成 bmap 映射表
  compressedImage = pkgs.runCommand "compressed-${hostName}-raw-image" {
    nativeBuildInputs = [ pkgs.zstd pkgs.bmaptool ];
  } ''
    mkdir -p $out
    RAW_SRC=$(find -L ${targetDiskoImages} -name "*.raw" | head -n 1)
    if [ -z "$RAW_SRC" ] || [ ! -f "$RAW_SRC" ]; then
      echo "ERROR: Raw image not found in ${targetDiskoImages}"
      exit 1
    fi

    echo ">> Generating bmap block map file..."
    bmaptool create -o $out/system.bmap "$RAW_SRC"

    echo ">> Compressing raw image with zstd (level 19)..."
    zstd -19 -T0 "$RAW_SRC" -o $out/system.raw.zst
  '';

  # 3. 评估全自动无人值守流式安装 ISO
  installerIso = (import (sources.nixpkgs + "/nixos/lib/eval-config.nix") {
    inherit pkgs;
    modules = [
      # 引入 NixOS 官方 Minimal CD 模块
      (sources.nixpkgs + "/nixos/modules/installer/cd-dvd/installation-cd-minimal.nix")

      ({ config, pkgs, ... }: {
        # 禁用系统休眠
        systemd.targets.sleep.enable = false;
        systemd.targets.suspend.enable = false;
        systemd.targets.hibernate.enable = false;
        systemd.targets.hybrid-sleep.enable = false;

        image.baseName = lib.mkForce "nixos-autoinstall-${hostName}";

        # 自动化流式刷盘 Service
        systemd.services.nixos-autoinstall = {
          description = "Unattended Fast Raw Streaming Installer for ${hostName}";
          wantedBy = [ "multi-user.target" ];
          after = [ "local-fs.target" ];

          serviceConfig = {
            Type = "oneshot";
            StandardOutput = "journal+console";
            StandardError = "journal+console";
          };

          path = with pkgs; [
            bmaptool
            zstd
            gptfdisk
            util-linux
            systemd
            coreutils
          ];

          script = ''
            set -euo pipefail

            echo "======================================================"
            echo " Starting Fast Raw Streaming Installer for: ${hostName}"
            echo " Target Disk: ${targetDisk}"
            echo "======================================================"

            # 1. 确保目标磁盘设备就绪
            echo ">> Waiting for disk ${targetDisk} to be ready..."
            for i in $(seq 1 30); do
              if [ -b "${targetDisk}" ]; then
                break
              fi
              echo "Waiting for ${targetDisk}... ($i/30)"
              sleep 1
            done

            if [ ! -b "${targetDisk}" ]; then
              echo "ERROR: Target disk ${targetDisk} not found!"
              exit 1
            fi

            # 2. 流式直写 raw 镜像至目标物理磁盘
            RAW_IMAGE="${compressedImage}/system.raw.zst"
            BMAP_FILE="${compressedImage}/system.bmap"

            echo ">> Writing raw image to ${targetDisk} using bmaptool..."
            if [ -f "$BMAP_FILE" ]; then
              bmaptool copy --bmap "$BMAP_FILE" "$RAW_IMAGE" "${targetDisk}"
            else
              echo ">> Bmap file not found, falling back to direct zstd streaming..."
              zstd -dc "$RAW_IMAGE" | dd of="${targetDisk}" bs=4M iflag=fullblock oflag=direct status=progress conv=fsync
            fi

            # 3. 修复 GPT 备份表至物理磁盘末端
            echo ">> Relocating Backup GPT table to the end of the disk..."
            sgdisk -e "${targetDisk}" || true
            partprobe "${targetDisk}" || true
            sync

            echo "======================================================"
            echo " Installation Finished Successfully in Seconds!"
            echo " System will reboot into ${hostName} in 5 seconds..."
            echo "======================================================"
            sleep 5
            reboot
          '';
        };
      })
    ];
  });
in
installerIso.config.system.build.isoImage
