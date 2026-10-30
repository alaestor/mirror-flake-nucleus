/**
  Recursively lists `*.nix` files under a directory, skipping `_`-prefixed
  entries. Deliberately plain-`builtins`-only (no `lib.hasSuffix`): this is
  imported directly from `flake.nix` before flake-parts/nixpkgs inputs are
  available to reach `lib` from.
*/
let
  listModules =
    directory:
    builtins.concatMap (
      name:
      let
        path = directory + "/${name}";
        type = builtins.readFileType path;
      in
      if builtins.substring 0 1 name == "_" then
        [ ]
      else if type == "directory" then
        listModules path
      else if builtins.match ".*\\.nix" name != null then
        [ path ]
      else
        [ ]
    ) (builtins.attrNames (builtins.readDir directory));
in
listModules
