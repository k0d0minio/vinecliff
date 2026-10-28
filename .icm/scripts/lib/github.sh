#!/usr/bin/env bash
# lib/github.sh — the GitHub transport of the scripts in .icm/scripts/. Sourced, not run.
#
# Every call goes to the REST API through `gh api`. No call uses GraphQL. A Claude Code cloud
# session gets "HTTP 403: GitHub GraphQL is not available from Claude Code sessions" (why: seen on
# a merge after the tick, 2026-10-28). So the scripts use no `gh pr`, no `gh release list` and no
# `gh repo view`. `gh run` and `gh workflow run` use REST and stay. No function uses `gh api --jq`:
# jq reads the body, so check.yml can serve the body from a file.
#
# Functions:
#   gh_repo            owner/repo. GH_REPO when set. Else the last two path segments of the origin
#                      URL, which also works with the proxy remote of a cloud session.
#   gh_checks <sha>    one line per check on <sha>: the name, a tab, ok, pending or the failed
#                      conclusion, a tab, the description. It reads both surfaces: the check runs
#                      (the latest run per name) and the commit statuses (Vercel reports there).
#                      Success, neutral and skipped are ok.
#   gh_open_pulls      the open pull requests, one JSON array, 100 at most.

gh_repo() {
  if [ -n "${GH_REPO:-}" ]; then
    printf '%s\n' "$GH_REPO"
    return 0
  fi
  local url owner name
  url="$(git config --get remote.origin.url 2>/dev/null || true)"
  [ -n "$url" ] || { echo "the repository has no origin remote. Set GH_REPO=<owner>/<repo>" >&2; return 1; }
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
        else (.conclusion // "unknown") end),
       (.output.title // "")] | @tsv),
    (.[1].statuses // [] | group_by(.context) | map(max_by(.id)) | .[] |
      [.context,
       (if .state == "success" then "ok" elif .state == "pending" then "pending" else .state end),
       (.description // "")] | @tsv)'
}

gh_open_pulls() {
  local repo
  repo="$(gh_repo)" || return 1
  gh api "repos/${repo}/pulls?state=open&per_page=100"
}
