# nucleus

[![Nix](https://img.shields.io/badge/NIX-%235277C3.svg?logo=NixOS&logoColor=white)](https://nixos.org/)
[![License 0BSD](https://img.shields.io/badge/LICENSE-0BSD-GREEN)](LICENSE)
![Hallucinated Slop](https://img.shields.io/badge/%E2%80%94_Hallucinated_Slop_%E2%80%94-red)


> [Each flake begins by forming around a tiny particle, called its nucleus.](https://en.wikipedia.org/wiki/Snowflake)

A small foundation for [flake-parts](https://flake.parts/) projects; a minimal alternative to [denful/import-tree](https://github.com/denful/import-tree) and [denful/flake-file](https://github.com/denful/flake-file). Recursively discovers flake-parts modules, collect distributed flake input declarations, and generate`flake.nix`.

---

Nucleus is intended to be vendored and tailored to your project, not used as a remote third-party dependency.

**Copy `nucleus/` and own it.**

This repository's other folders and top-level flake outputs are for conveniences and not meant to be part of a vendored nucleus.

## Start a project

>[!NOTE]
> **About Nix and Nucleus with Git Projects.**
>
> A quirk of Nix is that it can only see tracked files in git-versioned projects. Passing `--git` lets bootstrap track and stage the new nucleus-related files for you, or you can review and track them by hand. If you do use it, note that it only stages the generated contents after bootstrapping succeeds. Existing tracked files aren't restaged, and untracked files are left unntracked, including existing project modules. You can review with `git diff --cached` before committing.

Omit `--git` and git-related steps if not needed.

Nucleus' bootstrap script creates `modules/project.nix` (an arbitrary convention) only when `modules/` is absent. That declaration owns the project description, supported systems, and base inputs.
An existing module tree is left untouched and must supply those declarations.

This project's `nix run .#bootstrap` helper creates `nucleus/` and its files if it is absent, then runs that folder's bootstrap script. It never replaces an existing vendored copy.
Likewise, the `nix run .#write-flake` helper delegates to the project's own `write-flake` app.

### By Nix

Run from the destination project:

```sh
nix run git+https://git.0x04.cc/alaestor/flake-nucleus#bootstrap -- --git
nix run git+https://git.0x04.cc/alaestor/flake-nucleus#write-flake
```

### By hand

Copy only this repository's `nucleus/` directory into your project. Then run:

```sh
./nucleus/bootstrap.sh --git && nix run .#write-flake
```

Or manage Git yourself:

```sh
# Prepares the bootstrap source, then stops if files need adding.
./nucleus/bootstrap.sh
git add nucleus modules flake.nix
./nucleus/bootstrap.sh
git add flake.lock
nix run .#write-flake
```

## Extend

### Your Project

Put flake-parts modules under `modules/` (by default).
Nucleus discovers `.nix` files recursively, excluding underscore-prefixed files and directories.
Non-module Nix files are best kept outside of the `modules/` tree.

Declare inputs where ever you like, such as beside their consumers, with `nucleus.inputs`:

```nix
{
  nucleus.inputs.example = {
    url = "github:owner/example";
    inputs.nixpkgs.follows = "nixpkgs";
  };
}
```

Regenerate with `nix run .#write-flake` rather than editing `flake.nix`.
When the flake changes, the writer refreshes the lock and runs `nix flake check --no-build`,
restoring the previous flake and lock if either step fails.

#### Automatic input following

Optionally use [fzakaria/nix-auto-follow](https://github.com/fzakaria/nix-auto-follow) to unify dependencies with same-named root inputs. This reduces duplication but overrides upstream dependency pins, which may break compatibility. The pinned package is evaluated and built only if you use the feature.

```nix
{
  nucleus.autoFollow = {
    enable = true; # Disabled by default
    ignore = [ "my-special-input" ]; # Optional: preserve this root input's subtree.
  };
}
```

When enabled, `write-flake` runs auto-follow after refreshing the lock, even when `flake.nix` is unchanged.

Pass `--no-auto-follow` to skip it for one run. Normal lock refresh and validation rules still apply.
`--no-check` skips lock updates and auto-follow as well as validation.

### Your Nucleus

Tweak it however you want to fit your project's needs. Change the module discovery rules and add directories to import, or edit the minimal seed flake to include additional inputs that may be a prerequisite for evaluating your modules.

Regarding the latter: if a module imports an input's flake-parts module, bootstrap needs that input before it can collect the project's declarations.
For example, alongside the `nucleus.inputs.example` declaration above:

```nix
{ inputs, ... }:
{
  imports = [ inputs.example.flakeModules.default ];
}
```

Also add the input to the `inputs` block in `nucleus/bootstrap-flake.nix` so a fresh bootstrap regeneration can evaluate properly:

```nix
example = {
  url = "github:owner/example";
  inputs.nixpkgs.follows = "nixpkgs";
};
```

Keep both input declarations aligned.
Inputs used only for packages or inside deferred NixOS and Home Manager modules don't need this duplication.
This chicken-and-egg problem can also be avoided by re-architecting how you declare and evaluate inputs;
e.g. keeping input declarations separate from your flake-module files, at the cost of no longer keeping them tightly coupled in a single file.

In any case, this becomes code you own, allowing you to engineer your preferred solutions to meet your unique needs and solve your problems.

## Recover

To regenerate a missing or broken `flake.nix` using the bundled bootstrap flake:

```sh
./nucleus/bootstrap.sh
```

Bootstrap skips validation and refreshes the lock.
It backs up an existing non-seed flake as `flake.nix.pre-bootstrap.*`, but doesn't restore it on failure.
It still needs to evaluate `modules/`, so fix broken module sources first.

## Validate

Run `nix flake check` in this repository for the native regression checks, or in
a consuming project for those checks plus generated-source consistency.
Run `bash tests/smoke.sh` here to exercise vendoring, initialization, generation, and recovery in temporary projects.
