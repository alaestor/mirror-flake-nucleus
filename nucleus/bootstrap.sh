#!/usr/bin/env bash
set -euo pipefail

if [[ ! -f nucleus/bootstrap-flake.nix ]]; then
  printf '%s\n' 'bootstrap must run from the repository root.' >&2
  exit 2
fi

use_git=false
if (( $# == 1 )) && [[ $1 == --git ]]; then
  use_git=true
elif (( $# != 0 )); then
  printf '%s\n' 'Usage: ./nucleus/bootstrap.sh [--git]' >&2
  exit 2
fi

if "$use_git" && ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  printf '%s\n' '--git requires an existing Git working tree.' >&2
  exit 2
fi

git_paths=(flake.nix nucleus)
if [[ ! -e modules ]]; then
  mkdir modules
  cp nucleus/project.nix modules/project.nix
  chmod u+w modules/project.nix
  git_paths+=(modules/project.nix)
elif [[ ! -d modules ]]; then
  printf '%s\n' 'modules exists but is not a directory.' >&2
  exit 2
fi

if [[ -f flake.nix ]] && ! cmp -s nucleus/bootstrap-flake.nix flake.nix; then
  backup="$(mktemp flake.nix.pre-bootstrap.XXXXXXXX)"
  cp flake.nix "$backup"
fi

cp nucleus/bootstrap-flake.nix flake.nix
chmod u+w flake.nix

# Make new source visible to Nix now; stage its final contents only on success.
new_files=()
mark_new_files() {
  local path
  local paths=()
  while IFS= read -r -d '' path; do
    paths+=("$path")
  done < <(git ls-files --others --exclude-standard -z -- "$@")
  if (( ${#paths[@]} )); then
    git add --intent-to-add -- "${paths[@]}"
    new_files+=("${paths[@]}")
  fi
}

if "$use_git"; then
  mark_new_files "${git_paths[@]}"
fi

if command -v git >/dev/null 2>&1 && git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  untracked="$(git ls-files --others --exclude-standard -- flake.nix nucleus modules)"
  if [[ -n "$untracked" ]] || ! git ls-files --error-unmatch -- flake.nix >/dev/null 2>&1; then
    printf '%s\n' \
      'Bootstrap source is ready, but new files are not yet visible to Nix.' \
      'Review the files, then run:' \
      '  git add nucleus modules flake.nix' \
      '  ./nucleus/bootstrap.sh' >&2
    exit 2
  fi
fi

nix run --no-write-lock-file .#write-flake -- --no-check
# An explicit output avoids Nix automatically adding a new lock to Git's index.
nix flake lock --output-lock-file "$PWD/flake.lock"
if "$use_git"; then
  mark_new_files flake.lock
  if ! git ls-files --error-unmatch -- flake.lock >/dev/null 2>&1; then
    printf '%s\n' 'flake.lock is ignored; make it visible to Git before running write-flake.' >&2
    exit 2
  fi
  if (( ${#new_files[@]} )); then
    git add -- "${new_files[@]}"
  fi
  printf '%s\n' 'Bootstrap complete. New bootstrap files are staged; review them before committing. Existing tracked files were not restaged.'
else
  printf '%s\n' 'Bootstrap complete. In Git projects, review and git add flake.lock before running nix run .#write-flake.'
fi
