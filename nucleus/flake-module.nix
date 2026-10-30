{
  config,
  inputs,
  lib,
  ...
}:
let
  cfg = config.nucleus;

  followsOption = lib.mkOption {
    type = lib.types.nullOr lib.types.str;
    default = null;
    description = "Another flake input path to follow.";
  };

  inputOverridesType = lib.types.lazyAttrsOf (
    lib.types.submodule {
      options = {
        follows = followsOption;
        inputs = lib.mkOption {
          type = inputOverridesType;
          default = { };
          description = "Nested input overrides.";
        };
      };
    }
  );

  inputType = lib.types.submodule {
    options = {
      url = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Flake reference URL.";
      };

      flake = lib.mkOption {
        type = lib.types.nullOr lib.types.bool;
        default = null;
        description = "Whether the input is a flake.";
      };

      follows = followsOption;

      inputs = lib.mkOption {
        type = inputOverridesType;
        default = { };
        description = "Overrides for the input's own inputs.";
      };
    };
  };

  rendered = import ./render.nix { inherit lib; } {
    inherit (cfg) description inputs outputsExpression;
  };

  tests = import ./tests.nix { inherit lib; };

in
{
  options.nucleus = {
    description = lib.mkOption {
      type = lib.types.str;
      default = "";
      description = "Description written to flake.nix.";
    };

    inputs = lib.mkOption {
      type = lib.types.lazyAttrsOf inputType;
      default = { };
      description = "Flake inputs collected from flake-parts modules.";
    };

    outputsExpression = lib.mkOption {
      type = lib.types.lines;
      default = ''
        inputs:
          inputs.flake-parts.lib.mkFlake { inherit inputs; } {
            imports = [ ./nucleus/flake-module.nix ]
              ++ import ./nucleus/list-modules.nix ./modules;
          }
      '';
      description = "Nix expression used as the flake outputs function.";
    };
  };

  config = {
    perSystem =
      { pkgs, ... }:
      let
        generated = pkgs.writeText "flake.nix" rendered;
        writeFlake = pkgs.writeShellApplication {
          name = "write-flake";
          runtimeInputs = [
            pkgs.coreutils
            pkgs.diffutils
            pkgs.nix
          ];
          text = ''
            export NUCLEUS_GENERATED=${lib.escapeShellArg (toString generated)}
            export NUCLEUS_NIX=${lib.escapeShellArg (lib.getExe pkgs.nix)}
            export NUCLEUS_NIX_INSTANTIATE=${lib.escapeShellArg (lib.getExe' pkgs.nix "nix-instantiate")}
            exec ${lib.getExe pkgs.bash} ${./write-flake.sh} "$@"
          '';
        };
      in
      {
        apps.write-flake = {
          type = "app";
          program = lib.getExe writeFlake;
          meta.description = "Regenerate flake.nix using nucleus.";
        };

        checks.nucleus = builtins.deepSeq tests (
          pkgs.runCommandLocal "check-nucleus" { nativeBuildInputs = [ pkgs.git ]; } ''
            diff -u ${inputs.self}/flake.nix ${generated}
            ${lib.getExe pkgs.bash} ${./.}/tests/bootstrap.sh
            ${lib.getExe pkgs.bash} ${./.}/tests/writer.sh
            touch $out
          ''
        );

        packages.nucleus = generated;
      };
  };
}
