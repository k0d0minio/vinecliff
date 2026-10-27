#!/usr/bin/env bash
# new-run.sh — start a ticket: the branch, the stub's move into _done/, the pull request.
#
# Usage: .icm/scripts/new-run.sh <epic>/<slug> [--ready] [--dry-run]
#        .icm/scripts/new-run.sh triage/<slug> [--ready] [--dry-run]
#
# The script reads the stub, cuts the branch from origin/main, moves the stub into its _done/
# folder, commits, pushes, and opens the draft pull request from
# .github/pull_request_template.md with the ticket path and the acceptance criteria filled in.
# It keeps the Spec approved gate for a medium, high or research stub and drops it for a low
# stub or a triage stub. It decides nothing else. It never ticks a gate and never merges.
#
#   --ready    opens the pull request ready, not draft. The hotfix lane uses it. Any other use
#              is the user's call.
#   --dry-run  prints the title, the branch, the stub's move, draft or ready, and the full pull
#              request body. It creates nothing: no branch, no commit, no push, no pull request.
#              It calls no gh and no git fetch, so it skips the clean-tree check and the remote
#              branch check. The working tree is unchanged afterwards.
#
# A triage stub that a lane wrote and did not commit is carried onto the new branch, when it is
# the one untracked file and the tree is otherwise clean. A tracked stub moves with git mv.
# The contract is .icm/intake/CONTEXT.md.
set -euo pipefail

usage() {
  echo "usage: $0 <epic>/<slug> | triage/<slug> [--ready] [--dry-run]" >&2
  exit 2
}
ready=0
dry=0
ref=""
for a in "$@"; do
  case "$a" in
    --ready) ready=1 ;;
    --dry-run) dry=1 ;;
    -*) usage ;;
    *) [ -z "$ref" ] || usage; ref="$a" ;;
  esac
done
[ -n "$ref" ] || usage
ref="${ref%.md}"
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
tracked=1
git ls-files --error-unmatch "$stub" >/dev/null 2>&1 || tracked=0
if [ "$tracked" -eq 0 ] && [ "$epic" != triage ]; then
  echo "the stub $stub is not committed. Commit the epic on main first" >&2
  exit 1
fi
if [ "$dry" -eq 0 ]; then
  command -v gh >/dev/null 2>&1 || { echo "gh is not installed" >&2; exit 1; }
  dirty="$(git status --porcelain --untracked-files=all)"
  if [ "$tracked" -eq 1 ]; then
    [ -z "$dirty" ] || { echo "the working tree is not clean. Commit or stash first" >&2; exit 1; }
  else
    [ "$dirty" = "?? $stub" ] || { echo "the working tree is not clean. The untracked stub must be the one change" >&2; exit 1; }
  fi
fi

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
if git show-ref --verify --quiet "refs/heads/${branch}"; then
  echo "branch ${branch} exists. One ticket is one branch: finish it or delete it first" >&2
  exit 1
fi

# The acceptance criteria: the checklist lines under the stub's heading, as they are.
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
awk '/^## Acceptance criteria/ { f = 1; next } f && /^## / { f = 0 } f && /^- \[/ { print }' \
  "$stub" > "${tmp}/criteria"
[ -s "${tmp}/criteria" ] || echo "- [ ] <The stub has no acceptance criteria. Write them here.>" > "${tmp}/criteria"

# The body: the template with the ticket line and the criteria filled in, and the Spec approved
# anchor and its line removed when the gate is not required. The dry run prints this same body.
awk -v ticket="$stub" -v crit="${tmp}/criteria" -v spec="$need_spec" '
  /^<!-- gate:spec-approved -->/ { if (spec == 0) { drop = 1; next } }
  drop == 1 && /^- \[ \] \*\*Spec approved\*\*/ { drop = 0; getline; next }
  /^- ticket:/ { print "- ticket: `" ticket "`"; next }
  /^- \[ \] <Copied from the stub/ { while ((getline line < crit) > 0) print line; next }
  { print }
' .github/pull_request_template.md > "${tmp}/body"

kind=draft
[ "$ready" -eq 0 ] || kind=ready
if [ "$dry" -eq 1 ]; then
  echo "dry run: nothing is created. The clean-tree check and the remote branch check are skipped."
  echo "title: ${title}"
  echo "branch: ${branch}"
  echo "base: origin/main"
  if [ "$tracked" -eq 1 ]; then echo "stub: tracked"; else echo "stub: untracked. The run carries it onto the branch."; fi
  echo "move: ${stub} -> ${done_dir}/${slug}.md"
  echo "pull request: ${kind}"
  echo "body:"
  cat "${tmp}/body"
  exit 0
fi

git fetch -q origin main
if git ls-remote --exit-code --heads origin "$branch" >/dev/null 2>&1; then
  echo "branch ${branch} exists on origin. One ticket is one branch: finish it or delete it first" >&2
  exit 1
fi
git switch -q -c "$branch" origin/main
mkdir -p "$done_dir"
if [ "$tracked" -eq 1 ]; then
  git mv "$stub" "${done_dir}/${slug}.md"
else
  mv "$stub" "${done_dir}/${slug}.md"
  git add "${done_dir}/${slug}.md"
fi
git commit -q -m "chore(intake): start ${ref}"
git push -q -u origin "$branch"

if [ "$ready" -eq 1 ]; then
  url="$(gh pr create --base main --head "$branch" --title "$title" --body-file "${tmp}/body")"
else
  url="$(gh pr create --draft --base main --head "$branch" --title "$title" --body-file "${tmp}/body")"
fi
echo "$url"
if [ "$need_spec" -eq 1 ]; then
  echo "next: Spec approved waits on Jamie. Write what you will build and your questions in the pull request, then stop."
else
  echo "next: build the ticket on branch ${branch}. The pull request is ${kind}."
fi
