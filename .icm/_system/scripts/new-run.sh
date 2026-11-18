#!/usr/bin/env bash
# new-run.sh — start the run of one ticket: the branch, the run folder, the draft pull request.
# This script is the only place that opens a pull request.
#
# Usage:
#   Linear:    new-run.sh <KEY> --title "<title>" --branch "<gitBranchName>" --url "<url>"
#                         [--lane <lane>] [--summary "<one sentence>"]
#   Markdown:  new-run.sh <epic>/<slug> | triage/<slug>
#                         [--lane <lane>] [--summary "<one sentence>"]
#   Both:      new-run.sh <ticket> --refresh-body
#
# A lane is the name of a folder of .icm/_system/lanes/ that has a CONTEXT.md.
# Without --lane the run is a spine run: .icm/runs/<id>/spec.md must exist (Define writes it).
# On the default branch the script makes the run's branch from origin. On another branch
# it keeps that branch. A markdown stub that is not committed goes onto the run's branch.
# --refresh-body writes the pull request body again from spec.md. All boxes are then not
# ticked. The script never ticks a gate and never merges.
#
# Last line: "RESULT: OK <pull request url>" or "RESULT: STOP <reason>".
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$here/lib/project.sh"
. "$here/lib/ticket.sh"
. "$here/lib/gh.sh"

ticket="" TITLE="" BRANCH="" URL="" lane="" SUMMARY="" refresh=0
while [ $# -gt 0 ]; do
  case "$1" in
    --title) TITLE="${2:-}"; shift 2 ;;
    --branch) BRANCH="${2:-}"; shift 2 ;;
    --url) URL="${2:-}"; shift 2 ;;
    --lane) lane="${2:-}"; shift 2 ;;
    --summary) SUMMARY="${2:-}"; shift 2 ;;
    --refresh-body) refresh=1; shift ;;
    -*) stop "unknown option $1" ;;
    *) [ -z "$ticket" ] || stop "give one ticket"; ticket="$1"; shift ;;
  esac
done
[ -n "$ticket" ] || stop "usage: new-run.sh <ticket> [options]. Read the header of this script"
need git gh jq
cd "$(icm_root)"

source="$(ticket_source)"
base="$(default_branch)"
ID="$(run_id "$ticket")"
[ -n "$ID" ] || stop "$ticket is not a ticket of this repo"
run=".icm/runs/$ID"
sys=".icm/_system"
DATE="$(date +%F)"
repo="$(gh_repo)" || stop "the GitHub repo was not found"

