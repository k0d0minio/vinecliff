#!/usr/bin/env bash
# resolve-run.sh — adopt an existing pipeline run into the working tree, or STOP.
#
# The single canonical "resolve the run or STOP" procedure (.icm/_shared/stage-preamble.md), made
# into one deterministic call so Build / Release spend no model tokens resolving a run.
# It reads run.md if it is already in the working tree (or the archive), otherwise it finds the run's
# PR on GitHub and fetches + checks out that PR's head branch. The PR lookup tries, in order:
#
#   1. body scan     — GET /repos/<repo>/pulls?state=open, every page (≤ 5), filtered for the slug
#                      line. The slug line is the Spec table row `| **Slug** | `<slug>` |` on a
#                      spine PR (project-body.sh) or the `- slug: <slug>` bullet on a lane PR
#                      (new-run.sh); both are matched exactly, ignoring emphasis, backticks and
#                      spaces — a PR that merely mentions the slug never resolves the run.
#   2. head branch   — GET /repos/<repo>/pulls?state=open&head=<owner>:claude/<slug> (exact head).
#   3. head suffix   — the same open-PR list, filtered for head.ref ending in `-<slug>` (a
#                      harness-named branch such as claude/<hash>-<slug>).
#   4. closed PRs    — GET /repos/<repo>/pulls?state=closed&sort=updated (the 200 most recently
#                      updated), the same slug-line and head-branch matches: a run that merged
#                      without its close-out, or whose branch was renamed after the fact.
#
# Every call is repository-scoped (/repos/{owner}/{repo}/...). The search API is never used: a
# Claude Code cloud session's proxy answers /search/* with HTTP 403, so a script that searched would
# work everywhere except the environment the pipeline is most often driven from
# (.icm/_shared/github.md → Repository-scoped endpoints only).
#
# The route that resolved the run is logged on stderr ("matched PR #N on branch B via <route>") and
# in the READY line. It NEVER creates a run, spec, run.md, or branch and never `git checkout -b`s a
# fallback — a missing run means Define has not run for this slug (or the slug is wrong), and the
# verdict is STOP. Requires curl + jq + git.
#
# Config is read straight from the process environment — this script does NOT load any .env file.
# Export these locally and set the same values in the cloud environment so resolution behaves
# identically wherever it runs. The GitHub calls go through .icm/scripts/lib/gh.sh, which falls
# back to a logged-in `gh` CLI when the token route fails and dies naming what this environment is
# missing when neither works (the per-environment table: .icm/_shared/github.md → Runs anywhere):
#
#   GITHUB_TOKEN          (one*)      GitHub token (contents, pull-requests, issues) — the PR lookup.
#   GH_TOKEN              (one*)      Alternative name for the token (*one of the two, or a gh login).
#   GITHUB_REPO           (optional)  owner/repo the runs live in. Default: derived from `origin` (lib/gh.sh).
#   GITHUB_API_URL        (optional)  API base. Default: https://api.github.com.
#
# Only the PR-lookup path (run.md absent from the tree and the archive) touches GitHub; a run
# already in the tree resolves offline. `.icm/scripts/lib/gh.sh --check` always makes the call.
#
# Usage:
#   .icm/scripts/resolve-run.sh <slug>
#
# Verdict (stdout, last line):
#   RESULT: READY   exit 0  — .icm/runs/<slug>/run.md is in the working tree and its branch is
#                             checked out. The caller proceeds to load the stage contract. The line
#                             before it names the route: "run '<slug>' resolved via <route> — …".
#   RESULT: STOP    exit 3  — no run resolved (Define hasn't run, or the slug is wrong). Do NOT
#                             fabricate the run; tell the user to run `new` (next stub, or `new <stub-name>`).
set -euo pipefail

command -v curl >/dev/null || { echo "curl not found" >&2; exit 1; }
command -v jq   >/dev/null || { echo "jq not found"   >&2; exit 1; }
command -v git  >/dev/null || { echo "git not found"  >&2; exit 1; }

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

die()  { echo "error: $*" >&2; exit 1; }
stop() { echo "$*" >&2; echo "RESULT: STOP"; exit 3; }

# --- args ------------------------------------------------------------------------------------------

slug=""
while [ $# -gt 0 ]; do
  case "$1" in
    --*) die "unknown flag: $1" ;;
    *)   [ -z "$slug" ] && slug="$1" || die "unexpected argument: $1"; shift ;;
  esac
done
[ -n "$slug" ] || die "usage: resolve-run.sh <slug>"

