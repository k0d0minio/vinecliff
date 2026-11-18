#!/usr/bin/env bash
# close-out.sh — close one run on its branch, before the merge.
#
# Usage: close-out.sh <ticket | run id>
#
# In one commit the script:
#   - moves run.md, handoff.md, spec.md and findings.md to .icm/archive/<id>/
#   - deletes the other files of .icm/runs/<id>/
#   - moves the ticket stub to its _done/ folder
# It pushes nothing and merges nothing. The merge of the branch publishes the moves.
# It refuses on the default branch and on a working tree that is not clean.
#
# Last line: "RESULT: OK <text>" or "RESULT: STOP <reason>".
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$here/lib/project.sh"
. "$here/lib/ticket.sh"

[ $# -eq 1 ] || stop "usage: close-out.sh <ticket>"
need git jq
cd "$(icm_root)"
id="$(run_id "$1")"
[ -n "$id" ] || stop "$1 is not a ticket of this repo"
run=".icm/runs/$id"
archive=".icm/archive/$id"
[ -f "$run/run.md" ] || stop "no run for $1 on this branch"
[ ! -e "$archive" ] || stop "$archive exists. The run was closed before"

branch="$(git symbolic-ref -q --short HEAD || true)"
[ -n "$branch" ] || stop "HEAD is detached"
[ "$branch" != "$(default_branch)" ] || stop "close-out runs on the run's branch, not on $branch"
[ -z "$(git status --porcelain)" ] || stop "the working tree is not clean. Commit first"

ticket="$(field ticket "$run/run.md")"
mkdir -p "$archive"
for f in run.md handoff.md spec.md findings.md; do
  [ ! -f "$run/$f" ] || git mv "$run/$f" "$archive/$f"
done
git rm -r -q --ignore-unmatch "$run"
rm -rf "$run"

moved="no stub was found"
if [ "$(ticket_source)" = linear ]; then
  stub=".icm/intake/tickets/${ticket}.md"
  done_dir=".icm/intake/_done"
else
  stub="$ticket"
  done_dir="$(dirname "$ticket")/_done"
fi
if [ -f "$stub" ]; then
  mkdir -p "$done_dir"
  git mv "$stub" "$done_dir/$(basename "$stub")"
  moved="the stub is in $done_dir/"
fi

git commit -q -m "chore(icm): close out $id"
echo "RESULT: OK the run is in $archive, and $moved. Push the branch"
