{ pkgs ? import (import ../npins).nixpkgs { } }:

{
  static = import ./static.nix;
  installer = import ./installer.nix;
  vmtest = import ./vmtest.nix;
}