run_md="$repo_root/.icm/runs/$slug/run.md"

# --- config from env (lib/gh.sh: GH_API, repo, gh_token + the curl→gh fallback) --------------------

# shellcheck source=lib/gh.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/gh.sh"
# shellcheck source=lib/project.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/project.sh"

# A blocking GitHub GET. Echoes "<body>\n<http_code>"; the caller splits the status off the last line.
gh_get() { gh_api GET "$1"; }

# Read the branch a run.md records, stripping any trailing "# comment" the template carries.
branch_from_run_md() {
  grep -m1 '^- branch:' "$1" 2>/dev/null \
    | sed -E 's/^- branch:[[:space:]]*//; s/[[:space:]]+#.*$//; s/[[:space:]]*$//'
}

checkout_branch() {
  local branch="$1"
  [ -n "$branch" ] || die "run.md has no '- branch:' line — cannot resolve the run's branch"
  if ! git -C "$repo_root" rev-parse --verify --quiet "refs/heads/$branch" >/dev/null; then
    git -C "$repo_root" fetch origin "$branch" \
      || die "could not fetch origin/$branch — check network, and that the branch still exists"
  fi
  git -C "$repo_root" checkout "$branch" \
    || die "could not check out $branch (uncommitted changes in the way?)"
}

# --- PR lists (each fetched once; shared by the body scan and the head-suffix route) ----------------

open_pulls_json=""; closed_pulls_json=""
load_pulls() {   # load_pulls open|closed — sets <state>_pulls_json in this shell (idempotent)
  local state="$1" var="${1}_pulls_json" page=1 acc='[]' resp http body n max_pages sort
  [ -z "${!var}" ] || return 0
  case "$state" in
    open)   max_pages=5; sort="" ;;                                   # ≤ 500 open PRs
    closed) max_pages=2; sort="&sort=updated&direction=desc" ;;       # the 200 most recently updated
  esac
  while :; do
    resp="$(gh_get "/repos/${repo}/pulls?state=${state}${sort}&per_page=100&page=${page}")" || exit 1
    http="$(printf '%s' "$resp" | tail -n1)"
    body="$(printf '%s' "$resp" | sed '$d')"
    [ "$http" = "200" ] || die "listing $state PRs returned HTTP $http: $(printf '%s' "$body" | jq -r '.message // empty' 2>/dev/null)"
    acc="$(printf '%s\n%s' "$acc" "$body" | jq -cs '.[0] + .[1]')"   # via stdin: PR bodies overflow ARG_MAX
    n="$(printf '%s' "$body" | jq 'length')"
    [ "$n" -eq 100 ] && [ "$page" -lt "$max_pages" ] || break
    page=$((page + 1))
  done
  printf -v "$var" '%s' "$acc"
}
load_open_pulls() { load_pulls open; }

# Print "<number>\t<head.ref>" for the first PR in a list matching a jq boolean over one PR ($pr), or
# nothing. Usage: pull_where open|closed '<jq boolean>' — call load_pulls <state> in the calling
# shell first (this runs in a $(...)).
pull_where() {
  local var="${1}_pulls_json"
  printf '%s' "${!var}" | jq -r --arg slug "$slug" \
    "[.[] | . as \$pr | select($2)] | first // empty | \"\\(.number)\\t\\(.head.ref)\""
}
open_pull_where() { pull_where open "$1"; }

# jq filter: does $body carry the run's slug line? Either the spine Spec-table row
# (`| **Slug** | `<slug>` |`, compared with emphasis, backticks and spaces stripped, case-insensitive
# on the label) or the lane bullet (`- slug: <slug>`, compared trimmed). Exact — never a substring.
body_has_slug='(($body // "") | split("\n") | map(sub("\r$"; "")) | any(
    ((sub("^\\s+"; "") | sub("\\s+$"; "")) == ("- slug: " + $slug))
    or ((gsub("[*` \\t]"; "") | ascii_downcase) == ("|slug|" + ($slug | ascii_downcase) + "|"))
  ))'

# --- resolve ---------------------------------------------------------------------------------------

archived="$repo_root/$runs_archive_rel/$slug/run.md"   # runs_archive in .icm/project.json (lib/project.sh)
route=""

if [ -f "$run_md" ]; then
  # Already in the working tree — just make sure we're on the branch it records.
  route="run.md in the working tree"
  echo "run.md present for '$slug' — checking out its branch" >&2
  checkout_branch "$(branch_from_run_md "$run_md")"
