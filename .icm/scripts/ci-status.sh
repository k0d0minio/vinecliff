#!/usr/bin/env bash
# ci-status.sh — wait for a run's CI to settle, then print one verdict: GREEN, RED or PENDING.
#
# The deterministic answer to "is this PR green?" (.icm/_shared/ci.md). It reads BOTH surfaces a
# commit's health lives on — GitHub Actions check runs AND commit statuses, where the Vercel
# preview deploys land — discards the known noise, and blocks until the run settles. The polling
# happens here, in bash, so a stage can genuinely wait for green or red without spending model
# turns on a sleep-and-re-read loop. Requires curl + jq.
#
# What it filters, and why (the full rationale is in .icm/_shared/ci.md):
#   * "Vercel Preview Comments" is a zero-second always-success marker, not a build — ignored.
#   * A Vercel status whose description reads "Canceled by Ignored Build Step" (turbo-ignore) or
#     "Skipped - Not affected" (Vercel's native unaffected-project skip) is a SKIPPED project, not
#     a passed one — its `state` is `success` either way, so the description is what decides.
#     Reported as skipped with that description, never as a built preview, never counted green.
#   * Check runs whose name ends in "(advisory)" are reported but can never make the verdict RED.
#   * A required check that has not appeared yet is PENDING, never GREEN — an empty check list on a
#     fresh push is CI not having started, not CI having passed.
#   * On a READY head, a declared product deploy project (.icm/project.json → deploy.projects,
#     class product) that has posted no status is UNPOSTED, and unposted is PENDING until the
#     script can tell a build that has not posted yet from the native unaffected-skip that will
#     never post: a Vercel deployment for the head (QUEUED, BUILDING, anything) is waited on; no
#     deployment once the grace window has passed is the native skip and settles. Without a Vercel
#     token, the grace window alone decides — and only when another product project HAS posted on
#     the head; with none posted at all, nothing is known and the run stays PENDING.
#
# Config is read straight from the process environment — this script does NOT load any .env file.
# The reads go through .icm/scripts/lib/gh.sh (curl with the token, else a logged-in `gh` CLI,
# else one die naming what this environment is missing):
#
#   GITHUB_TOKEN          (one*)      GitHub token (contents, pull-requests, issues).
#   GH_TOKEN              (one*)      Alternative name for the token (*one of the two, or a gh login).
#   GITHUB_REPO           (optional)  owner/repo. Default: derived from `origin` (lib/gh.sh).
#   GITHUB_API_URL        (optional)  API base. Default: https://api.github.com.
#   PIPELINE_REQUIRED_CHECKS (optional) NEWLINE-separated check-run names that must be present
#                                     and completed before a run can be GREEN. Newlines only: a
#                                     check name may itself contain a comma ("Format, lint,
#                                     typecheck" is ONE check), so a comma split would wait
#                                     forever on three phantom names. Default: the
#                                     `required_checks` array in .icm/project.json; empty means
#                                     nothing is waited for beyond the checks that appear.
#                                     A CONDITIONALLY required check — a preview smoke that is
#                                     owed only when a real preview was built on a ready head —
#                                     is never in this list: it is the `smoke_check` object in
#                                     .icm/project.json ({name, workflow, preview_status}),
#                                     derived per pass from the signals themselves (see the
#                                     loop below), because a draft head and a skipped preview
#                                     are never owed one.
#   PIPELINE_PREVIEW_GRACE (optional) Seconds after the head commit's committer time within which
#                                     an unposted product project is always waited on — Vercel's
#                                     queue can hold a build a while before its status posts.
#                                     Default 180. The committer time stands in for the push time
#                                     (Build's post-flip push is a fresh commit, so the two agree).
#   <deploy.token_env> / VERCEL_TOKEN (optional) Read through .icm/scripts/lib/vercel.sh to ask the
#                                     platform whether an unposted product project has a deployment
#                                     for the head. Absent, the grace rule above decides alone.
#
# Usage:
#   .icm/scripts/ci-status.sh <slug> [--timeout <seconds>] [--interval <seconds>] [--no-wait]
#   .icm/scripts/ci-status.sh --pr <number> [...]
#
# Verdict (stdout, last line):
#   RESULT: GREEN    exit 0  — every blocking check and status completed, none failed. Safe to
#                              merge or hand off. The only verdict either may rest on.
#   RESULT: RED      exit 3  — something blocking failed. STOP: read the logs, fix, push, re-run.
#   RESULT: PENDING  exit 4  — the wait timed out with the run unsettled (or a required check never
#                              registered). STOP and say so; re-run rather than assuming.
set -euo pipefail

