{ lib, config, pkgs, ... }:
with lib;
let
  cfg = config.base.update;
in {
  options.base.update = {
    enable = mkEnableOption "System automatic update and maintenance service";

    host = mkOption {
      type = types.str;
      default = config.networking.hostName;
      description = "The hostname used for builds. Defaults to system hostname.";
    };

    path = mkOption {
      type = types.str;
      default = "";
      description = "The relative path to the configuration within the repository (e.g., 'hosts/myhost'). Defaults to the repository root.";
    };

    sync = {
      enable = mkOption {
        type = types.bool;
        default = false;
        description = "Whether to enable Git sync service for pulling configuration from remote repository.";
      };
      url = mkOption {
        type = types.str;
        default = "";
        description = "Remote Git repository URL.";
      };
      branch = mkOption {
        type = types.str;
        default = "main";
        description = "The name of the branch to sync.";
      };
      targetPath = mkOption {
        type = types.str;
        default = "/etc/nixos";
        description = "Absolute path to sync to locally.";
      };
      destructive = mkOption {
        type = types.bool;
        default = true;
        description = "Whether to allow destructive modifications (git reset --hard and git clean).";
      };
      interval = mkOption {
        type = types.str;
        default = "hourly";
        description = "Sync frequency (systemd OnCalendar format).";
      };
    };

    upgrade = {
      enable = mkOption {
        type = types.bool;
        default = true;
        description = "Whether to enable automatic upgrades (nixos-rebuild).";
      };
      dates = mkOption {
        type = types.str;
        default = "04:00";
        description = "The time at which automatic upgrades are performed.";
      };
      randomizedDelaySec = mkOption {
        type = types.str;
        default = "1h";
        description = "Random delay time for upgrades to avoid many machines updating at the same time.";
      };
      allowReboot = mkOption {
        type = types.bool;
        default = false;
        description = "Whether to allow automatic reboot if the kernel changes after upgrade.";
      };
    };

    proxy = mkOption {
      type = types.nullOr types.str;
      default = config.networking.proxy.default;
      description = "Proxy URL for Git sync and upgrade operations. Defaults to networking.proxy.default.";
    };

    gc = {
      enable = mkOption {
        type = types.bool;
        default = true;
        description = "Whether to enable Nix garbage collection.";
      };
      dates = mkOption {
        type = types.str;
        default = "weekly";
        description = "Frequency of garbage collection.";
      };
      olderThan = mkOption {
        type = types.str;
        default = "7d";
        description = "Delete generations older than this number of days.";
      };
    };
  };

  config = mkIf (cfg.enable && !config.base.testMode) {
    # --- Git 同步服务 ---
    systemd.services.sync-config = mkIf cfg.sync.enable {
      description = "Sync NixOS configuration from Git";
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      path = [ pkgs.git pkgs.coreutils ];
      environment = mkIf (cfg.proxy != null) {
        http_proxy = cfg.proxy;
        https_proxy = cfg.proxy;
        ALL_PROXY = cfg.proxy;
        no_proxy = config.networking.proxy.noProxy;
      };
      script = ''
        mkdir -p "${cfg.sync.targetPath}"
        cd "${cfg.sync.targetPath}"
        
        if [ ! -d ".git" ]; then
          echo "Initializing Git repository in ${cfg.sync.targetPath}..."
          git init -b "${cfg.sync.branch}"
          git remote add origin "${cfg.sync.url}"
        else
          git remote set-url origin "${cfg.sync.url}" || true
        fi
        
        echo "Syncing branch ${cfg.sync.branch} from ${cfg.sync.url}..."
        git fetch origin "${cfg.sync.branch}"
        
        if [ "${if cfg.sync.destructive then "1" else "0"}" = "1" ]; then
          echo "Performing destructive sync (hard reset)..."
          git reset --hard "origin/${cfg.sync.branch}"
          git clean -fd
        else
          echo "Performing non-destructive sync (pull)..."
          git pull origin "${cfg.sync.branch}"
        fi
      '';
      serviceConfig = {
        Type = "oneshot";
        User = "root";
      };
    };

    systemd.timers.sync-config = mkIf cfg.sync.enable {
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = cfg.sync.interval;
        RandomizedDelaySec = "5min";
      };
    };

    # 为升级服务注入代理环境变量与依赖关系
    systemd.services.nixos-upgrade = mkIf cfg.upgrade.enable {
      wants = mkIf cfg.sync.enable [ "sync-config.service" ];
      after = mkIf cfg.sync.enable [ "sync-config.service" ];
      environment = mkIf (cfg.proxy != null) {
        http_proxy = cfg.proxy;
        https_proxy = cfg.proxy;
        ALL_PROXY = cfg.proxy;
        no_proxy = config.networking.proxy.noProxy;
      };
    };

    # --- 自动升级配置 ---
    system.autoUpgrade = mkIf cfg.upgrade.enable {
      enable = true;
      dates = cfg.upgrade.dates;
      randomizedDelaySec = cfg.upgrade.randomizedDelaySec;
      allowReboot = cfg.upgrade.allowReboot;
      flags = [
        "-I" "nixos-config=${cfg.sync.targetPath}${if cfg.path != "" then "/${cfg.path}" else ""}/configuration.nix"
        "-I" "nixpkgs=${builtins.path { name = "nixpkgs"; path = pkgs.path; }}"
      ];
    };

    # --- 垃圾回收与存储优化 ---
    nix.gc = mkIf cfg.gc.enable {
      automatic = true;
      dates = cfg.gc.dates;
      options = "--delete-older-than ${cfg.gc.olderThan}";
    };

    # 如果启用了 GC，默认启用 store 优化
    nix.settings.auto-optimise-store = mkDefault true;
  };
}
