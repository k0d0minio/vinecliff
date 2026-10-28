#!/usr/bin/env bash
# checks.sh — read the checks of one pull request, through the REST API.
#
# Usage: .icm/scripts/checks.sh <number> [--watch]
#
# The script reads the head commit of the pull request. Then it prints one line per check: the
# name, ok, pending or the failed conclusion, and the description. It reads both surfaces of
# GitHub: the check runs and the commit statuses. Vercel reports on the commit statuses.
#
#   --watch  reads again every 15 seconds while a check is pending or no check is listed yet,
#            30 minutes at most. Each read takes the head again, so a new push is read too. The
#            wait happens inside the script and costs no model turn.
#
# Exit: 0 every check is ok · 1 a check failed, or no check ran · 8 a check is still pending.
# It replaces the GraphQL read of the checks (lib/github.sh says why). It decides nothing.
# The contract is .icm/intake/CONTEXT.md § The loop, step 4.
set -euo pipefail

usage() {
  echo "usage: $0 <pull request number> [--watch]" >&2
  exit 2
}
n=""
watch=0
for a in "$@"; do
  case "$a" in
    --watch) watch=1 ;;
    '' | *[!0-9]*) usage ;;
    *) [ -z "$n" ] || usage; n="$a" ;;
  esac
done
[ -n "$n" ] || usage
for t in gh git jq; do
  command -v "$t" >/dev/null 2>&1 || { echo "$t is not installed" >&2; exit 1; }
done
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/github.sh
source "$here/lib/github.sh"
repo="$(gh_repo)"

deadline=$((SECONDS + 1800))
while :; do
  sha="$(gh api "repos/${repo}/pulls/${n}" | jq -r '.head.sha')"
  checks="$(gh_checks "$sha")"
  waiting=0
  if [ -z "$checks" ]; then
    waiting=1
  elif printf '%s\n' "$checks" | cut -f2 | grep -qx pending; then
    waiting=1
  fi
  if [ "$watch" -eq 0 ] || [ "$waiting" -eq 0 ] || [ "$SECONDS" -ge "$deadline" ]; then
    break
  fi
  sleep 15
done

echo "#${n} at ${sha:0:7}"
if [ -z "$checks" ]; then
  echo "no check ran" >&2
  exit 1
fi
printf '%s\n' "$checks" | sort
if printf '%s\n' "$checks" | cut -f2 | grep -qvxE 'ok|pending'; then
  exit 1
fi
if printf '%s\n' "$checks" | cut -f2 | grep -qx pending; then
  exit 8
fi
exit 0
