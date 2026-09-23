#!/usr/bin/env bash
# lint.sh — lint the files THIS BRANCH changed, and nothing else (PROJECT-OWNED stub).
#
# Same standing as format.sh: changed-files-only FEEDBACK before a push, never the full sweep and
# never the verdict — CI is the verdict. Project-owned because the linter is the project's: wire
# this repo's linter in below (eslint, biome, ruff, golangci-lint, …), no auto-fix, over exactly
# the files `lib/changed-files.sh` lists. Until it is wired, it lists them and reports SKIP.
#
# Usage: .icm/scripts/lint.sh [--base <ref>]     (default base: origin/main)
# Verdict (stdout, last line): RESULT: OK 0 · RESULT: SKIP 0 (not wired) · RESULT: PROBLEMS n
#   exit 2 (the linter reported findings — fix them, or leave them to CI to say the same)
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$repo_root"
die() { echo "error: $*" >&2; exit 1; }

base="origin/main"
while [ $# -gt 0 ]; do
  case "$1" in
    --base) base="${2:-}"; shift 2 ;;
    *) die "unknown argument: $1 (usage: lint.sh [--base <ref>])" ;;
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

# --- wire the project's linter here, over "$files" only, no --fix ------------------------------
# Example (eslint):
#   printf '%s\n' "$files" | filter_ext ts tsx js jsx | xargs -r node_modules/.bin/eslint --max-warnings=0

echo "no linter is wired for this project — see _shared/project-rules.md → The factory"
echo "RESULT: SKIP"; exit 0
