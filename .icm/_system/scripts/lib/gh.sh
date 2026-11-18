#!/usr/bin/env bash
# lib/gh.sh — the GitHub transport of the scripts. Sourced, not run.
#
# Each call goes to the REST API through `gh api`. No call uses GraphQL, because GraphQL
# is not available in a cloud session. jq reads each body.
#
#   gh_repo              owner/repo. GH_REPO when set. If not, from the origin URL
#   gh_pr <number>       the pull request, as JSON
#   gh_open_pulls        the open pull requests, one JSON array, 100 at most
#   gh_checks <sha>      one line for each check: name, tab, ok | pending | <failure>
#   gh_ready_at <number> the time of the last change of the pull request to ready, or nothing
#   gh_runs_since <workflow file> <sha> <time>  one line (the status) for each run of the
#                        workflow for the commit that started at that time or later
#   gate_state <anchor>  reads a pull request body on stdin. Prints yes | no | none

gh_repo() {
  if [ -n "${GH_REPO:-}" ]; then
    printf '%s\n' "$GH_REPO"
    return 0
  fi
  local url owner name
  url="$(git config --get remote.origin.url 2>/dev/null || true)"
  [ -n "$url" ] || { echo "the repo has no origin remote. Set GH_REPO=<owner>/<repo>" >&2; return 1; }
  url="${url%/}"
  url="${url%.git}"
  url="${url//:/\/}"
  name="${url##*/}"
  url="${url%/*}"
  owner="${url##*/}"
  case "${owner}/${name}" in
    */ | /* | *@*) echo "no owner/repo in the origin URL. Set GH_REPO=<owner>/<repo>" >&2; return 1 ;;
  esac
  printf '%s/%s\n' "$owner" "$name"
}

gh_pr() {
  local repo
  repo="$(gh_repo)" || return 1
  gh api "repos/${repo}/pulls/$1"
}

gh_open_pulls() {
  local repo
  repo="$(gh_repo)" || return 1
  gh api "repos/${repo}/pulls?state=open&per_page=100"
}

# Reads both surfaces: the check runs, and the commit statuses (Vercel reports there).
gh_checks() {
  local repo runs statuses
  repo="$(gh_repo)" || return 1
  runs="$(gh api "repos/${repo}/commits/$1/check-runs?per_page=100")" || return 1
  statuses="$(gh api "repos/${repo}/commits/$1/status")" || return 1
  printf '%s\n%s\n' "$runs" "$statuses" | jq -rs '
    (.[0].check_runs // [] | group_by(.name) | map(max_by(.id)) | .[] |
      [.name,
       (if .status != "completed" then "pending"
        elif (.conclusion | IN("success", "neutral", "skipped")) then "ok"
        else (.conclusion // "unknown") end)] | @tsv),
    (.[1].statuses // [] | group_by(.context) | map(max_by(.id)) | .[] |
      [.context,
       (if .state == "success" then "ok" elif .state == "pending" then "pending" else .state end)] | @tsv)'
}

gh_ready_at() {
  local repo
  repo="$(gh_repo)" || return 1
  gh api --paginate "repos/${repo}/issues/$1/timeline?per_page=100" \
    | jq -rs 'add // [] | map(select(.event == "ready_for_review")) | last | .created_at // empty'
}

gh_runs_since() {
  local repo
  repo="$(gh_repo)" || return 1
  gh api "repos/${repo}/actions/workflows/$1/runs?head_sha=$2&per_page=100" \
    | jq -r --arg t "$3" '.workflow_runs[]? | select((.created_at // "") >= $t) | .status'
}

# The gate is the first checkbox line below its anchor. No anchor: none.
gate_state() {
  tr -d '\r' | awk -v anchor="<!-- gate:$1 -->" '
    index($0, anchor) { found = 1; next }
    found && /^- \[[xX]\]/ { print "yes"; done = 1; exit }
    found && /^- \[ \]/ { print "no"; done = 1; exit }
    END { if (!done) print "none" }'
}
