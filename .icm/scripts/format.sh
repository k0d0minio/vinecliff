#!/usr/bin/env bash
# format.sh — format the files THIS BRANCH changed, and nothing else (PROJECT-OWNED stub).
#
# The estate's rule is that format / lint / typecheck / build are the factory's job — CI is the
# verdict, and the session never runs the full sweep (every repo's block-local-checks hook and
# opencode.jsonc say so). What a session may do is get changed-files-only FEEDBACK before it
# pushes, so one unformatted file never costs a CI round-trip. That is what this script is for,
# and it is project-owned because the formatter is the project's: wire this repo's formatter in
# below (prettier, biome, gofmt, black, …), over exactly the files `lib/changed-files.sh` lists.
#
# Until it is wired, it lists the changed files and reports SKIP — a stub, not a pass.
#
# Usage: .icm/scripts/format.sh [--base <ref>]     (default base: origin/main)
# Verdict (stdout, last line): RESULT: OK 0 · RESULT: SKIP 0 (not wired) · RESULT: CHANGED n 0
#   (files rewritten — commit them) · RESULT: FAIL exit 1 (the formatter itself failed)
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$repo_root"
die() { echo "error: $*" >&2; exit 1; }

base="origin/main"
while [ $# -gt 0 ]; do
  case "$1" in
    --base) base="${2:-}"; shift 2 ;;
    *) die "unknown argument: $1 (usage: format.sh [--base <ref>])" ;;
  esac
done

# shellcheck source=lib/changed-files.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/changed-files.sh"
fork="$(fork_point "$base")" || exit 1
files="$(changed_files "$fork")"

if [ -z "$files" ]; then
  echo "no changed files since the fork point off $base"
  echo "RESULT: OK"; exit 0
fi
echo "changed files:"; printf '  %s\n' "$files"

# --- wire the project's formatter here, over "$files" only ---------------------------------------
# Example (prettier, JS/TS/MD only, write in place):
#   printf '%s\n' "$files" | filter_ext ts tsx js jsx md json | xargs -r node_modules/.bin/prettier --write
#   then compare `git status --porcelain` before/after to report CHANGED n.

echo "no formatter is wired for this project — see _shared/project-rules.md → The factory"
echo "RESULT: SKIP"; exit 0
