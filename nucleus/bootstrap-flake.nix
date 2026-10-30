# Minimal source copied to the repository root only to regenerate flake.nix through nucleus.
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-parts = {
      url = "github:hercules-ci/flake-parts";
      inputs.nixpkgs-lib.follows = "nixpkgs";
    };
  };

  outputs =
    inputs:
    inputs.flake-parts.lib.mkFlake { inherit inputs; } {
      imports = [ ./nucleus/flake-module.nix ] ++ import ./nucleus/list-modules.nix ./modules;
    };
}
