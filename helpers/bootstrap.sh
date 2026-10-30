#!/usr/bin/env bash
set -euo pipefail

if (( $# > 1 )) || { (( $# == 1 )) && [[ $1 != --git ]]; }; then
  printf '%s\n' 'Usage: bootstrap [--git]' >&2
  exit 2
fi
if (( $# == 1 )) && ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  printf '%s\n' '--git requires an existing Git working tree.' >&2
  exit 2
fi

: "${NUCLEUS_SOURCE:?NUCLEUS_SOURCE must name the vendored source}"
if [[ -f flake.nix ]] && cmp -s flake.nix "${NUCLEUS_REPOSITORY_FLAKE:?}"; then
  printf '%s\n' 'Run bootstrap from the destination project, not the nucleus repository.' >&2
  exit 2
fi

if [[ ! -e nucleus && ! -L nucleus ]]; then
  cp -R "$NUCLEUS_SOURCE" nucleus
  chmod -R u+w nucleus
elif [[ ! -f nucleus/bootstrap.sh ]]; then
  printf '%s\n' 'nucleus exists without a bootstrap.sh; refusing to overwrite it.' >&2
  exit 2
fi

exec bash nucleus/bootstrap.sh "$@"
