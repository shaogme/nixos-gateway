let
  sources = import ../npins;
  pkgs = import sources.nixpkgs { };
  lib = pkgs.lib;

  # 评估目标主机配置
  targetHost = (import (sources.nixpkgs + "/nixos/lib/eval-config.nix") {
    inherit pkgs;
    modules = [ ../configuration.nix ];
  });

  targetToplevel = targetHost.config.system.build.toplevel;
  diskoScript = targetHost.config.system.build.diskoScript;
  targetDisk = targetHost.config.exts.hardware.disk.btrfs.device;
  hostName = targetHost.config.networking.hostName;

  # 评估全自动安装 ISO 配置
  installerIso = (import (sources.nixpkgs + "/nixos/lib/eval-config.nix") {
    inherit pkgs;
    modules = [
      (sources.nixpkgs + "/nixos/modules/installer/cd-dvd/installation-cd-minimal.nix")

      ({ config, pkgs, ... }: {
        systemd.targets.sleep.enable = false;
        systemd.targets.suspend.enable = false;
        systemd.targets.hibernate.enable = false;
        systemd.targets.hybrid-sleep.enable = false;

        isoImage.storeContents = [ targetToplevel ];
        image.baseName = lib.mkForce "nixos-autoinstall-${hostName}";

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
            diskoScript
            nixos-install-tools
            util-linux
            systemd
            coreutils
          ];

          script = ''
            set -euo pipefail
            echo "Installing to ${targetDisk}"
          '';
        };
      })
    ];
  });

  cfg = installerIso.config;
in
pkgs.runCommand "installer-iso-static-check" { } ''
  echo "=== Running Installer ISO Static Evaluation Check ==="

  # 1. 验证目标主机名与镜像名称
  [[ "${cfg.image.baseName}" == "nixos-autoinstall-nixos-gateway" ]] || { echo "image.baseName mismatch"; exit 1; }

  # 2. 验证睡眠模式已被禁用
  [[ "${if cfg.systemd.targets.sleep.enable then "1" else "0"}" == "0" ]] || { echo "sleep not disabled"; exit 1; }
  [[ "${if cfg.systemd.targets.suspend.enable then "1" else "0"}" == "0" ]] || { echo "suspend not disabled"; exit 1; }

  # 3. 验证自动安装服务已配置
  [[ -n "${cfg.systemd.services.nixos-autoinstall.description}" ]] || { echo "nixos-autoinstall service missing"; exit 1; }

  # 4. 验证预置闭包配置
  [[ "${toString (builtins.length cfg.isoImage.storeContents)}" -ge 1 ]] || { echo "storeContents is empty"; exit 1; }

  echo "Installer ISO static assertions passed successfully!"
  touch $out
''
