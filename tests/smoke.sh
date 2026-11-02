#!/usr/bin/env bash
set -euo pipefail

# Run from any directory with Nix, Git, Bash, and coreutils available.
source_dir="$(cd "$(dirname "$0")/.." && pwd)"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
system="$(nix eval --impure --raw --expr builtins.currentSystem)"
mkdir "$work/manual" "$work/helper"
cd "$work/manual"
cp -R "$source_dir/nucleus" nucleus
# Pin test dependencies without putting a lock file in the vendored directory.
cp "$source_dir/flake.lock" flake.lock
cp nucleus/auto-follow.nix "$work/disabled-auto-follow.nix"
printf '%s\n' 'throw "disabled auto-follow package must stay unevaluated"' > nucleus/auto-follow.nix

git init -q
printf '%s\n' existing > existing.txt
git add existing.txt
index_before="$(git ls-files -s)"
printf '%s\n' unrelated > unrelated.txt

# Prepare absent source, requiring explicit Git review without changing the index.
if bash nucleus/bootstrap.sh > "$work/prepared.log" 2>&1; then
  echo 'bootstrap accepted untracked source in a Git project' >&2
  exit 1
fi
test "$(git ls-files -s)" = "$index_before"
cmp nucleus/project.nix modules/project.nix
cmp nucleus/bootstrap-flake.nix flake.nix
git add nucleus modules flake.nix flake.lock
index_before="$(git ls-files -s)"
bash nucleus/bootstrap.sh
test "$(git ls-files -s)" = "$index_before"
nix run .#write-flake
nix flake check --no-build --all-systems
nix build ".#checks.$system.nucleus" --no-link

# The remote writer must use this project's declarations, not its own inputs.
cat > modules/smoke.nix <<'NIX'
{ lib, ... }: {
  nucleus.description = lib.mkForce "Literal \${builtins.toString (1 + 1)} with \"quotes\", \\ and\na newline";
}
NIX
git add modules/smoke.nix
nix run "$source_dir#write-flake"
expected_description=$'Literal ${builtins.toString (1 + 1)} with "quotes", \\ and\na newline'
test "$(nix eval --raw --file flake.nix description)" = "$expected_description"

# Recovery uses and preserves an existing, project-owned copy.
printf '\n# Project-owned customization\n' >> nucleus/bootstrap.sh
cp nucleus/bootstrap.sh "$work/owned-bootstrap.sh"
printf '%s\n' broken > flake.nix
index_before="$(git ls-files -s)"
nix run "$source_dir#bootstrap"
test "$(git ls-files -s)" = "$index_before"
cmp nucleus/bootstrap.sh "$work/owned-bootstrap.sh"
test "$(nix eval --raw --file flake.nix description)" = "$expected_description"
shopt -s nullglob
backups=(flake.nix.pre-bootstrap.*)
test "${#backups[@]}" -eq 1
test "$(cat "${backups[0]}")" = broken
git diff --check

# Bootstrap skips auto-follow; the writer protects ignored dependency subtrees.
cp "$work/disabled-auto-follow.nix" nucleus/auto-follow.nix
mkdir -p "$work/canonical" "$work/alternative" "$work/consumer"
printf '%s\n' '{ outputs = _: { marker = "canonical"; }; }' > "$work/canonical/flake.nix"
printf '%s\n' '{ outputs = _: { marker = "alternative"; }; }' > "$work/alternative/flake.nix"
cat > "$work/consumer/flake.nix" <<NIX
{
  inputs.shared.url = "path:$work/alternative";
  outputs = _: { };
}
NIX
write_auto_follow_module() {
  cat > modules/auto-follow.nix <<NIX
{
  nucleus = {
    autoFollow = { enable = true; ignore = [ $1 ]; };
    inputs.shared.url = "path:$work/canonical";
    inputs.consumer.url = "path:$work/consumer";
    inputs.alias.follows = "consumer";
  };
}
NIX
}
write_auto_follow_module '"consumer"'
git add modules/auto-follow.nix
# A throwing package proves bypasses never evaluate it or require its build.
cp nucleus/auto-follow.nix "$work/auto-follow.nix"
printf '%s\n' 'throw "auto-follow package must stay unevaluated"' > nucleus/auto-follow.nix
nix run "$source_dir#bootstrap"
printf '%s\n' '{ nucleus.inputs.bypass.follows = "shared"; }' > modules/bypass.nix
git add modules/bypass.nix
nix run .#write-flake -- --no-auto-follow
nix run .#write-flake -- --no-check
cp "$work/auto-follow.nix" nucleus/auto-follow.nix
bash nucleus/bootstrap.sh
shared_marker() {
  nix eval --impure --raw --expr '(builtins.getFlake (toString ./.)).inputs.consumer.inputs.shared.marker'
}
test "$(shared_marker)" = alternative
nix run .#write-flake
test "$(shared_marker)" = alternative

