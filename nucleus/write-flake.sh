#!/usr/bin/env bash
set -euo pipefail

usage() {
  printf '%s\n' 'Usage: write-flake [--no-check] [--no-auto-follow]'
  printf '%s\n' ''
  printf '%s\n' 'Generate flake.nix transactionally.'
  printf '%s\n' '  --no-check  Install the generated file without validation or lock updates.'
  printf '%s\n' '              flake.lock is left untouched; run nix flake lock yourself'
  printf '%s\n' '              afterwards if the change affects it (bootstrap.sh does this).'
  printf '%s\n' '  --no-auto-follow Skip auto-follow for this run without disabling validation.'
}

skip_check=0
skip_auto_follow=0
for arg in "$@"; do
  case "$arg" in
    --no-check) skip_check=1 ;;
    --no-auto-follow) skip_auto_follow=1 ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      usage >&2
      exit 2
      ;;
  esac
done

if (( skip_auto_follow )); then
  unset NUCLEUS_AUTO_FOLLOW
fi

: "${NUCLEUS_GENERATED:?NUCLEUS_GENERATED must name the generated flake}"
: "${NUCLEUS_NIX:?NUCLEUS_NIX must name the nix executable}"
: "${NUCLEUS_NIX_INSTANTIATE:?NUCLEUS_NIX_INSTANTIATE must name nix-instantiate}"

if [[ ! -f flake.nix || ! -d nucleus ]]; then
  printf '%s\n' 'write-flake must run from the repository root.' >&2
  exit 2
fi

# nix flake lock/check evaluate the Git-backed source, not the working
# tree: an unstaged new module is invisible to them, so validation can pass
# green while the module the user just wrote is not evaluated at all.
if command -v git >/dev/null 2>&1 && git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  untracked_modules="$(git ls-files --others --exclude-standard -- 'modules/*.nix')"
  if [[ -n "$untracked_modules" ]]; then
    printf 'warning: untracked *.nix files under modules/ are invisible to this check (git add first):\n%s\n' \
      "$untracked_modules" >&2
  fi
fi

if cmp -s "$NUCLEUS_GENERATED" flake.nix \
  && { (( skip_check )) || [[ -z ${NUCLEUS_AUTO_FOLLOW:-} ]]; }; then
  printf '%s\n' 'flake.nix is already current.'
  exit 0
fi

if (( skip_check )); then
  cp "$NUCLEUS_GENERATED" flake.nix
  chmod u+w flake.nix
  printf '%s\n' 'Updated flake.nix without validation (--no-check).'
  exit 0
fi

if ! "$NUCLEUS_NIX_INSTANTIATE" --parse "$NUCLEUS_GENERATED" >/dev/null; then
  printf '%s\n' 'The generated candidate is not valid Nix; flake.nix was not changed.' >&2
  exit 1
fi

artifact_dir="$(mktemp -d "${TMPDIR:-/tmp}/nucleus.XXXXXXXX")"
log_file="$artifact_dir/validation.log"
restoration_needed=1

cp flake.nix "$artifact_dir/flake.nix.previous"
if [[ -f flake.lock ]]; then
  cp flake.lock "$artifact_dir/flake.lock.previous"
else
  touch "$artifact_dir/flake.lock.missing"
fi

restore_previous() {
  if (( restoration_needed )); then
    cp "$artifact_dir/flake.nix.previous" flake.nix
    chmod u+w flake.nix
    if [[ -f "$artifact_dir/flake.lock.previous" ]]; then
      cp "$artifact_dir/flake.lock.previous" flake.lock
      chmod u+w flake.lock
    else
      rm -f flake.lock
    fi
  fi
}

trap restore_previous EXIT
trap 'exit 130' HUP INT TERM

cp "$NUCLEUS_GENERATED" flake.nix
chmod u+w flake.nix

refresh_lock() {
  "$NUCLEUS_NIX" flake lock --output-lock-file "$PWD/flake.lock" || return
  if [[ -n ${NUCLEUS_AUTO_FOLLOW:-} ]]; then
    "$NUCLEUS_AUTO_FOLLOW" || return
  fi
  "$NUCLEUS_NIX" flake check --no-build --no-write-lock-file || return
}

if ! refresh_lock >"$log_file" 2>&1; then
  cp flake.nix "$artifact_dir/flake.nix.bad"
  if [[ -f flake.lock ]]; then
    cp flake.lock "$artifact_dir/flake.lock.bad"
  fi
  restore_previous
  restoration_needed=0
  trap - EXIT HUP INT TERM
  printf 'Candidate validation failed; the previous flake was restored.\nArtifacts: %s\n' "$artifact_dir" >&2
  exit 1
fi

restoration_needed=0
trap - EXIT HUP INT TERM
rm -rf "$artifact_dir"
printf '%s\n' 'Updated and validated flake.nix and flake.lock.'
