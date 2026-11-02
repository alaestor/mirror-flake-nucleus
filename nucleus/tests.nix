{ lib }:
let
  listModules = import ./list-modules.nix;
  render = import ./render.nix { inherit lib; };

  discovered = map (path: lib.removePrefix "${toString ./tests/fixture}/" (toString path)) (
    listModules ./tests/fixture
  );

  evaluate =
    modules:
    lib.evalModules {
      specialArgs.inputs = { };
      modules = [
        { options.perSystem = lib.mkOption { type = lib.types.deferredModule; }; }
        ./flake-module.nix
      ]
      ++ modules;
    };

  # Independent declarations of one input must merge, including nested overrides.
  evaluated = evaluate [
    { nucleus.inputs.example.url = "github:owner/example"; }
    { nucleus.inputs.example.inputs.nixpkgs.follows = "nixpkgs"; }
    { nucleus.inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable"; }
    {
      nucleus.inputs.source = {
        url = "github:owner/source";
        flake = false;
      };
    }
  ];

  rendered = render {
    description = "Fixture flake";
    inherit (evaluated.config.nucleus) inputs outputsExpression;
  };

  literalDescription = render {
    description = "\${builtins.toString (1 + 1)}";
    inherit (evaluated.config.nucleus) inputs outputsExpression;
  };

  invalid = builtins.tryEval (
    builtins.deepSeq (evaluate [ { nucleus.inputs.example.url = 42; } ]).config.nucleus.inputs true
  );
in
assert
  discovered == [
    "a.nix"
    "nested/b.nix"
  ];
assert evaluated.config.nucleus.inputs.example.url == "github:owner/example";
assert evaluated.config.nucleus.inputs.example.inputs.nixpkgs.follows == "nixpkgs";
assert lib.hasInfix ''description = "Fixture flake";'' rendered;
assert lib.hasInfix ''description = "\''${builtins.toString (1 + 1)}";'' literalDescription;
assert lib.hasInfix ''follows = "nixpkgs";'' rendered;
assert lib.hasInfix "flake = false;" rendered;
assert !(lib.hasInfix "null" rendered);
assert !(lib.hasInfix "inputs = { };" rendered);
assert !invalid.success;
assert !(evaluate [ ]).config.nucleus.autoFollow.enable;
assert (evaluate [ ]).config.nucleus.autoFollow.ignore == [ ];
assert (evaluate [ { nucleus.autoFollow.enable = true; } ]).config.nucleus.autoFollow.enable;
assert lib.sort builtins.lessThan (evaluate [
  { nucleus.autoFollow.ignore = [ "first" ]; }
  { nucleus.autoFollow.ignore = [ "second" ]; }
]).config.nucleus.autoFollow.ignore == [ "first" "second" ];
{
  inherit discovered rendered;
}