# Ignoring a follows alias fails without changing either active file.
write_auto_follow_module '"alias"'
cp flake.nix "$work/before-alias.nix"
cp flake.lock "$work/before-alias.lock"
if TMPDIR="$work" nix run .#write-flake > "$work/alias.log" 2>&1; then
  echo 'writer accepted an ignored follows alias' >&2
  exit 1
fi
cmp flake.nix "$work/before-alias.nix"
cmp flake.lock "$work/before-alias.lock"
artifact_dir=''
while IFS= read -r line; do
  if [[ $line == 'Artifacts: '* ]]; then
    artifact_dir="${line#Artifacts: }"
  fi
done < "$work/alias.log"
if [[ -z $artifact_dir ]]; then
  cat "$work/alias.log" >&2
  exit 1
fi
validation_log="$(cat "$artifact_dir/validation.log")"
if [[ $validation_log != *'nucleus.autoFollow.ignore contains follows aliases: alias.'* ]]; then
  printf '%s\n' "$validation_log" >&2
  exit 1
fi
test "$(shared_marker)" = alternative
# Bypasses still work even when the ignore policy is invalid.
nix run .#write-flake -- --no-auto-follow
nix run .#write-flake -- --no-check
cmp flake.lock "$work/before-alias.lock"

write_auto_follow_module ''
# The policy changed but generated flake.nix did not. Still rewrite the lock.
cp flake.nix "$work/before-auto-follow.nix"
nix run .#write-flake
cmp flake.nix "$work/before-auto-follow.nix"
test "$(shared_marker)" = canonical
nix run .#write-flake
test "$(shared_marker)" = canonical

# The remote bootstrap can also install into a fresh, non-Git project.
cd "$work/helper"
cp "$source_dir/flake.lock" flake.lock
nix run "$source_dir#bootstrap"
cmp nucleus/bootstrap.sh "$source_dir/nucleus/bootstrap.sh"
test -f modules/project.nix
test ! -e nucleus/flake.nix
test ! -e nucleus/flake.lock
nix run .#write-flake

# Opt-in Git initialization works through the helper without manual staging.
mkdir "$work/git-helper"
cd "$work/git-helper"
git init -q
printf '%s\n' staged > existing.txt
git add existing.txt
index_before="$(git ls-files -s -- existing.txt)"
printf '%s\n' unstaged > existing.txt
printf '%s\n' unrelated > unrelated.txt
cp "$source_dir/flake.lock" flake.lock
nix run "$source_dir#bootstrap" -- --git
test "$(git ls-files -s -- existing.txt)" = "$index_before"
git diff --exit-code -- flake.nix flake.lock modules/project.nix nucleus
test "$(git ls-files --others --exclude-standard -- unrelated.txt)" = unrelated.txt
nix run .#write-flake

# The helper rejects --git outside Git before copying nucleus.
mkdir "$work/no-git"
cd "$work/no-git"
if nix run "$source_dir#bootstrap" -- --git > "$work/no-git.log" 2>&1; then
  echo 'helper accepted --git outside a Git project' >&2
  exit 1
fi
test ! -e nucleus

# Helpers reject invalid destinations and do not replace unrelated nucleus paths.
mkdir "$work/refuse"
cd "$work/refuse"
printf '%s\n' unrelated > nucleus
if nix run "$source_dir#bootstrap" > "$work/rejected.log" 2>&1; then
  echo 'bootstrap overwrote an unrelated nucleus path' >&2
  exit 1
fi
test "$(cat nucleus)" = unrelated
