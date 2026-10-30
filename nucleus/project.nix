# Every .nix file under modules/ is a flake-parts module. Underscore-prefixed
# files and directories are excluded. Keep ordinary Nix data outside this tree.
{
  systems = [
    "x86_64-linux"
    "aarch64-linux"
    "aarch64-darwin"
  ];

  nucleus = {
    description = "A nucleus flake project";
    # Declare additional inputs beside their consumers using nucleus.inputs.
    # Outer imports from an input also need that input in bootstrap-flake.nix.
    inputs = {
      nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
      flake-parts = {
        url = "github:hercules-ci/flake-parts";
        inputs.nixpkgs-lib.follows = "nixpkgs";
      };
    };
  };
}
