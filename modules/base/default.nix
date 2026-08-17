{ lib, config, pkgs, ... }:
with lib;
let
  cfg = config.base;
in {
  imports = [
    ./auth.nix
    ./container.nix
    ./memory.nix
    ./network.nix
    ./update.nix
  ];

  options.base = {
    enable = mkEnableOption "Base system configuration";
    testMode = mkEnableOption "Test mode (force shutdown all networked services)";
  };

  config = mkIf cfg.enable {
    # 启用实验性功能 (仅 nix-command)
    nix.settings.experimental-features = [ "nix-command" ];

    # 将 NIX_PATH 中的 nixpkgs 指向当前系统使用的源码路径
    nix.nixPath = [ "nixpkgs=${builtins.path { name = "nixpkgs"; path = pkgs.path; }}" ];
    
    # 配置 Nix Registry，使 nix shell 等命令使用相同的源
    nix.registry.nixpkgs.to = {
      type = "path";
      path = builtins.path { name = "nixpkgs"; path = pkgs.path; };
    };
    
    # --- SSH 服务 ---
    services.openssh.enable = true;

    # 每次构建时自动去重存储池以节省空间
    nix.settings.auto-optimise-store = true;

    # 安装系统级常用工具
    environment.systemPackages = with pkgs; [
      git        
    ];

    # 设置时区
    time.timeZone = "Asia/Shanghai";

    # 国际化设置：默认使用中文
    i18n.defaultLocale = "zh_CN.UTF-8";
    
    # 显式添加支持的 Locale，防止部分程序报错
    i18n.supportedLocales = [ "zh_CN.UTF-8/UTF-8" "en_US.UTF-8/UTF-8" ];

    # 控制台字体设置
    console = {
      font = "Lat2-Terminus16";
      keyMap = "us";
    };

    # --- 图形界面 (X11) ---
    services.xserver.enable = false; # VPS 不需要图形界面

    # --- Firewall ---
    networking.nftables.enable = true;
  };
}
