let
  sources = import ../npins;
  pkgs = import sources.nixpkgs { };
  eval = import (sources.nixpkgs + "/nixos/lib/eval-config.nix") {
    modules = [
      ../configuration.nix
      {
        # Minimal system config required for evaluating NixOS systemd options
        exts.testMode = true;
        boot.loader.grub.enable = false;
        fileSystems."/" = {
          device = "/dev/sda1";
          fsType = "ext4";
        };
      }
    ];
    inherit pkgs;
  };
  cfg = eval.config;
in
pkgs.runCommand "static-check" { } ''
  echo "=== Running Static Evaluation Verification ==="

  # 1. 验证主机名与网络配置
  [[ "${cfg.networking.hostName}" == "nixos-gateway" ]] || { echo "hostName mismatch"; exit 1; }
  [[ "${toString cfg.networking.firewall.enable}" == "1" ]] || { echo "firewall not enabled"; exit 1; }
  [[ "${toString cfg.boot.kernel.sysctl."net.ipv4.ip_forward"}" == "1" ]] || { echo "ipv4 forwarding missing"; exit 1; }
  [[ "${toString cfg.boot.kernel.sysctl."net.ipv6.conf.all.forwarding"}" == "1" ]] || { echo "ipv6 forwarding missing"; exit 1; }

  # 2. 验证系统代理设置与自动更新/同步配置
  [[ "${cfg.networking.proxy.default}" == "socks5://127.0.0.1:2080" ]] || { echo "proxy mismatch"; exit 1; }
  [[ "${cfg.systemd.services.nix-daemon.environment.ALL_PROXY}" == "socks5://127.0.0.1:2080" ]] || { echo "nix-daemon proxy missing"; exit 1; }
  [[ "${toString cfg.base.proxy.enable}" == "1" ]] || { echo "base.proxy not enabled"; exit 1; }
  [[ "${toString cfg.base.update.sync.enable}" == "1" ]] || { echo "base.update.sync not enabled"; exit 1; }
  [[ "${cfg.base.update.sync.url}" == "https://github.com/shaogme/nixos-gateway" ]] || { echo "base.update.sync.url mismatch"; exit 1; }
  [[ "${cfg.base.update.sync.branch}" == "main" ]] || { echo "base.update.sync.branch mismatch"; exit 1; }
  [[ "${toString cfg.base.update.upgrade.enable}" == "1" ]] || { echo "base.update.upgrade not enabled"; exit 1; }
  [[ "${toString cfg.system.autoUpgrade.enable}" == "1" ]] || { echo "system.autoUpgrade not enabled"; exit 1; }
  [[ "${cfg.base.update.upgrade.type}" == "legacy" ]] || { echo "upgrade type mismatch"; exit 1; }

  # 3. 验证 base 优化项 (认证、内存、容器、维护、网络)
  [[ "${toString cfg.base.enable}" == "1" ]] || { echo "base module not enabled"; exit 1; }
  [[ "${cfg.users.users.root.initialHashedPassword}" == "$6$msMQKMhdVSF/pecx$yAZ/5Chw8S7QAGGqtxNRmGqyZUC.DcKXvpiKaMW3HQ0Keo./W82qRzLQgqSvHP9gnx.YZMBDyVgIJpLi4yjxQ." ]] || { echo "root initialHashedPassword mismatch"; exit 1; }
  [[ "${toString cfg.users.users.root.openssh.authorizedKeys.keys}" == *"ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJcOjVWQqIBNn/JyKBufWpubJuqYR2+5DQI/Q4b25HR/ ed25519 256-20260818"* ]] || { echo "root ssh authorized keys mismatch"; exit 1; }
  [[ "${cfg.services.openssh.settings.PermitRootLogin}" == "prohibit-password" ]] || { echo "PermitRootLogin mismatch"; exit 1; }
  [[ "${toString cfg.zramSwap.enable}" == "1" ]] || { echo "zramSwap not enabled"; exit 1; }
  [[ "${cfg.zramSwap.algorithm}" == "zstd" ]] || { echo "zram algorithm mismatch"; exit 1; }
  [[ "${toString cfg.virtualisation.podman.enable}" == "1" ]] || { echo "podman not enabled"; exit 1; }

  # 4. 验证 hardware.network (systemd-networkd) 配置
  [[ "${toString cfg.base.hardware.network.enable}" == "1" ]] || { echo "network not enabled"; exit 1; }
  [[ "${toString cfg.systemd.network.enable}" == "1" ]] || { echo "systemd.network not enabled"; exit 1; }
  [[ "${cfg.systemd.network.networks."10-eth0".networkConfig.DHCP}" == "ipv6" ]] || { echo "dhcp ipv6 mismatch"; exit 1; }
  [[ "${toString cfg.systemd.network.networks."10-eth0".address}" == *"192.168.2.5/24"* ]] || { echo "ipv4 address mismatch"; exit 1; }

  # 5. 验证 dot-exts 扩展模块 (Btrfs 磁盘与 CachyOS 内核)
  [[ "${toString cfg.exts.hardware.disk.btrfs.enable}" == "1" ]] || { echo "btrfs disk not enabled"; exit 1; }
  [[ "${cfg.exts.hardware.disk.btrfs.device}" == "/dev/sda" ]] || { echo "btrfs device mismatch"; exit 1; }
  [[ "${toString cfg.exts.kernel.cachyos.enable}" == "1" ]] || { echo "cachyos kernel not enabled"; exit 1; }
  [[ "${toString cfg.boot.kernelModules}" == *"tcp_bbr"* ]] || { echo "tcp_bbr module missing"; exit 1; }

  # 6. 验证 sing-box 服务
  [[ "${toString cfg.services.sing-box.enable}" == "1" ]] || { echo "sing-box not enabled"; exit 1; }

  # 7. 验证 S-UI 容器服务与端口防火墙配置
  [[ "${if cfg.base.app.proxy.s-ui.enable then "true" else "false"}" == "true" ]] || { echo "s-ui not enabled"; exit 1; }
  [[ "${if cfg.base.app.proxy.s-ui.nginx.enable then "true" else "false"}" == "false" ]] || { echo "s-ui nginx should be disabled"; exit 1; }
  [[ "${if cfg.base.app.proxy.s-ui.ports.subscription.enable then "true" else "false"}" == "false" ]] || { echo "s-ui subscription port should be disabled"; exit 1; }
  [[ "${if cfg.base.app.proxy.s-ui.ports.panel.firewall.open then "true" else "false"}" == "true" ]] || { echo "s-ui panel firewall.open should be enabled"; exit 1; }
  [[ "${toString cfg.base.app.proxy.s-ui.extraPorts.socks5.port}" == "2080" ]] || { echo "s-ui socks5 extraPort mismatch"; exit 1; }
  [[ "${if cfg.base.app.proxy.s-ui.extraPorts.socks5.firewall.open then "true" else "false"}" == "false" ]] || { echo "s-ui socks5 firewall.open should be disabled"; exit 1; }
  [[ "${cfg.virtualisation.oci-containers.containers.s-ui.image}" == "docker.io/alireza7/s-ui:latest" ]] || { echo "s-ui container image mismatch"; exit 1; }
  [[ "${toString cfg.virtualisation.oci-containers.containers.s-ui.extraOptions}" == *"--network=host"* ]] || { echo "s-ui network host missing"; exit 1; }
  [[ "${cfg.virtualisation.oci-containers.containers.s-ui.environment.http_proxy}" == "" ]] || { echo "s-ui http_proxy should be empty (disabled)"; exit 1; }
  [[ "${cfg.virtualisation.oci-containers.containers.s-ui.environment.ALL_PROXY}" == "" ]] || { echo "s-ui ALL_PROXY should be empty (disabled)"; exit 1; }

  # 8. 验证防火墙规则与 TProxy 放行策略
  [[ "${if builtins.elem 53 cfg.networking.firewall.allowedTCPPorts then "1" else "0"}" == "1" ]] || { echo "port 53 missing from allowedTCPPorts"; exit 1; }
  [[ "${if builtins.elem 2095 cfg.networking.firewall.allowedTCPPorts then "1" else "0"}" == "1" ]] || { echo "port 2095 (s-ui panel) missing from allowedTCPPorts"; exit 1; }
  [[ "${if builtins.elem 7893 cfg.networking.firewall.allowedTCPPorts then "1" else "0"}" == "0" ]] || { echo "port 7893 should not be in allowedTCPPorts"; exit 1; }
  [[ "${if builtins.elem 2080 cfg.networking.firewall.allowedTCPPorts then "1" else "0"}" == "0" ]] || { echo "port 2080 should not be in allowedTCPPorts"; exit 1; }
  [[ "${if builtins.elem 2096 cfg.networking.firewall.allowedTCPPorts then "1" else "0"}" == "0" ]] || { echo "port 2096 should not be in allowedTCPPorts"; exit 1; }
  [[ "${if builtins.elem 53 cfg.networking.firewall.allowedUDPPorts then "1" else "0"}" == "1" ]] || { echo "port 53 missing from allowedUDPPorts"; exit 1; }
  [[ "${if builtins.elem 2095 cfg.networking.firewall.allowedUDPPorts then "1" else "0"}" == "1" ]] || { echo "port 2095 missing from allowedUDPPorts"; exit 1; }
  [[ "${if builtins.elem 7893 cfg.networking.firewall.allowedUDPPorts then "1" else "0"}" == "0" ]] || { echo "port 7893 should not be in allowedUDPPorts"; exit 1; }
  [[ "${toString cfg.networking.firewall.extraInputRules}" == *"meta mark 1 accept"* ]] || { echo "extraInputRules missing meta mark 1 accept"; exit 1; }
  [[ "${cfg.networking.firewall.checkReversePath}" == "loose" ]] || { echo "checkReversePath mismatch"; exit 1; }

  # 9. 验证 nftables 与 TProxy 路由服务
  [[ "${toString cfg.networking.nftables.enable}" == "1" ]] || { echo "nftables not enabled"; exit 1; }
  [[ -n "${cfg.systemd.services.tproxy-routing.description}" ]] || { echo "tproxy-routing unit missing"; exit 1; }

  echo "All static assertions passed successfully!"
  touch $out
''
