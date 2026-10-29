#!/usr/bin/env bash
# rollback.sh — name the previous production deployment of each UAT project and print the
# commands that put them back. Runs nothing: Jamie runs the commands.
#
# Usage: .icm/scripts/rollback.sh
#
# The UAT projects are the Vercel projects of the repository with the custom environment `uat`
# (lib/vercel.sh finds them). For each one, the script reads the production deployments: the one
# production serves now, and the newest READY one made before it. It prints both with their
# commits, then one `vercel rollback` command per project. A rollback changes the code, not the
# database: migrations are forward-only, so the previous code must tolerate the schema the batch
# left. Reads: VERCEL_TOKEN, and VERCEL_TEAM, UAT_ENVIRONMENT when set. The contract is
# .icm/uat/CONTEXT.md.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
die() { echo "error: $*" >&2; exit 1; }
[ $# -eq 0 ] || { sed -n '2,13p' "${BASH_SOURCE[0]}"; exit 2; }

# shellcheck source=lib/vercel.sh
source "$here/lib/vercel.sh"
vercel_require "reading production"

projects="$(vercel_uat_projects)"
[ -n "$projects" ] || die "no Vercel project of $(gh_repo) has the custom environment '${UAT_ENVIRONMENT:-uat}'"

line() { # <deployment json>
  printf '%s' "$1" | jq -r '"\(.uid // .id) · \((.meta.githubCommitSha // "")[0:7]) · \(.state // .readyState) · https://\(.url) · \(.created / 1000 | todate)"'
}
commands=(); prepared=()
while IFS=$'\t' read -r pid pname; do
  vercel_use "$pid" "$pname"
  current="$(vercel_production_current)"
  [ -n "$current" ] || die "project $pname serves no production deployment"
  deployments="$(vercel_deployments production)"
  cur="$(printf '%s' "$deployments" | jq -c --arg c "$current" '[.[] | select((.uid // .id) == $c)] | first // empty')"
  [ -n "$cur" ] || die "the current deployment $current of $pname is not among the 20 newest: read the project in Vercel"
  created="$(printf '%s' "$cur" | jq -r '.created')"
  prev="$(printf '%s' "$deployments" | jq -c --arg c "$current" --argjson t "$created" \
    '[.[] | select((.uid // .id) != $c and (.state // .readyState) == "READY" and .created < $t)] | sort_by(-.created) | first // empty')"
  echo "$pname"
  echo "  current:  $(line "$cur")"
  if [ -z "$prev" ]; then
    echo "  previous: none READY among the 20 newest production deployments"
    continue
  fi
  echo "  previous: $(line "$prev")"
  commands+=("vercel rollback $(printf '%s' "$prev" | jq -r '.url')${VERCEL_TEAM:+ --scope $VERCEL_TEAM}")
  prepared+=("$(printf '%s' "$prev" | jq -r '.uid // .id')")
done <<<"$projects"

if [ "${#commands[@]}" -eq 0 ]; then
  echo "RESULT: NONE"
  exit 0
fi
echo
echo "The commands, Jamie's to run, one per project:"
printf '  %s\n' "${commands[@]}"
echo
echo "A rollback changes the code, not the database. Migrations are forward-only: the previous code must tolerate the schema the batch left. A schema it cannot tolerate is repaired forward, as a ticket."
echo "RESULT: PREPARED ${prepared[*]}"
