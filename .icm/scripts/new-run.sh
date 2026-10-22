#!/usr/bin/env bash
# new-run.sh — start a ticket: the branch, the stub's move into _done/, the draft pull request.
#
# Usage: .icm/scripts/new-run.sh <epic>/<slug>
#        .icm/scripts/new-run.sh triage/<slug>
#
# The script reads the stub, cuts the branch from origin/main, moves the stub into its _done/
# folder, commits, pushes, and opens the draft pull request from
# .github/pull_request_template.md with the ticket path and the acceptance criteria filled in.
# It keeps the Spec approved gate for a medium, high or research stub and drops it for a low
# stub or a triage stub. It decides nothing else. It never ticks a gate and never merges.
# The contract is .icm/intake/CONTEXT.md.
set -euo pipefail

usage() {
  echo "usage: $0 <epic>/<slug> | triage/<slug>" >&2
  exit 2
}
[ $# -eq 1 ] || usage
ref="${1%.md}"
ref="${ref#.icm/intake/}"
case "$ref" in
  */*/*) echo "not a stub path: $ref" >&2; exit 2 ;;
  */*) ;;
  *) usage ;;
esac
epic="${ref%%/*}"
slug="${ref##*/}"
[ "$epic" != _done ] || { echo "the stub is already in _done/" >&2; exit 2; }

root="$(git rev-parse --show-toplevel)"
cd "$root"
stub=".icm/intake/${ref}.md"
[ -f "$stub" ] || { echo "no open stub at $stub" >&2; exit 1; }
[ -f .github/pull_request_template.md ] || { echo "no .github/pull_request_template.md" >&2; exit 1; }
command -v gh >/dev/null 2>&1 || { echo "gh is not installed" >&2; exit 1; }
[ -z "$(git status --porcelain)" ] || { echo "the working tree is not clean. Commit or stash first" >&2; exit 1; }

title="$(sed -nE 's/^# +(Stub: *)?//p' "$stub" | head -n1)"
[ -n "$title" ] || title="$slug"
complexity="$(sed -nE 's/^- *complexity: *//p' "$stub" | head -n1 | tr '[:upper:]' '[:lower:]')"
if [ "$epic" = triage ]; then
  branch="triage/${slug}"
  done_dir=".icm/intake/triage/_done"
else
  branch="$slug"
  done_dir=".icm/intake/${epic}/_done"
fi
need_spec=1
case "$complexity" in low*) need_spec=0 ;; esac
[ "$epic" != triage ] || need_spec=0

git fetch -q origin main
if git show-ref --verify --quiet "refs/heads/${branch}" || git ls-remote --exit-code --heads origin "$branch" >/dev/null 2>&1; then
  echo "branch ${branch} exists. One ticket is one branch: finish it or delete it first" >&2
  exit 1
fi
git switch -q -c "$branch" origin/main
mkdir -p "$done_dir"
git mv "$stub" "${done_dir}/${slug}.md"
git commit -q -m "chore(intake): start ${ref}"
git push -q -u origin "$branch"

# The acceptance criteria: the checklist lines under the stub's heading, as they are.
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
awk '/^## Acceptance criteria/ { f = 1; next } f && /^## / { f = 0 } f && /^- \[/ { print }' \
  "${done_dir}/${slug}.md" > "${tmp}/criteria"
[ -s "${tmp}/criteria" ] || echo "- [ ] <The stub has no acceptance criteria. Write them here.>" > "${tmp}/criteria"

# The body: the template with the ticket line and the criteria filled in, and the Spec approved
# anchor and its line removed when the gate is not required.
awk -v ticket="$stub" -v crit="${tmp}/criteria" -v spec="$need_spec" '
  /^<!-- gate:spec-approved -->/ { if (spec == 0) { drop = 1; next } }
  drop == 1 && /^- \[ \] \*\*Spec approved\*\*/ { drop = 0; getline; next }
  /^- ticket:/ { print "- ticket: `" ticket "`"; next }
  /^- \[ \] <Copied from the stub/ { while ((getline line < crit) > 0) print line; next }
  { print }
' .github/pull_request_template.md > "${tmp}/body"

url="$(gh pr create --draft --base main --head "$branch" --title "$title" --body-file "${tmp}/body")"
echo "$url"
if [ "$need_spec" -eq 1 ]; then
  echo "next: Spec approved waits on Jamie. Write what you will build and your questions in the pull request, then stop."
else
  echo "next: build the ticket on branch ${branch}."
fi
