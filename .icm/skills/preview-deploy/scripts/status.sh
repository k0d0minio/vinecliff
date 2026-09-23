#!/usr/bin/env bash
# status.sh — the preview-deploy skill's Level-3 runnable: the environment this branch changed and
# the settled CI verdict, in one call. Wraps env.sh and ci-status.sh — no logic of its own.
#   bash .icm/skills/preview-deploy/scripts/status.sh <slug>
set -uo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)"
cd "$repo_root"
slug="${1:-}"; [ -n "$slug" ] || { echo "usage: status.sh <slug>" >&2; exit 1; }
echo "== env.sh audit --changed =="
.icm/scripts/env.sh audit --changed; rc1=$?
echo
echo "== ci-status.sh $slug =="
.icm/scripts/ci-status.sh "$slug"; rc2=$?
echo "-------------------------------------------------"
[ "$rc1" -eq 0 ] && [ "$rc2" -eq 0 ] && { echo "preview-deploy: env OK, CI GREEN — the flip (or the merge) may proceed"; exit 0; }
echo "preview-deploy: not there yet — read the verdicts above"; exit 2
