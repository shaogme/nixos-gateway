let
  sources = import ../npins;
  pkgs = import sources.nixpkgs { };
in
pkgs.testers.nixosTest {
  name = "gateway-vm-test";

  nodes.machine = { config, pkgs, lib, ... }: {
    imports = [ ../configuration.nix ];

    # Minimal VM configuration
    virtualisation.memorySize = 1024;
    networking.usePredictableInterfaceNames = lib.mkForce false;
  };

  testScript = ''
    start_all()
    machine.wait_for_unit("multi-user.target")
    machine.wait_for_unit("sing-box.service")
    machine.wait_for_unit("tproxy-routing.service")

    # 验证 nftables 规则是否生效
    machine.succeed("nft list ruleset | grep 'table ip sing-box'")

    # 验证 ip rule 与路由表配置
    output = machine.succeed("ip rule show")
    assert "lookup 100" in output, "TProxy ip rule lookup 100 missing"
  '';
}
