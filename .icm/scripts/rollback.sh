#!/usr/bin/env bash
# rollback.sh — name the previous production deployment and print the command that puts it back.
# Runs nothing: Jamie runs the command.
#
# Usage: .icm/scripts/rollback.sh
#
# Reads the project's production deployments from Vercel: the one production serves now, and the
# newest READY one made before it. Prints both with their commits, then the rollback command. A
# rollback changes the code, not the database: migrations are forward-only, so the previous code
# must tolerate the schema the batch left. Reads: VERCEL_TOKEN, and VERCEL_TEAM, VERCEL_PROJECT
# when set. The contract is .icm/uat/CONTEXT.md.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
die() { echo "error: $*" >&2; exit 1; }
[ $# -eq 0 ] || { sed -n '2,11p' "${BASH_SOURCE[0]}"; exit 2; }

# shellcheck source=lib/vercel.sh
source "$here/lib/vercel.sh"
vercel_require "reading production"

current="$(vercel_production_current)"
[ -n "$current" ] || die "project $(vercel_project_name) serves no production deployment"
deployments="$(vercel_deployments production)"
line() { # <deployment json>
  printf '%s' "$1" | jq -r '"\(.uid // .id) · \((.meta.githubCommitSha // "")[0:7]) · \(.state // .readyState) · https://\(.url) · \(.created / 1000 | todate)"'
}
cur="$(printf '%s' "$deployments" | jq -c --arg c "$current" '[.[] | select((.uid // .id) == $c)] | first // empty')"
[ -n "$cur" ] || die "the current deployment $current is not among the 20 newest: read the project in Vercel"
created="$(printf '%s' "$cur" | jq -r '.created')"
prev="$(printf '%s' "$deployments" | jq -c --arg c "$current" --argjson t "$created" \
  '[.[] | select((.uid // .id) != $c and (.state // .readyState) == "READY" and .created < $t)] | sort_by(-.created) | first // empty')"

echo "current:  $(line "$cur")"
if [ -z "$prev" ]; then
  echo "previous: none READY among the 20 newest production deployments"
  echo "RESULT: NONE"
  exit 0
fi
echo "previous: $(line "$prev")"
echo
echo "The command, Jamie's to run:"
echo "  vercel rollback $(printf '%s' "$prev" | jq -r '.url')${VERCEL_TEAM:+ --scope $VERCEL_TEAM}"
echo
echo "A rollback changes the code, not the database. Migrations are forward-only: the previous code must tolerate the schema the batch left. A schema it cannot tolerate is repaired forward, as a ticket."
echo "RESULT: PREPARED $(printf '%s' "$prev" | jq -r '.uid // .id')"
