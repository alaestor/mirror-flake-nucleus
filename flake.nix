{
  description = "A small, vendored flake source generator";

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
      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "aarch64-darwin"
      ];

      perSystem = { pkgs, lib, ... }: {
        apps =
          builtins.mapAttrs
            (name: script: {
              type = "app";
              program = lib.getExe (
                pkgs.writeShellApplication {
                  inherit name;
                  runtimeInputs = [
                    pkgs.bash
                    pkgs.coreutils
                    pkgs.nix
                    pkgs.git
                  ];
                  text = ''
                    export NUCLEUS_SOURCE=${./nucleus}
                    export NUCLEUS_REPOSITORY_FLAKE=${./flake.nix}
                    exec ${lib.getExe pkgs.bash} ${script} "$@"
                  '';
                }
              );
              meta.description =
                if name == "bootstrap" then
                  "Vendor nucleus if absent and bootstrap the current project."
                else
                  "Run the current project's vendored flake writer.";
            })
            {
              bootstrap = ./helpers/bootstrap.sh;
              write-flake = ./helpers/write-flake.sh;
            };

        checks.nucleus = builtins.deepSeq (import ./nucleus/tests.nix { inherit lib; }) (
          pkgs.runCommandLocal "check-nucleus" { nativeBuildInputs = [ pkgs.git ]; } ''
            ${lib.getExe pkgs.bash} ${./nucleus}/tests/bootstrap.sh
            ${lib.getExe pkgs.bash} ${./nucleus}/tests/writer.sh
            touch $out
          ''
        );
      };
    };
}
