{ config, pkgs, lib, ... }:
with lib;
let
  cfg = config.base.auth;
in {
  options.base.auth = {
    root = {
      mode = mkOption {
        type = types.enum [ "default" "permit_passwd" ];
        default = "default";
        description = ''
          Root login mode:
          - default: prohibit-password (key-based only recommended)
          - permit_passwd: allow password login (less secure)
        '';
      };

      initialHashedPassword = mkOption {
        type = types.str;
        default = "";
        description = "Initial hashed password for root user (empty = no password login)";
      };

      authorizedKeys = mkOption {
        type = types.listOf types.str;
        default = [];
        description = "List of authorized SSH keys for root user";
      };
    };
  };

  config = {
    assertions = [
      {
        assertion = cfg.root.mode == "default" -> cfg.root.authorizedKeys != [];
        message = "base.auth.root: When mode is 'default' (prohibit-password), you MUST provide at least one authorized SSH key. Password login is disabled in this mode, so missing keys would lock you out.";
      }
    ];

    # --- Root 用户配置 ---
    users.users.root = {
      # 强制禁用 hashedPasswordFile，解决冲突
      hashedPasswordFile = mkForce null;

      initialHashedPassword = cfg.root.initialHashedPassword;
      openssh.authorizedKeys.keys = cfg.root.authorizedKeys;
    };

    # --- SSH 安全加固 ---
    services.openssh.settings = {
      PermitEmptyPasswords = "no";
      
      # 根据 mode 动态设定 PermitRootLogin
      PermitRootLogin = if cfg.root.mode == "permit_passwd" 
                        then "yes" 
                        else "prohibit-password";
    };
  };
}
