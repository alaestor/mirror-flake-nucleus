#!/usr/bin/env bash
set -euo pipefail

if [[ ! -f flake.nix || ! -f nucleus/flake-module.nix || ! -d modules ]]; then
  printf '%s\n' 'Run from an initialized project root. Use the bootstrap helper first.' >&2
  exit 2
fi

# Use the project's own writer, not the helper repository's input declarations.
exec nix run .#write-flake -- "$@"
