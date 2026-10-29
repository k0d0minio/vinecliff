#!/usr/bin/env bash
# close-out.sh — after the last stub of an epic: move the epic folder into .icm/intake/_done/.
#
# Usage: .icm/scripts/close-out.sh
# Run it on the ticket's branch, after the stub's move and before the pull request flips ready.
#
# An epic is finished when it has a breakdown, no open stub, at least one stub in _done/, and
# no open pull request on a sibling stub's branch. The script moves each finished epic with
# git mv and commits. It pushes nothing and merges nothing: the merge of this branch publishes
# the move. The contract is .icm/intake/CONTEXT.md.
set -euo pipefail

root="$(git rev-parse --show-toplevel)"
cd "$root"
[ -z "$(git status --porcelain)" ] || { echo "the working tree is not clean. Commit or stash first" >&2; exit 1; }
branch="$(git symbolic-ref --quiet --short HEAD || true)"
case "$branch" in
  main|master|"") echo "run this on the ticket's branch, not on ${branch:-a detached head}" >&2; exit 1 ;;
esac
for t in gh jq; do
  command -v "$t" >/dev/null 2>&1 || { echo "$t is not installed" >&2; exit 1; }
done
# The open pull requests, through the REST API (lib/github.sh says why). A failed read stops the
# script: an empty list would close an epic while a sibling pull request is open.
# shellcheck source=lib/github.sh
source .icm/scripts/lib/github.sh
pulls="$(gh_open_pulls)" || { echo "the open pull requests were not read. Nothing moved" >&2; exit 1; }
open_heads="$(jq -r '.[].head.ref' <<<"$pulls")"

moved=""
for dir in .icm/intake/*/; do
  [ -d "$dir" ] || continue
  epic="$(basename "$dir")"
  case "$epic" in _done|triage|setup) continue ;; esac
  [ -f "${dir}breakdown.md" ] || continue
  open="$(find "$dir" -maxdepth 1 -name '*.md' ! -name breakdown.md | wc -l)"
  [ "$open" -eq 0 ] || continue
  [ -d "${dir}_done" ] || continue
  finished="$(find "${dir}_done" -maxdepth 1 -name '*.md' | wc -l)"
  [ "$finished" -gt 0 ] || continue
  busy=""
  for f in "${dir}_done"/*.md; do
    s="$(basename "${f%.md}")"
    [ "$s" != "$branch" ] || continue
    if printf '%s\n' "$open_heads" | grep -qx "$s"; then busy="$s"; fi
  done
  if [ -n "$busy" ]; then
    echo "${epic}: stub ${busy} has an open pull request. The epic is not finished."
    continue
  fi
  mkdir -p .icm/intake/_done
  git mv "${dir%/}" ".icm/intake/_done/${epic}"
  moved="${moved} ${epic}"
done

if [ -z "$moved" ]; then
  echo "no epic is finished. Nothing moved."
  exit 0
fi
git commit -q -m "chore(intake): close out${moved}"
echo "moved into .icm/intake/_done/:${moved}. Push with your work. The merge publishes the move."
