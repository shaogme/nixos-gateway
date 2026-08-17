let
  sources = import ./npins;
in
{ config ? null, pkgs ? import sources.nixpkgs { }, lib ? pkgs.lib, ... }:
let
  dotExts = import sources.dot-exts { inherit pkgs; };
in
{
  # =========================================================================
  # 模块导入
  # =========================================================================
  imports = [
    ./modules/base
    dotExts.nixosModules.hardware.disk.btrfs
    dotExts.nixosModules.kernel.cachyos
  ];

  # =========================================================================
  # 1. 基础系统与优化配置 (Base 模块)
  # =========================================================================
  base = {
    enable = true;

    # 内存与内核优化（启用 MGLRU、zramSwap (zstd)、优化 swappiness 与缓存压力）
    memory.mode = "balanced";

    # 容器引擎优化
    container = {
      podman.enable = true;
    };

    # 统一网络管理 (systemd-networkd)：IPv4 固定 192.168.2.5/24，IPv6 DHCP
    network = {
      enable = true;
      preference = "ipv4";
      interfaces.eth0 = {
        dhcp = "ipv6";
        ipv4 = {
          addresses = [
            {
              address = "192.168.2.5";
              prefixLength = 24;
            }
          ];
          gateway = "192.168.2.1";
        };
      };
    };

    # 系统自动维护、GC 与 Git 同步（支持代理）
    update = {
      enable = true;
      # 代理设置默认继承 networking.proxy.default，也可显式指定
      proxy = "socks5://127.0.0.1:2080";
      gc = {
        enable = true;
        dates = "weekly";
        olderThan = "7d";
      };
      sync = {
        enable = false; # 如需从远程仓库定时拉取配置可设为 true 并指定 url
      };
      upgrade = {
        enable = false;
      };
    };
  };

  # =========================================================================
  # 2. 扩展模块配置 (硬件磁盘与内核)
  # =========================================================================
  exts = {
    # Btrfs 磁盘布局 (基于 Disko，包含 ESP、Boot、Swap、优化 Btrfs 子卷与透明压缩)
    hardware.disk.btrfs = {
      enable = true;
      device = "/dev/sda";
      swapSize = 0;          # 使用 zramSwap，禁用物理 swap
      imageBaseSize = 5120; # 基础镜像大小 5GB (MB)
    };

    # CachyOS 高性能内核 (BBRv3 + CAKE 优化)
    kernel.cachyos = {
      enable = true;
    };
  };

  # =========================================================================
  # 3. 基础网络与 IP 转发设置
  # =========================================================================
  networking = {
    hostName = "nixos-gateway";

    # 开启防火墙并开放相关端口
    firewall = {
      enable = true;
      allowedTCPPorts = [ 53 2080 7893 ];
      allowedUDPPorts = [ 53 2080 7893 ];
    };

    # 开启流量转发支持（旁路由必需）
    iproute2.enable = true;
  };

  # 内核开启 IPv4 / IPv6 转发
  boot.kernel.sysctl = {
    "net.ipv4.ip_forward" = 1;
    "net.ipv6.conf.all.forwarding" = 1;
  };

  # =========================================================================
  # 4. NixOS 系统自身代理设置（系统更新、nix-daemon 下载等）
  # =========================================================================
  networking.proxy = {
    default = "socks5://127.0.0.1:2080";
    # 排除本地回环与常见局域网网段，避免循环代理
    noProxy = "127.0.0.1,localhost,192.168.0.0/16,10.0.0.0/8,172.16.0.0/12";
  };

  # 显式给 nix-daemon 注入代理环境变量，保证 nix-shell / nixos-rebuild 顺利走代理
  systemd.services.nix-daemon.environment = {
    http_proxy = "socks5://127.0.0.1:2080";
    https_proxy = "socks5://127.0.0.1:2080";
    ALL_PROXY = "socks5://127.0.0.1:2080";
  };

  # =========================================================================
  # 5. sing-box 配置（TProxy 流量转发 + DNS 服务）
  # =========================================================================
  services.sing-box = {
    enable = true;
    settings = {
      # --- 入站定义 ---
      inbounds = [
        # 透明代理入站：接收局域网转发过来的网络流量
        {
          type = "tproxy";
          tag = "tproxy-in";
          listen = "::";
          listen_port = 7893;
          sniff = true;
        }
        # DNS 入站：监听 53 端口，接管局域网及本机的 DNS 查询
        {
          type = "dns";
          tag = "dns-in";
          listen = "::";
          listen_port = 53;
        }
      ];

      # --- 出站定义 ---
      outbounds = [
        # 指向本地已有的 SOCKS5 代理
        {
          type = "socks";
          tag = "socks-out";
          server = "127.0.0.1";
          server_port = 2080;
        }
        # 直连出站
        {
          type = "direct";
          tag = "direct";
        }
      ];

      # --- DNS 模块（国内外分流防污染）---
      dns = {
        servers = [
          # 境外代理解析（DoH）
          {
            tag = "remote-dns";
            address = "https://1.1.1.1/dns-query";
            detour = "socks-out";
          }
          # 国内直连解析
          {
            tag = "local-dns";
            address = "223.5.5.5";
            detour = "direct";
          }
        ];
        rules = [
          # 访问出站规则为 direct 的域名使用国内 DNS
          {
            outbound = "direct";
            server = "local-dns";
          }
        ];
        final = "remote-dns";
      };

      # --- 路由规则 ---
      route = {
        auto_detect_interface = true;
        rules = [
          # DNS 请求直接交给内建 DNS 引擎处理
          {
            protocol = "dns";
            action = "hijack-dns";
          }
          # 局域网私有 IP 直连
          {
            geoip = [ "private" ];
            outbound = "direct";
          }
          # 其余流量全走 SOCKS 出站
          {
            network = [ "tcp" "udp" ];
            outbound = "socks-out";
          }
        ];
      };
    };
  };

  # =========================================================================
  # 6. nftables 与 TProxy 路由策略配置
  # =========================================================================
  # 使用 nftables 将发往旁路由的流量重定向到 sing-box 的 7893 TProxy 端口
  networking.nftables = {
    enable = true;
    ruleset = ''
      table ip sing-box {
        chain mangle_prerouting {
          type filter hook prerouting priority mangle; policy accept;

          # 绕过本地回环和私有网段（避免目标是局域网内部设备的流量被强制转发）
          ip daddr { 127.0.0.0/8, 10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16 } return

          # 将局域网客户端发来的 TCP/UDP 流量标记为 1 并打入 TProxy 7893 端口
          meta l4proto { tcp, udp } tproxy to :7893 meta mark set 1 accept
        }
      }
    '';
  };

  # 创建路由表策略，使被 mark 1 的 TProxy 标记流量能被本地正确接收
  systemd.services.tproxy-routing = {
    description = "Set up TProxy routing rule and table";
    after = [ "network-pre.target" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = ''
        ${pkgs.iproute2}/bin/ip rule add fwmark 1 lookup 100
        ${pkgs.iproute2}/bin/ip route add local default dev lo table 100
      '';
      ExecStop = ''
        ${pkgs.iproute2}/bin/ip rule del fwmark 1 lookup 100
        ${pkgs.iproute2}/bin/ip rule del local default dev lo table 100
      '';
    };
  };

  # =========================================================================
  # 7. 系统工具包
  # =========================================================================
  environment.systemPackages = with pkgs; [
    sing-box
    iptables
    nftables
    iproute2
  ];
}
