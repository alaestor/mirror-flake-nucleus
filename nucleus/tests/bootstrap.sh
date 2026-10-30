#!/usr/bin/env bash
set -euo pipefail

source_dir="$(cd "$(dirname "$0")/.." && pwd)"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/project/nucleus" "$work/bin"
cp "$source_dir/bootstrap.sh" "$work/project/nucleus/bootstrap.sh"
cp "$source_dir/bootstrap-flake.nix" "$work/project/nucleus/bootstrap-flake.nix"
cp "$source_dir/project.nix" "$work/project/nucleus/project.nix"

# Exercise the bootstrap's file handling without resolving real flake inputs.
printf '#!%s\n' "$BASH" > "$work/bin/nix"
cat >> "$work/bin/nix" <<'EOF'
set -euo pipefail
if [[ ${BOOTSTRAP_TEST_FAIL_LOCK:-} == 1 && $1 == flake ]]; then
  exit 1
fi
case "$1" in
  run)
    test "$#" -eq 5
    test "$2" = --no-write-lock-file
    test "$3" = '.#write-flake'
    test "$4" = --
    test "$5" = --no-check
    cmp nucleus/bootstrap-flake.nix flake.nix
    printf '%s\n' generated > flake.nix
    ;;
  flake)
    test "$#" -eq 4
    test "$2" = lock
    test "$3" = --output-lock-file
    test "$4" = "$PWD/flake.lock"
    touch flake.lock
    ;;
  *) exit 1 ;;
esac
EOF
chmod +x "$work/bin/nix"
export PATH="$work/bin:$PATH"
cd "$work/project"

# A new project needs no existing flake and produces no spurious backup.
bash nucleus/bootstrap.sh
test "$(cat flake.nix)" = generated
test -f flake.lock
cmp nucleus/project.nix modules/project.nix
shopt -s nullglob
backups=(flake.nix.pre-bootstrap.*)
test "${#backups[@]}" -eq 0

# Recovery preserves the old source before replacing it.
printf '%s\n' custom > modules/project.nix
printf '%s\n' broken > flake.nix
bash nucleus/bootstrap.sh
test "$(cat modules/project.nix)" = custom
backups=(flake.nix.pre-bootstrap.*)
test "${#backups[@]}" -eq 1
test "$(cat "${backups[0]}")" = broken
test "$(cat flake.nix)" = generated

# An existing module tree must not gain a project declaration.
mv modules/project.nix modules/existing.nix
cp nucleus/bootstrap-flake.nix flake.nix
bash nucleus/bootstrap.sh
test ! -e modules/project.nix
test "$(cat modules/existing.nix)" = custom

# Reusing the seed itself must not create another backup.
cp nucleus/bootstrap-flake.nix flake.nix
bash nucleus/bootstrap.sh
backups=(flake.nix.pre-bootstrap.*)
test "${#backups[@]}" -eq 1

# Reject unrelated working directories without writing a flake.
cd "$work"
if bash "$source_dir/bootstrap.sh" > rejected.log 2>&1; then
  echo 'bootstrap accepted an unrelated directory' >&2
  exit 1
fi
test ! -e flake.nix

# Opt-in Git handling rejects non-repositories before modifying source.
mkdir "$work/not-git"
cd "$work/not-git"
cp -R "$work/project/nucleus" nucleus
if bash nucleus/bootstrap.sh --git > "$work/not-git.log" 2>&1; then
  echo '--git accepted a non-Git project' >&2
  exit 1
fi
test ! -e modules
test ! -e flake.nix

# Ignored lock files must not be force-added or reported as ready for Nix.
mkdir "$work/ignored-lock"
cd "$work/ignored-lock"
cp -R "$work/project/nucleus" nucleus
git init -q
printf '%s\n' flake.lock > .gitignore
if bash nucleus/bootstrap.sh --git > "$work/ignored-lock.log" 2>&1; then
  echo '--git accepted an ignored lock file' >&2
  exit 1
fi
test -f flake.lock
test -z "$(git ls-files -- flake.lock)"
test -z "$(git diff --cached --name-only)"

# Successful bootstrap stages final contents, leaving existing staged entries,
# unrelated files, and backup files alone.
mkdir "$work/git"
cd "$work/git"
cp -R "$work/project/nucleus" nucleus
git init -q
printf '%s\n' staged > nucleus/owned.txt
git add nucleus/owned.txt
index_before="$(git ls-files -s -- nucleus/owned.txt)"
printf '%s\n' unstaged > nucleus/owned.txt
printf '%s\n' unrelated > unrelated.txt
printf '%s\n' broken > flake.nix
bash nucleus/bootstrap.sh --git
test "$(git ls-files -s -- nucleus/owned.txt)" = "$index_before"
test "$(git show :flake.nix)" = generated
test "$(git diff --cached --name-only -- flake.lock)" = flake.lock
git diff --exit-code -- flake.nix flake.lock modules/project.nix nucleus/bootstrap.sh
test "$(git ls-files --others --exclude-standard -- unrelated.txt)" = unrelated.txt
test -z "$(git ls-files -- flake.nix.pre-bootstrap.\*)"
git ls-files --error-unmatch -- flake.nix flake.lock modules/project.nix nucleus/bootstrap.sh
test "$(cat flake.nix)" = generated

# Repeated opt-in runs preserve the index, including a staged lock file.
git add flake.lock
index_before="$(git ls-files -s)"
printf '%s\n' broken > flake.nix
printf '%s\n' existing-lock > flake.lock
bash nucleus/bootstrap.sh --git
test "$(git ls-files -s)" = "$index_before"

# Existing project modules are not silently included by --git.
printf '%s\n' custom > modules/untracked.nix
if bash nucleus/bootstrap.sh --git > "$work/untracked.log" 2>&1; then
  echo '--git accepted an untracked preexisting project module' >&2
  exit 1
fi
test "$(git ls-files --others --exclude-standard -- modules/untracked.nix)" = modules/untracked.nix

# Bad options fail before initialization, even in a valid Git repository.
mkdir "$work/options"
cd "$work/options"
cp -R "$work/project/nucleus" nucleus
git init -q
if bash nucleus/bootstrap.sh --unknown > "$work/options.log" 2>&1; then
  echo 'bootstrap accepted an unknown option' >&2
  exit 1
fi
test ! -e modules
test ! -e flake.nix

# A failed lock refresh leaves new files intent-to-add, not staged for commit.
mkdir "$work/failed-lock"
cd "$work/failed-lock"
cp -R "$work/project/nucleus" nucleus
git init -q
if BOOTSTRAP_TEST_FAIL_LOCK=1 bash nucleus/bootstrap.sh --git > "$work/failed-lock.log" 2>&1; then
  echo 'bootstrap accepted a failed lock refresh' >&2
  exit 1
fi
test -z "$(git diff --cached --name-only)"
test "$(cat flake.nix)" = generated