command -v curl >/dev/null || { echo "curl not found" >&2; exit 1; }
command -v jq   >/dev/null || { echo "jq not found"   >&2; exit 1; }

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

die() { echo "error: $*" >&2; exit 1; }

# --- args ------------------------------------------------------------------------------------------

slug=""; pr_number=""; timeout=900; interval=20; wait=1
while [ $# -gt 0 ]; do
  case "$1" in
    --pr)       pr_number="${2:-}"; shift 2 ;;
    --timeout)  timeout="${2:-}";   shift 2 ;;
    --interval) interval="${2:-}";  shift 2 ;;
    --no-wait)  wait=0;             shift   ;;
    --*)        die "unknown flag: $1" ;;
    *)          [ -z "$slug" ] && slug="$1" || die "unexpected argument: $1"; shift ;;
  esac
done
[ -n "$slug" ] || [ -n "$pr_number" ] || die "usage: ci-status.sh <slug> | --pr <number> [--timeout s] [--interval s] [--no-wait]"

case "$timeout"  in ''|*[!0-9]*) die "--timeout must be a whole number of seconds" ;; esac
case "$interval" in ''|*[!0-9]*) die "--interval must be a whole number of seconds" ;; esac
[ "$interval" -ge 5 ] || die "--interval must be at least 5 seconds — don't hammer the API"

# --- config from env (lib/gh.sh: GH_API, repo, gh_token + the curl→gh fallback) --------------------

# shellcheck source=lib/gh.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/gh.sh"
# shellcheck source=lib/project.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/project.sh"
gh_require "reading the PR's checks"

# The environment's override, else the project manifest's list — split on newlines ONLY.
required_raw="${PIPELINE_REQUIRED_CHECKS:-}"
[ -n "$required_raw" ] || required_raw="$(project_list '.required_checks')"
required_checks="$(printf '%s' "$required_raw" | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//' | grep -v '^$' || true)"

# The project's conditionally required smoke check, if it declares one (.icm/project.json →
# smoke_check): the check-run NAME to wait for, the WORKFLOW file whose presence on the default
# branch says it is installed, and the commit-status CONTEXT of the preview it walks.
smoke_name="$(project_field '.smoke_check.name' '')"
smoke_workflow="$(project_field '.smoke_check.workflow' '')"
smoke_status="$(project_field '.smoke_check.preview_status' '')"

# The repo's product deploy projects, one "<status_context>\t<vercel project name>" line each
# (.icm/project.json → deploy.projects[], class product). On a READY head a product project with
# no status is UNPOSTED — a build that has not posted yet, or the native unaffected-skip that never
# will — and the settle loop resolves which before it may settle GREEN (`_shared/ci.md` → "An
# unposted product status is PENDING until it is explained").
product_projects="$([ -f "$project_json" ] && jq -r '(.deploy.projects // [])[] | select((.class // "product") == "product") | select(.status_context // "" | length > 0) | [.status_context, (.name // "")] | @tsv' "$project_json" 2>/dev/null || true)"

preview_grace="${PIPELINE_PREVIEW_GRACE:-180}"
case "$preview_grace" in ''|*[!0-9]*) die "PIPELINE_PREVIEW_GRACE must be a whole number of seconds" ;; esac