elif [ -f "$archived" ]; then
  # After close-out, the run folder lives in the archive — check there.
  run_md="$archived"
  route="run.md in the archive"
  echo "run.md in archive for '$slug' — checking out its branch" >&2
  checkout_branch "$(branch_from_run_md "$run_md")"
else
  # Not in the tree — find the PR by slug through the repository's own pulls listing (body line,
  # then head branch; open PRs first, then the recently closed), then check out its head.
  gh_require "finding the run's PR"
  echo "run.md absent for '$slug' — finding the run's PR via the repository's pulls listing" >&2
  git -C "$repo_root" fetch origin --quiet || die "git fetch origin failed — check network"

  pr_number=""; head_branch=""

  # 1. Body scan over the open PRs — the slug line, matched exactly (body_has_slug).
  load_pulls open
  match="$(pull_where open "(\$pr.body as \$body | $body_has_slug)")"
  if [ -n "$match" ]; then
    route="PR body scan (open PRs)"
    pr_number="${match%%$'\t'*}"; head_branch="${match#*$'\t'}"
  fi

  # 2. Exact head branch claude/<slug> (plain local runs name the branch this way).
  if [ -z "$pr_number" ]; then
    owner="${repo%%/*}"
    h_enc="$(jq -rn --arg h "${owner}:claude/${slug}" '$h|@uri')"
    resp="$(gh_get "/repos/${repo}/pulls?state=open&head=${h_enc}&per_page=1")" || exit 1
    http="$(printf '%s' "$resp" | tail -n1)"
    body="$(printf '%s' "$resp" | sed '$d')"
    [ "$http" = "200" ] || die "listing PRs by head returned HTTP $http: $(printf '%s' "$body" | jq -r '.message // empty' 2>/dev/null)"
    match="$(printf '%s' "$body" | jq -r 'first // empty | "\(.number)\t\(.head.ref)"')"
    if [ -n "$match" ]; then
      route="PR head branch claude/${slug}"
      pr_number="${match%%$'\t'*}"; head_branch="${match#*$'\t'}"
    fi
  fi

  # 3. Head branch ending in -<slug> (a harness-named branch, e.g. claude/<hash>-<slug>).
  if [ -z "$pr_number" ]; then
    match="$(pull_where open '$pr.head.ref | endswith("-" + $slug)')"
    if [ -n "$match" ]; then
      route="PR head branch ending in -${slug}"
      pr_number="${match%%$'\t'*}"; head_branch="${match#*$'\t'}"
    fi
  fi

  # 4. The recently closed PRs — same matches. A run that merged without its close-out has no
  #    run.md in the archive yet; its PR is the only record of the branch.
  if [ -z "$pr_number" ]; then
    echo "no open PR carries the slug line or a matching head — checking the recently closed PRs" >&2
    load_pulls closed
    match="$(pull_where closed "(\$pr.body as \$body | $body_has_slug) or (\$pr.head.ref == (\"claude/\" + \$slug)) or (\$pr.head.ref | endswith(\"-\" + \$slug))")"
    if [ -n "$match" ]; then
      route="closed PR (body line or head branch)"
      pr_number="${match%%$'\t'*}"; head_branch="${match#*$'\t'}"
    fi
  fi

  [ -n "$pr_number" ] || stop "No PR found for slug '$slug' (no open or recently closed PR carries the slug line, and none has head claude/$slug or a head ending in -$slug) — Define has not run for it (or the slug is wrong)."
  [ -n "$head_branch" ] || die "PR #$pr_number has no head branch"

  echo "matched PR #$pr_number on branch $head_branch via $route" >&2
  checkout_branch "$head_branch"
fi

# --- verdict ---------------------------------------------------------------------------------------
# After checkout the run folder must be present. If it still isn't, Define genuinely never produced
# this run — STOP rather than fabricate it.

[ -f "$run_md" ] || stop "Still no run.md for '$slug' after checkout — Define has not produced this run. Do not create it; run 'new' (next intake stub, or 'new <stub-name>')."

branch="$(git -C "$repo_root" rev-parse --abbrev-ref HEAD)"
pr_line="$(grep -m1 '^- pr:' "$run_md" | sed -E 's/^- pr:[[:space:]]*//; s/[[:space:]]+#.*$//; s/[[:space:]]*$//' || true)"
echo "run '$slug' resolved via $route — branch: $branch${pr_line:+, pr: $pr_line}"
echo "RESULT: READY"
