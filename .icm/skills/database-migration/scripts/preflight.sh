#!/usr/bin/env bash
# preflight.sh — the database-migration skill's Level-3 runnable: bind the run's database and
# check this branch's migrations, in one call — and, on a MongoDB repo (isolation: database), prove
# their round trip. Wraps db-branch.sh and check-migrations.sh.
#   bash .icm/skills/database-migration/scripts/preflight.sh <slug> [--base <ref>]
set -uo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)"
cd "$repo_root"
slug="${1:-}"; [ -n "$slug" ] || { echo "usage: preflight.sh <slug> [--base <ref>]" >&2; exit 1; }
shift
echo "== db-branch =="
.icm/scripts/db-branch.sh "$slug" status; rc1=$?
echo
echo "== check-migrations =="
.icm/scripts/check-migrations.sh "$@"; rc2=$?
rc3=0
if [ "$rc2" -eq 0 ] && [ "$(jq -r '.database.isolation // ""' .icm/project.json 2>/dev/null)" = database ]; then
  echo
  echo "== prove =="
  .icm/scripts/db-branch.sh "$slug" prove "$@"; rc3=$?
fi
echo "-------------------------------------------------"
[ "$rc1" -eq 0 ] && [ "$rc2" -eq 0 ] && [ "$rc3" -eq 0 ] && { echo "preflight: ok"; exit 0; }
echo "preflight: attention needed — read the verdicts above"; exit 2