# The Vercel transport, for the one question the statuses cannot answer: does an unposted product
# project have a deployment for the head? Nothing is fetched at source time; no token → the grace
# rule decides alone.
if [ -n "$product_projects" ]; then
  # shellcheck source=lib/vercel.sh
  source "$(dirname "${BASH_SOURCE[0]}")/lib/vercel.sh"
fi

# A blocking GitHub GET. Echoes "<body>\n<http_code>"; the caller splits the status off the last line.
gh_get() { gh_api GET "$1"; }

api() { # api <path> <what> -> body on stdout, dies on non-200
  local resp http body
  resp="$(gh_get "$1")" || exit 1
  http="$(printf '%s' "$resp" | tail -n1)"
  body="$(printf '%s' "$resp" | sed '$d')"
  [ "$http" = "200" ] || die "reading $2 returned HTTP $http: $(printf '%s' "$body" | jq -r '.message // empty' 2>/dev/null)"
  printf '%s' "$body"
}

# --- resolve the PR ---------------------------------------------------------------------------------

# Located whenever a slug is given, independently of whether pr_number still needs resolving from
# it: run.md's own branch line is what the expected-head check below needs to tell whether this
# checkout IS the run's branch.
run_md=""
if [ -n "$slug" ]; then
  run_md="$repo_root/.icm/runs/$slug/run.md"
  if [ ! -f "$run_md" ]; then
    # After close-out, the run folder lives in the archive — check there so the
    # bare slug keeps working either side of the move.
    archived="$repo_root/$runs_archive_rel/$slug/run.md"
    [ -f "$archived" ] && run_md="$archived"
  fi
  [ -f "$run_md" ] || run_md=""
fi

if [ -z "$pr_number" ]; then
  [ -n "$run_md" ] || die "no .icm/runs/$slug/run.md in the working tree — run the stage preamble (resolve-run.sh $slug) first, or pass --pr <number>"
  pr_number="$(grep -m1 '^- pr:' "$run_md" \
    | sed -E 's/^- pr:[[:space:]]*//; s/[[:space:]]+#.*$//; s#^.*/pull/##; s/^#//; s/[^0-9].*$//' || true)"
  [ -n "$pr_number" ] || die "run.md for '$slug' has no usable '- pr:' line — Define has not opened the PR (or pass --pr <number>)"
fi
case "$pr_number" in ''|*[!0-9]*) die "PR number must be numeric, got: $pr_number" ;; esac

# Expected head: this checkout is the run's own branch (run.md → '- branch:') and that branch is
# already pushed — the pushed SHA is what the caller means by "the run's CI". Outside a matching,
# pushed checkout (no run.md, a different branch, an unpushed head, no git) this stays empty and
# nothing below changes.
expected_sha=""
if [ -n "$run_md" ] && command -v git >/dev/null 2>&1; then
  run_branch="$(grep -m1 '^- branch:' "$run_md" 2>/dev/null \
    | sed -E 's/^- branch:[[:space:]]*//; s/[[:space:]]+#.*$//; s/[[:space:]]*$//')"
  current_branch="$(git -C "$repo_root" rev-parse --abbrev-ref HEAD 2>/dev/null || true)"
  if [ -n "$run_branch" ] && [ "$run_branch" = "$current_branch" ]; then
    local_head="$(git -C "$repo_root" rev-parse HEAD 2>/dev/null || true)"
    upstream_head="$(git -C "$repo_root" rev-parse '@{upstream}' 2>/dev/null || true)"
    [ -n "$local_head" ] && [ "$local_head" = "$upstream_head" ] && expected_sha="$local_head"
  fi
fi

pr_json="$(api "/repos/${repo}/pulls/${pr_number}" "PR #$pr_number")"
head_sha="$(printf '%s' "$pr_json" | jq -r '.head.sha // empty')"
[ -n "$head_sha" ] || die "PR #$pr_number has no head SHA"

deadline=$(( SECONDS + timeout ))