# The pull request body: the template, the criteria from the spec, and the gates of the lane.
body_file="$(mktemp)"
trap 'rm -f "$body_file"' EXIT
make_body() {
  # The questions: the block of the pull request body when --refresh-body kept one,
  # or the file of the run. The body is the home of the answers (rules/questions.md).
  QUESTIONS="${kept_questions:-}"
  if [ -z "$QUESTIONS" ] && [ -s "$run/questions.md" ]; then QUESTIONS="$(cat "$run/questions.md")"; fi
  [ -n "$QUESTIONS" ] || QUESTIONS="No questions."
  CRITERIA="- [ ] The change does what the ticket asks."
  if [ -f "$run/spec.md" ]; then
    CRITERIA="$(awk '/^## Acceptance criteria/ { f = 1; next } f && /^## / { f = 0 } f && /^- \[/' "$run/spec.md" \
      | sed -E 's/^- \[[xX]\]/- [ ]/')"
  fi
  render "$sys/templates/pr-body.md" | awk -v lane="$LANE" '
    lane != "spine" && /^<!-- gate:spec-approved -->/ { skip = 1; next }
    skip && /^- \[/ { skip = 2; next }
    skip == 2 && /^$/ { skip = 0; next }
    skip == 1 { next }
    { skip = 0; print }' > "$body_file"
}

if [ "$refresh" -eq 1 ]; then
  [ -f "$run/run.md" ] || stop "no run for $ticket on this branch"
  LANE="$(field lane "$run/run.md")"
  URL="$(field link "$run/run.md")"
  number="$(field pr "$run/run.md" | tr -d '#')"
  [[ "$number" =~ ^[0-9]+$ ]] || stop "run.md has no pull request number"
  old_body="$(gh_pr "$number" | jq -r '.body // ""' | tr -d '\r')" || stop "the pull request #${number} was not read"
  if [ -z "$SUMMARY" ]; then
    SUMMARY="$(printf '%s\n' "$old_body" \
      | awk '/^## Summary/ { f = 1; next } f && /^- ticket:/ { exit } f && NF { print; exit }')"
  fi
  kept_questions="$(printf '%s\n' "$old_body" | awk '
    index($0, "<!-- questions:end -->") { inside = 0 }
    inside { print }
    index($0, "<!-- questions:start -->") { inside = 1 }')"
  make_body
  gh api -X PATCH "repos/${repo}/pulls/${number}" -F body=@"$body_file" >/dev/null \
    || stop "GitHub refused the new body of #${number}"
  echo "The body of #${number} was written again. All boxes are not ticked."
  echo "RESULT: OK #${number}"
  exit 0
fi

if [ -n "$lane" ]; then
  [[ "$lane" =~ ^[a-z][a-z0-9-]*$ ]] && [ "$lane" != spine ] && [ -f "$sys/lanes/$lane/CONTEXT.md" ] \
    || stop "the lane must be a folder of $sys/lanes/: $(cd "$sys/lanes" && ls -d -- */ | tr -d / | paste -sd ' ')"
fi
LANE="${lane:-spine}"
ticket_valid "$ticket" || stop "$ticket is not a ticket of this repo (wrong team, or no stub)"
if [ -e "$run/run.md" ] || [ -e ".icm/archive/$ID" ]; then
  stop "$ticket has a run. Use build, release or revise. A follow-up needs a new ticket"
fi
[ "$LANE" != spine ] || [ -f "$run/spec.md" ] || stop "write $run/spec.md first. That is the work of Define"

stub=""
if [ "$source" = linear ]; then
  TICKET="$(ticket_norm "$ticket")"
  [ -n "$TITLE" ] && [ -n "$BRANCH" ] && [ -n "$URL" ] || stop "a Linear ticket needs --title, --branch and --url"
else
  ref="$(stub_ref "$ticket")"
  stub=".icm/intake/${ref}.md"
  TICKET="$stub"
  URL="\`$stub\`"
  [ -n "$TITLE" ] || TITLE="$(sed -nE 's/^# +//p' "$stub" | head -n1)"
  [ -n "$TITLE" ] || TITLE="$ID"
  case "$ref" in triage/*) BRANCH="triage/$ID" ;; *) BRANCH="$ID" ;; esac
fi
[ -n "$SUMMARY" ] || SUMMARY="$TITLE"

current="$(git symbolic-ref -q --short HEAD || true)"
[ -n "$current" ] || stop "HEAD is detached. Check out the default branch or the run's branch"
excluded=(":(exclude)$run")
[ -z "$stub" ] || excluded+=(":(exclude)$stub")
dirty="$(git status --porcelain --untracked-files=all -- . "${excluded[@]}")"
[ -z "$dirty" ] || stop "the working tree is not clean. Commit or remove the other changes first"

if [ "$current" = "$base" ]; then
  git fetch -q origin "$base" || stop "git fetch failed"
  if git show-ref --verify --quiet "refs/heads/$BRANCH" \
    || git ls-remote --exit-code --heads origin "$BRANCH" >/dev/null 2>&1; then
    stop "the branch $BRANCH exists. One ticket is one branch"
  fi
  git switch -q -c "$BRANCH" "origin/$base" || stop "the branch $BRANCH was not made"
else
  BRANCH="$current"
fi

mkdir -p "$run"
PR="pending"
PHASE="define"
[ "$LANE" = spine ] || PHASE="build"
render "$sys/templates/run.md" > "$run/run.md"
render "$sys/templates/status.md" > "$run/status.md"
render "$sys/templates/handoff.md" > "$run/handoff.md"
git add "$run"
[ -z "$stub" ] || git add "$stub"
if [ "$source" = linear ] && [ "$LANE" != spine ]; then
  write_stub "$ID"
  git add .icm/intake/tickets
fi
git commit -q -m "chore(icm): start $ID"
git push -q -u origin "$BRANCH" || stop "git push failed. The run is committed on $BRANCH"

make_body
created="$(gh api -X POST "repos/${repo}/pulls" -f title="$(pr_title_for "$ticket" "$TITLE")" \
  -f head="$BRANCH" -f base="$base" -F draft=true -F body=@"$body_file")" \
  || stop "GitHub did not open the pull request. The branch $BRANCH is pushed"
number="$(jq -r '.number' <<<"$created")"
sed -i "s|^- pr: .*|- pr: #${number}|" "$run/run.md"
git commit -q -m "chore(icm): record the pull request of $ID" -- "$run/run.md"
git push -q
# A question waits: show the question dialog on the BAXTER HUD now. The dialog must not
# depend on a session that remembers to show it. No HUD on this computer: nothing happens.
hud="${ICM_HUD:-$HOME/baxter_live/system/bin/baxter_gate.py}"
if [ -x "$hud" ] && grep -qE '^- answer: *(_waiting_)? *$' "$run/questions.md" 2>/dev/null; then
  if "$hud" questions "$repo" "$number" >/dev/null 2>&1; then
    echo "questions: the dialog is on the HUD"
  else
    echo "questions: the HUD did not show the dialog. The questions are in the pull request body"
  fi
fi
echo "run: $run  branch: $BRANCH  lane: $LANE  pull request: #${number}"
echo "RESULT: OK $(jq -r '.html_url' <<<"$created")"
