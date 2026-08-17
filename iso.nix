{ hostPath ? ./. }:
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

  # 1. 评估目标主机系统配置
  targetHost = (import (sources.nixpkgs + "/nixos/lib/eval-config.nix") {
    inherit pkgs;
    modules = [ (resolvedHostPath + "/configuration.nix") ];
  });

  targetToplevel = targetHost.config.system.build.toplevel;
  diskoScript = targetHost.config.system.build.diskoScript;
  targetDisk = targetHost.config.exts.hardware.disk.btrfs.device;
  hostName = targetHost.config.networking.hostName;

  # 2. 评估全自动无人值守安装 ISO
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

        # 将目标系统的所有依赖闭包预置到 ISO 本地 store，实现离线安装
        isoImage.storeContents = [ targetToplevel ];
        image.baseName = lib.mkForce "nixos-autoinstall-${hostName}";

        # 自动化安装 Service
        systemd.services.nixos-autoinstall = {
          description = "Unattended NixOS & Disko Auto-Installer for ${hostName}";
          wantedBy = [ "multi-user.target" ];
          after = [ "local-fs.target" "network.target" ];

          serviceConfig = {
            Type = "oneshot";
            StandardOutput = "journal+console";
            StandardError = "journal+console";
          };

          path = with pkgs; [
            config.nix.package
            diskoScript
            nixos-install-tools
            util-linux
            systemd
            coreutils
          ];

          script = ''
            set -euo pipefail

            echo "======================================================"
            echo " Starting Unattended Installation for: ${hostName}"
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

            # 2. 运行 Disko 完成 GPT 分区、Btrfs 格式化与子卷挂载
            echo ">> Running Disko partition and mount script..."
            ${diskoScript}

            # 3. 安装预构建的目标系统闭包
            echo ">> Installing NixOS closure to /mnt..."
            nixos-install \
              --system ${targetToplevel} \
              --no-root-passwd \
              --no-channel-copy

            echo "======================================================"
            echo " Installation Finished Successfully!"
            echo " System will reboot into ${hostName} in 10 seconds..."
            echo "======================================================"
            sleep 10
            reboot
          '';
        };
      })
    ];
  });
in
installerIso.config.system.build.isoImage