# Never verdict on a head that predates a push the caller just made. The settle loop below re-reads
# the PR each pass, but that only catches a push landing MID-wait — nothing, until now, compared
# the PR against a push already made before this script's FIRST read, so a read landing in the
# window before GitHub moves the PR (10–30s is routine) would settle a verdict about the old head
# (.icm/_shared/ci.md — "a stage never … declares done on a verdict it did not actually
# establish"). Poll — within the one timeout the whole call gets — until the PR catches up.
if [ -n "$expected_sha" ] && [ "$head_sha" != "$expected_sha" ]; then
  echo "waiting for GitHub to register ${expected_sha:0:7} on PR #$pr_number (currently ${head_sha:0:7})" >&2
  while [ "$head_sha" != "$expected_sha" ]; do
    if [ "$wait" -eq 0 ] || [ "$SECONDS" -ge "$deadline" ]; then
      echo "PR #$pr_number never registered ${expected_sha:0:7} within ${timeout}s (still at ${head_sha:0:7}) — this is NOT a pass" >&2
      echo "RESULT: PENDING"; exit 4
    fi
    sleep "$interval"
    pr_json="$(api "/repos/${repo}/pulls/${pr_number}" "PR #$pr_number")"
    head_sha="$(printf '%s' "$pr_json" | jq -r '.head.sha // empty')"
    [ -n "$head_sha" ] || die "PR #$pr_number has no head SHA"
  done
  echo "PR #$pr_number now at ${head_sha:0:7} — matches the pushed head" >&2
fi

pr_state="$(printf '%s' "$pr_json" | jq -r '.state // empty')"
pr_merged="$(printf '%s' "$pr_json" | jq -r '.merged // false')"
pr_draft="$(printf '%s' "$pr_json" | jq -r '.draft // false')"

# Which tier this verdict settles (blind-until-ready — _shared/ci.md). A DRAFT head runs the
# cheap tier and produces NO product-app previews at all: zero
# Vercel statuses on a draft is the designed state, not a hole in the evidence, and the verdict
# arithmetic below is already correct for it — a status that never exists is never waited on.
# A READY head owes the full gate, and its affected product-app previews arrive as statuses.
if [ "$pr_draft" = "true" ]; then
  tier="cheap tier (draft — blind-until-ready, no previews expected)"
else
  tier="full gate (ready)"
fi

# Is the project's smoke check actually installed? A workflow that triggers on the `status`
# event runs from the DEFAULT BRANCH only — it reports nothing until it is merged there, and a
# branch that merely CONTAINS the file produces no check. Asked once, of the default branch, not of
# the PR: requiring a check that cannot exist yet would hang every ready PR at PENDING, the PR
# introducing the workflow first among them. A project with no `smoke_check` skips all of this.
smoke_installed=0
if [ -n "$smoke_name" ] && [ -n "$smoke_workflow" ] && [ -n "$smoke_status" ]; then
  default_branch="$(printf '%s' "$pr_json" | jq -r '.base.repo.default_branch // "main"')"
  smoke_resp="$(gh_get "/repos/${repo}/contents/${smoke_workflow}?ref=${default_branch}")" || exit 1
  smoke_probe="$(printf '%s' "$smoke_resp" | tail -n1)"
  case "$smoke_probe" in
    200) smoke_installed=1 ;;
    404) smoke_installed=0 ;;
    # Anything else is an unanswered question, not a "no". Treating a 403 or a 5xx as "not installed"
    # would silently drop the check from the required set and let the run settle GREEN without it —
    # the precise failure this file exists to forbid.
    *)   die "could not tell whether ${smoke_workflow} is on ${default_branch} (HTTP $smoke_probe) — re-run rather than settling a verdict without knowing" ;;
  esac
fi

# The workflow refuses a forked head — it will not run that code with the preview environment's
# secrets — so a fork PR is never owed a check either. Mirrored here rather than inferred, so the
# two guards cannot drift apart and strand a ready fork PR at PENDING.
pr_head_repo="$(printf '%s' "$pr_json" | jq -r '.head.repo.full_name // empty')"

