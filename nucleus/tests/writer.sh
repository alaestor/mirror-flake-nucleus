#!/usr/bin/env bash
set -euo pipefail

source_dir="$(cd "$(dirname "$0")/.." && pwd)"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/project/nucleus" "$work/artifacts"
export TMPDIR="$work/artifacts"
export NUCLEUS_GENERATED="$work/generated.nix"
export NUCLEUS_NIX="$work/nix"
export NUCLEUS_NIX_INSTANTIATE="$work/parse"

printf '#!%s\n' "$BASH" > "$NUCLEUS_NIX"
cat >> "$NUCLEUS_NIX" <<'EOF'
set -euo pipefail
test "$1" = flake
case "$2" in
  lock)
    test "$#" -eq 4
    test "$3" = --output-lock-file
    test "$4" = "$PWD/flake.lock"
    printf '%s\n' attempted > flake.lock
    test "${NUCLEUS_TEST_FAIL-}" != lock
    ;;
  check)
    test "$#" -eq 4
    test "$3" = --no-build
    test "$4" = --no-write-lock-file
    touch checked
    test "${NUCLEUS_TEST_FAIL-}" != check
    ;;
  *) exit 1 ;;
esac
EOF
printf '#!%s\n' "$BASH" > "$NUCLEUS_NIX_INSTANTIATE"
cat >> "$NUCLEUS_NIX_INSTANTIATE" <<'EOF'
set -euo pipefail
test "$1" = --parse
test "$(cat "$2")" != invalid
EOF
chmod +x "$NUCLEUS_NIX" "$NUCLEUS_NIX_INSTANTIATE"
cd "$work/project"

reset_project() {
  printf '%s\n' previous > flake.nix
  printf '%s\n' previous-lock > flake.lock
  printf '%s\n' candidate > "$NUCLEUS_GENERATED"
}

expect_failure() {
  if bash "$source_dir/write-flake.sh" "$@" > "$work/output" 2>&1; then
    echo 'writer unexpectedly succeeded' >&2
    exit 1
  fi
  test "$(cat flake.nix)" = previous
  test "$(cat flake.lock)" = previous-lock
}

# A successful transaction installs both candidate and refreshed lock.
reset_project
bash "$source_dir/write-flake.sh"
test "$(cat flake.nix)" = candidate
test "$(cat flake.lock)" = attempted

# A failed lock must stop validation, even if the check would succeed.
reset_project
rm checked
export NUCLEUS_TEST_FAIL=lock
expect_failure
test ! -e checked

# Check failure also restores both active files and retains diagnostics.
export NUCLEUS_TEST_FAIL=check
expect_failure
test -f checked
shopt -s nullglob
artifacts=("$TMPDIR"/nucleus.*/flake.nix.bad)
test "${#artifacts[@]}" -eq 2
test "$(cat "${artifacts[0]}")" = candidate

# If no lock existed before the transaction, rollback removes the attempted one.
reset_project
rm flake.lock
if bash "$source_dir/write-flake.sh" > "$work/output" 2>&1; then
  echo 'writer accepted a failed check without an original lock' >&2
  exit 1
fi
test "$(cat flake.nix)" = previous
test ! -e flake.lock

# Invalid source and excess arguments must fail without installing anything.
unset NUCLEUS_TEST_FAIL
reset_project
printf '%s\n' invalid > "$NUCLEUS_GENERATED"
expect_failure
expect_failure --no-check unexpected

# The escape hatch does not validate or change the existing lock.
reset_project
bash "$source_dir/write-flake.sh" --no-check
test "$(cat flake.nix)" = candidate
test "$(cat flake.lock)" = previous-lock
