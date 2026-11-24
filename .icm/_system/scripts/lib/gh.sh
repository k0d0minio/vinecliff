#!/usr/bin/env bash
# lib/gh.sh — the GitHub transport of the scripts. Sourced, not run.
#
# Each call goes to the REST API through `gh api`. No call uses GraphQL, because GraphQL
# is not available in a cloud session. jq reads each body.
#
#   gh_repo              owner/repo. GH_REPO when set. If not, from the origin URL
#   gh_pr <number>       the pull request, as JSON
#   gh_open_pulls        the open pull requests, one JSON array, 100 at most
#   gh_checks <sha>      one line for each check: name, tab, ok | pending | waits | <failure>.
#                        waits: the check asks for an act of a person (action_required)
#   gh_running <sha> [name]  the count of check runs that are not completed, in one call.
#                        A check with that name is not counted
#   gh_rate_limited <file>  true when the error text of a call in the file is a rate limit
#   gh_rate_reset        the time (HH:MM) when the rate limit ends, or "a time not known"
#   gh_ready_at <number> the time of the last change of the pull request to ready, or nothing
#   gh_runs_since <workflow file> <sha> <time>  one line (the status) for each run of the
#                        workflow for the commit that started at that time or later
#   gh_pr_of <ticket>    the number of the open pull request of a ticket: run.md of this
#                        branch, else a title "<KEY>:" or a branch with the run id
#   gh_conflict <pr json> the line for a branch that conflicts with the default branch, or
#                        nothing. The default branch moved: merge it in, not a rebase
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
        elif .conclusion == "action_required" then "waits"
        else (.conclusion // "unknown") end)] | @tsv),
    (.[1].statuses // [] | group_by(.context) | map(max_by(.id)) | .[] |
      [.context,
       (if .state == "success" then "ok" elif .state == "pending" then "pending" else .state end)] | @tsv)'
}

gh_running() {
  local repo
  repo="$(gh_repo)" || return 1
  gh api "repos/${repo}/commits/$1/check-runs?per_page=100" | jq -r --arg skip "${2:-}" '
    [.check_runs // [] | group_by(.name) | map(max_by(.id)) | .[]
     | select(.name != $skip and .status != "completed")] | length'
}

gh_rate_limited() {
  grep -qiE 'rate limit|HTTP 429' "$1" 2>/dev/null
}

# The call rate_limit does not count for the limit.
gh_rate_reset() {
  local t
  t="$(gh api rate_limit 2>/dev/null | jq -r '.resources.core.reset // empty' 2>/dev/null || true)"
  if [[ "$t" =~ ^[0-9]+$ ]] && [ "$t" -gt 0 ]; then
    date -d "@$t" +%H:%M 2>/dev/null || date -r "$t" +%H:%M 2>/dev/null || echo "a time not known"
  else
    echo "a time not known"
  fi
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

gh_pr_of() {
  local id key n
  id="$(run_id "$1")" key="$(ticket_norm "$1")"
  [ -n "$id" ] || return 1
  n="$(field pr ".icm/runs/$id/run.md" | tr -d '#')"
  [[ "$n" =~ ^[0-9]+$ ]] || n="$(gh_open_pulls | jq -r --arg id "$id" --arg key "${key:-$id}" '
    [.[] | select((.title | startswith($key + ":")) or .head.ref == $id
                  or (.head.ref | ascii_downcase | test("(^|[/_-])" + $id + "($|[/_-])")))]
    | first | .number // empty')"
  [ -n "$n" ] && printf '%s\n' "$n"
}

gh_conflict() {
  local base
  [ "$(jq -r '.mergeable' <<<"$1")" = false ] || [ "$(jq -r '.mergeable_state' <<<"$1")" = dirty ] || return 0
  base="$(jq -r '.base.ref // empty' <<<"$1")"
  base="${base:-$(default_branch)}"
  echo "the default branch $base moved, and the branch $(jq -r '.head.ref' <<<"$1") conflicts with it." \
    "Run: git fetch origin && git merge origin/$base (a merge, not a rebase), resolve, commit, push"
}

# The gate is the first checkbox line below its anchor. No anchor: none.
gate_state() {
  tr -d '\r' | awk -v anchor="<!-- gate:$1 -->" '
    index($0, anchor) { found = 1; next }
    found && /^- \[[xX]\]/ { print "yes"; done = 1; exit }
    found && /^- \[ \]/ { print "no"; done = 1; exit }
    END { if (!done) print "none" }'
}