echo "PR #$pr_number (${pr_state}${pr_merged:+, merged: $pr_merged}, draft: $pr_draft) — head ${head_sha:0:7} — settling the ${tier}" >&2

# --- one read of both surfaces ----------------------------------------------------------------------
# Emits one TSV line per meaningful signal:  <class>\t<state>\t<name>\t<detail>\t<neutral_title>
# class:  blocking | advisory | skipped | noise
# state:  pass | fail | pending
# detail: the check's or deployment's URL — except for a skipped Vercel project, where it is the
#         status DESCRIPTION (the skip reason). A skipped project has no preview at that URL, so
#         the URL is never offered; the reason is what the operator needs to see.
# neutral_title: for a check run that concluded `neutral`, its output title — the reason nothing
#         was verified (a smoke check saying "The preview environment is not configured", or that
#         its kill switch is on). Empty for every other signal. `neutral` is a pass to the verdict
#         arithmetic, so without this column the reason would never reach the report.
read_signals() {
  local checks statuses
  checks="$(api "/repos/${repo}/commits/${head_sha}/check-runs?per_page=100" "check runs for ${head_sha:0:7}")"
  statuses="$(api "/repos/${repo}/commits/${head_sha}/status?per_page=100" "commit statuses for ${head_sha:0:7}")"

  # Dedupe by check name, newest attempt wins. A re-run (or a concurrency cancel followed by a
  # fresh run) leaves BOTH attempts on the SHA, and the API does not collapse them across check
  # suites — reading the stale one is how a green PR reports RED forever.
  printf '%s' "$checks" | jq -r '
    (.check_runs // [])
    | group_by(.name) | map(sort_by(.started_at, .id) | last)[]
    | . as $c
    | (if   ($c.name | test("Vercel Preview Comments")) then "noise"
       elif ($c.name | test("\\(advisory\\)$"))         then "advisory"
       else "blocking" end) as $class
    | (if   $c.status != "completed"                    then "pending"
       elif ($c.conclusion // "") | IN("success","neutral","skipped") then "pass"
       else "fail" end) as $state
    | (if $c.status == "completed" and ($c.conclusion // "") == "neutral" then ($c.output.title // "") else "" end) as $neutral_title
    | [$class, $state, $c.name, ($c.details_url // ""), $neutral_title] | @tsv
  '

  # Vercel deploys land here, not in check runs. Vercel posts `state: success` for a project it
  # did NOT build — "Canceled by Ignored Build Step" (turbo-ignore) and "Skipped - Not affected"
  # (the native unaffected-project skip) — so the description, not the state, is what says whether
  # a preview exists (.icm/_shared/ci.md → "An absent status is not a skipped one"). A skip has no
  # preview, so it is neither a pass nor a failure, and its target_url is not a preview to offer:
  # the detail column carries the skip reason instead.
  printf '%s' "$statuses" | jq -r '
    (.statuses // [])
    | group_by(.context) | map(max_by(.created_at))[]   # newest status per context wins
    | . as $s
    | ($s.description // "") as $desc
    | (if ($desc | test("Ignored Build Step|Skipped|Not affected"; "i")) then "skipped" else "blocking" end) as $class
    | (if   $class == "skipped"                  then "skipped"
       elif $s.state == "pending"                then "pending"
       elif $s.state == "success"                then "pass"
       else "fail" end) as $state
    | [$class, $state, $s.context, (if $class == "skipped" then $desc else ($s.target_url // "") end), ""] | @tsv
  '
}

# --- the unposted product projects -------------------------------------------------------------------
# A declared product project with no status on a READY head is not "absent" by default — Vercel can
# hold a build QUEUED or BUILDING before its status posts (sustentus PR 1162: GREEN "settled on the
# full gate" while `web` was BUILDING). Each pass resolves every unposted one to exactly one of:
#   wait     — a deployment exists for the head, or the grace window is still open, or nothing can
#              explain the silence. Keeps the run PENDING, exactly like a pending status.
#   settled  — no deployment for the head once the grace window has passed (the native
#              unaffected-skip, confirmed by the platform), or — with no token to ask — the grace
#              window has passed and another product project HAS posted on this head.
# Sets unposted_wait (context names, comma-joined) and unposted_notes (one report line each).

head_epoch_sha=""; head_epoch=""
head_commit_epoch() { # sets head_epoch: the head commit's committer time in epoch seconds — one read per head
  [ "$head_epoch_sha" != "$head_sha" ] || return 0
  # Called directly, never in $(…), so the cache survives the pass. An unreadable answer leaves
  # head_epoch empty — an unanswered question, which the caller reads as the window still open.
  head_epoch="$(api "/repos/${repo}/commits/${head_sha}" "commit ${head_sha:0:7}" 2>/dev/null \
    | jq -r '(.commit.committer.date // .commit.author.date // empty) | sub("\\.[0-9]+"; "") | fromdateiso8601? // empty' 2>/dev/null)" \
    || head_epoch=""
  head_epoch_sha="$head_sha"
}

resolve_unposted() {
  unposted_wait=""; unposted_notes=""
  [ -n "$product_projects" ] && [ "$pr_draft" != "true" ] || return 0

  local ctx name unposted="" any_posted=0 now epoch grace_left deps state count note token_note
  # Names the token, never prints it.
  if [ -n "${vercel_token:-}" ]; then token_note="the ${vercel_token_name} read failed"; else token_note="${vercel_token_name:-VERCEL_TOKEN} not set"; fi
  while IFS=$'\t' read -r ctx name; do
    [ -n "$ctx" ] || continue
    if printf '%s\n' "$signals" | awk -F'\t' -v c="$ctx" '$3==c' | grep -q .; then
      any_posted=1
    else
      unposted="${unposted}${ctx}"$'\t'"${name}"$'\n'
    fi
  done <<< "$product_projects"
  [ -n "$unposted" ] || return 0

  now="$(date +%s)"
  head_commit_epoch; epoch="$head_epoch"
  # An unreadable commit time is an unanswered question: the window is treated as still open.
  if [ -n "$epoch" ]; then grace_left=$(( epoch + preview_grace - now )); else grace_left="$preview_grace"; fi

  while IFS=$'\t' read -r ctx name; do
    [ -n "$ctx" ] || continue
    state=""; count=""
    if [ -n "${vercel_token:-}" ] && [ -n "$name" ]; then
      # A failed read is "unknown", never "no deployment" — it falls through to the grace rule.
      if deps="$( (vercel_deployments "$name" --sha "$head_sha" --limit 5) 2>/dev/null )"; then
        count="$(printf '%s' "$deps" | jq 'length' 2>/dev/null || echo "")"
        state="$(printf '%s' "$deps" | jq -r 'sort_by(-(.created // 0)) | first | (.state // .readyState // empty)' 2>/dev/null || true)"
      fi
    fi

    if [ -n "$count" ] && [ "$count" -gt 0 ]; then
      note="[PENDING] $ctx: Vercel has a ${state:-?} deployment for ${head_sha:0:7}, status not yet posted — waited on"
      unposted_wait="${unposted_wait:+$unposted_wait, }$ctx"
    elif [ "$grace_left" -gt 0 ]; then
      note="[PENDING] $ctx: no status on ${head_sha:0:7} yet — within the ${preview_grace}s grace window (${grace_left}s left), waited on"
      unposted_wait="${unposted_wait:+$unposted_wait, }$ctx"
    elif [ "$count" = "0" ]; then
      note="[INFO] $ctx: no status and no Vercel deployment for ${head_sha:0:7} after the ${preview_grace}s grace window — the native unaffected-skip; nothing built, nothing to smoke"
    elif [ "$any_posted" -eq 1 ]; then
      note="[INFO] $ctx: no status on ${head_sha:0:7} after the ${preview_grace}s grace window while another product project posted — read as the native unaffected-skip, UNVERIFIED (${token_note}; the platform did not confirm it)"
    else
      note="[PENDING] $ctx: no status on ${head_sha:0:7} and no product project has posted — cannot tell a build that has not posted from the native skip; set ${vercel_token_name:-VERCEL_TOKEN} so the platform can answer"
      unposted_wait="${unposted_wait:+$unposted_wait, }$ctx"
    fi
    unposted_notes="${unposted_notes}${note}"$'\n'
  done <<< "$unposted"
}

# --- wait for the run to settle ----------------------------------------------------------------------
# deadline was set above, before the expected-head wait — the two share one timeout budget.

verdict=""
signals=""
unposted_wait=""; unposted_notes=""

while :; do
  # Re-read the head each pass: a push landing mid-wait moves the SHA, and a verdict about the
  # old head is a verdict about code that is no longer on the branch. The draft flag comes off the
  # same read — a flip mid-wait changes which tier is owed, and with it whether the preview smoke
  # is required below.
  pr_poll="$(api "/repos/${repo}/pulls/${pr_number}" "PR #$pr_number")"
  latest_sha="$(printf '%s' "$pr_poll" | jq -r '.head.sha // empty')"
  pr_draft="$(printf '%s' "$pr_poll" | jq -r '.draft // false')"
  if [ -n "$latest_sha" ] && [ "$latest_sha" != "$head_sha" ]; then
    echo "head moved ${head_sha:0:7} → ${latest_sha:0:7} — a new push restarts the wait" >&2
    head_sha="$latest_sha"
  fi

  signals="$(read_signals)"

  # The project's smoke check is required only when it is actually owed — the same four
  # conditions such a workflow applies: it is installed on the default branch, the head is READY,
  # the head is not a fork (both above), and the preview status it walks (`smoke_check.preview_status`)
  # is a REAL build. On a draft head there is no preview (blind-until-ready), and a preview the
  # deploy skipped lands in the `skipped` class rather than `pass` — none of those earns a walk,
  # and none may wait on one. Deriving it from the signals already read, rather than adding it to
  # PIPELINE_REQUIRED_CHECKS, is what keeps that conditionality honest: the static list would
  # demand the check on every PR, and hang forever on the ones that never get it.
  # (.icm/_shared/ci.md → "The smoke check is required conditionally".)
  effective_required="$required_checks"
  if [ "$smoke_installed" -eq 1 ] && [ "$pr_draft" != "true" ] && [ "$pr_head_repo" = "$repo" ] \
    && printf '%s\n' "$signals" | awk -F'\t' -v s="$smoke_status" '$1=="blocking" && $2=="pass" && $3==s' | grep -q .; then
    if [ -n "$effective_required" ]; then
      effective_required="$effective_required"$'\n'"$smoke_name"
    else
      effective_required="$smoke_name"
    fi
  fi

  blocking_fail="$(printf '%s\n' "$signals" | awk -F'\t' '$1=="blocking" && $2=="fail"'   || true)"
  blocking_wait="$(printf '%s\n' "$signals" | awk -F'\t' '$1=="blocking" && $2=="pending"' || true)"

  # A declared product project with no status on a ready head keeps the run PENDING until it is
  # explained — a deployment still building, or the native skip confirmed (resolve_unposted above).
  resolve_unposted

  # A required check that has not registered yet keeps the run PENDING — an empty list is CI not
  # having started, never CI having passed.
  missing_required=""
  if [ -n "$effective_required" ]; then
    while IFS= read -r req; do
      [ -n "$req" ] || continue
      printf '%s\n' "$signals" | awk -F'\t' -v r="$req" '$3==r && $2!="pending"' | grep -q . \
        || missing_required="${missing_required:+$missing_required, }$req"
    done <<< "$effective_required"
  fi

  if [ -n "$blocking_fail" ]; then
    verdict="RED"; break                       # a failure is final — later checks cannot un-fail it
  elif [ -z "$blocking_wait" ] && [ -z "$missing_required" ] && [ -z "$unposted_wait" ]; then
    verdict="GREEN"; break
  fi

  if [ "$wait" -eq 0 ] || [ "$SECONDS" -ge "$deadline" ]; then
    verdict="PENDING"; break
  fi

  waiting_on="$(printf '%s\n' "$blocking_wait" | awk -F'\t' 'NF{print $3}' | paste -sd', ' - || true)"
  echo "waiting ${interval}s — unsettled: ${waiting_on:-none}${missing_required:+; not yet registered: $missing_required}${unposted_wait:+; product previews not yet posted: $unposted_wait}" >&2
  sleep "$interval"
done

# --- report ------------------------------------------------------------------------------------------

emit() { # emit <heading> <awk-filter>
  local rows; rows="$(printf '%s\n' "$signals" | awk -F'\t' "$2" || true)"
  [ -n "$rows" ] || return 0
  echo "$1" >&2
  printf '%s\n' "$rows" | awk -F'\t' 'NF{printf "  %-9s %s%s\n", $2, $3, ($4=="" ? "" : "  " $4)}' >&2
}

emit "Blocking:" '$1=="blocking"'
# A `neutral` smoke check passes the verdict arithmetic but smoked nothing — the check's own
# title says why (an unconfigured preview environment, the kill switch). Print it here, next to
# the verdict, so a GREEN cannot hide a walk that never happened.
smoke_neutral=""
[ -z "$smoke_name" ] || smoke_neutral="$(printf '%s\n' "$signals" | awk -F'\t' -v s="$smoke_name" '$3==s && $5!="" {print $5; exit}' || true)"
[ -z "$smoke_neutral" ] || echo "${smoke_name}: neutral — ${smoke_neutral} (nothing was smoked; a pass to the verdict, not a walk)" >&2
emit "Advisory (never blocks a merge):" '$1=="advisory"'
emit "Previews built for this commit:" '$1=="blocking" && $3 ~ /^Vercel/ && $2=="pass"'
if [ "$pr_draft" != "true" ] && ! printf '%s\n' "$signals" | awk -F'\t' '$1=="blocking" && $3 ~ /^Vercel/ && $2=="pass"' | grep -q .; then
  # Said out loud rather than left as a missing heading: a ready head with nothing built has
  # nothing to smoke, and silence here is how a skipped project used to pass as a preview.
  echo "Previews built for this commit: none — every Vercel project was skipped or is still pending; there is no preview URL to test against" >&2
fi
emit "Vercel projects skipped for this diff (no preview — not a pass; reason shown):" '$1=="skipped"'

if [ "$pr_draft" = "true" ]; then
  echo "Previews: suppressed — draft. Product apps preview from the ready flip; quiet apps build on merge." >&2
elif [ -n "$unposted_notes" ]; then
  # Each declared product project that posted nothing on this READY head, and what the last pass
  # concluded about it: still waited on ([PENDING]) or explained as the native skip ([INFO]).
  printf '%s' "$unposted_notes" >&2
fi

case "$verdict" in
  GREEN)
    echo "every blocking check and status completed without failure — settled on the ${tier}"
    echo "RESULT: GREEN"; exit 0 ;;
  RED)
    echo "failing: $(printf '%s\n' "$blocking_fail" | awk -F'\t' 'NF{print $3}' | paste -sd', ' -)" >&2
    echo "read the failing job (get_job_logs, failed_only: true), fix on the branch, push, then re-run this call"
    echo "RESULT: RED"; exit 3 ;;
  *)
    if [ "$wait" -eq 0 ]; then
      echo "run is unsettled${missing_required:+ (never registered: $missing_required)}${unposted_wait:+ (product previews not yet posted: $unposted_wait)} and --no-wait was passed — this is NOT a pass" >&2
    else
      echo "still unsettled after ${timeout}s${missing_required:+ (never registered: $missing_required)}${unposted_wait:+ (product previews not yet posted: $unposted_wait)} — this is NOT a pass" >&2
    fi
    echo "RESULT: PENDING"; exit 4 ;;
esac
