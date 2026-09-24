#!/usr/bin/env bash
# deploy-status.sh — read production ONCE after a merge: is the merge commit live? (TEMPLATE-OWNED)
#
# Release step 9 calls this after the squash-merge and writes what it says into the Release
# record as one `- production:` line. That is the whole of the pipeline's post-release health
# check (agency brief §4.3, decision 6): one read, written down, and the human decides. Nothing
# here watches, retries beyond its own bounded wait, un-merges, or starts anything — an ERROR is
# a line in the record and a pointer at the hotfix lane, not an action.
#
# For every project in the repo's deploy block (`.icm/project.json` → deploy.projects — the
# repo's own; lib/vercel.sh is the transport, the token is named there) it finds the production
# deployment of the merge commit (`GET /v6/deployments?projectId=…&target=production&sha=…`),
# waits until its state settles — READY, ERROR or CANCELED, bounded like ci-status.sh — and
# prints per project: state, URL, deployment id, and the PREVIOUS READY production deployment's
# id (the newest READY one created before this — what `rollback.sh --vercel` names). Quiet
# projects (`class: quiet`) build on the default branch too, so they are read like product ones.
#
# Vercel's `sha=` filter matches the full 40-character SHA only, so a short --sha is expanded
# through the repo's git first; where that fails, or the filter finds nothing, the project's
# newest deployments are read and `meta.githubCommitSha` matched by prefix. A deployment the
# project's Ignored Build Step canceled (a merge that touches none of the project's inputs) is
# SKIPPED, not an incident: production still serves the previous READY deployment, named on the
# line. CANCELED stays with ERROR only when it was not the ignore step — a person, or a newer push.
#
# Read-only in the strong sense: GET only, the CLI never run, nothing written but stdout.
#
# --uat — where the repo declares a UAT environment (.icm/project.json → uat: {target, url};
# `.icm/_shared/promotion.md`; decision D39), Release reads the UAT environment's deployment of the
# merge commit once: for each product project, the deployment of the SHA whose custom environment
# is `uat.target` (the list item's `customEnvironment` — matched on its slug, or on the id
# `GET /v9/projects/<name>/custom-environments` gives for the slug; which of the two Vercel's v6
# list exposes is proven on the first real UAT repo, so both are read). Quiet projects carry no
# UAT environment and are skipped, named. The record line is `- uat: READY on <sha> — <project>
# dpl_… · <uat.url>`; no previous-deployment id is looked up (a broken UAT build is a bug lane,
# and the address keeps serving its last READY deployment).
#
# Without --uat on a UAT repo, the read is the production BUILD of the SHA: a Staged deployment
# is READY and not yet serving — whether it is Current is `promote.sh status`'s line, and the
# release workflow reads this once after it promoted.
#
# Usage:
#   .icm/scripts/deploy-status.sh <slug> [--timeout <seconds>] [--interval <seconds>] [--no-wait] [--uat]
#   .icm/scripts/deploy-status.sh --sha <merge-sha> [...]
#   (<slug> resolves the merge SHA from the run's PR: run.md → `- pr:` → the PR's merge_commit_sha,
#    or its head SHA when it has not merged yet; --sha bypasses GitHub entirely.)
#
# Verdict (stdout, last line):
#   RESULT: READY                 exit 0  — every declared project's deployment of this SHA is READY,
#                                           or SKIPPED by its ignore step (at least one READY)
#   RESULT: ERROR <project…>      exit 3  — at least one is ERROR or CANCELED (named). See the hotfix lane.
#   RESULT: PENDING               exit 4  — the wait ran out with a deployment unsettled or not yet created
#   RESULT: SKIP                  exit 0  — every project SKIPPED by its ignore step (production unchanged:
#                                           `- production: SKIPPED on <sha> — …`), or no deploy block
#                                           (`production: not declared (no deploy block)`)
set -euo pipefail

command -v curl >/dev/null || { echo "curl not found" >&2; exit 1; }
command -v jq   >/dev/null || { echo "jq not found"   >&2; exit 1; }

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
die() { echo "error: $*" >&2; exit 1; }

slug=""; sha=""; timeout=600; interval=20; wait=1; uat=0
while [ $# -gt 0 ]; do
  case "$1" in
    --sha)      sha="${2:-}"; shift 2 ;;
    --timeout)  timeout="${2:-}"; shift 2 ;;
    --interval) interval="${2:-}"; shift 2 ;;
    --no-wait)  wait=0; shift ;;
    --uat)      uat=1; shift ;;
    --*)        die "unknown flag: $1" ;;
    *)          [ -z "$slug" ] && slug="$1" || die "unexpected argument: $1"; shift ;;
  esac
done
[ -n "$slug" ] || [ -n "$sha" ] || die "usage: deploy-status.sh <slug> | --sha <merge-sha> [--timeout s] [--interval s] [--no-wait] [--uat]"
case "$timeout"  in ''|*[!0-9]*) die "--timeout must be a whole number of seconds" ;; esac
case "$interval" in ''|*[!0-9]*) die "--interval must be a whole number of seconds" ;; esac
[ "$interval" -ge 5 ] || die "--interval must be at least 5 seconds"

# shellcheck source=lib/project.sh
source "$here/lib/project.sh"
# shellcheck source=lib/vercel.sh
source "$here/lib/vercel.sh"

label="production"; ut=""; uat_suffix=""
if [ "$uat" -eq 1 ]; then
  uat_declared || die "--uat needs a UAT environment declared in .icm/project.json (uat.target + uat.url) — /setup declares one; without one Release reads production"
  label="uat"; ut="$(uat_target)"; uat_suffix=" · $(uat_url)"
fi
if ! vercel_declared; then
  echo "$label: not declared (no deploy block)"
  echo "RESULT: SKIP"; exit 0
fi
vercel_require "reading $label"

# --- resolve the SHA from the run's PR when a slug was given --------------------------------------------

if [ -z "$sha" ]; then
  run_md="$repo_root/.icm/runs/$slug/run.md"
  [ -f "$run_md" ] || run_md="$repo_root/$runs_archive_rel/$slug/run.md"
  [ -f "$run_md" ] || die "no run.md for '$slug' in .icm/runs/ or $runs_archive_rel/ — pass --sha <merge-sha>"
  pr="$(grep -m1 '^- pr:' "$run_md" | sed -E 's/^- pr:[[:space:]]*//; s/[[:space:]]+#.*$//; s#^.*/pull/##; s/^#//; s/[^0-9].*$//' || true)"
  [ -n "$pr" ] || die "run.md for '$slug' has no usable '- pr:' line — pass --sha <merge-sha>"
  # shellcheck source=lib/gh.sh
  source "$here/lib/gh.sh"
  gh_require "reading PR #$pr"
  resp="$(gh_api GET "/repos/${repo}/pulls/${pr}")" || exit 1
  [ "$(printf '%s' "$resp" | tail -n1)" = "200" ] || die "PR #$pr returned HTTP $(printf '%s' "$resp" | tail -n1)"
  sha="$(printf '%s' "$resp" | sed '$d' | jq -r 'if .merged then .merge_commit_sha else .head.sha end')"
  echo "PR #$pr → $(printf '%s' "$resp" | sed '$d' | jq -r 'if .merged then "merged as" else "not merged — head" end') ${sha:0:7}" >&2
fi

# Vercel's sha filter wants the full SHA; expand a short one where the repo's git knows it.
if [ "${#sha}" -lt 40 ]; then
  full="$(git -C "$repo_root" rev-parse --verify --quiet "${sha}^{commit}" 2>/dev/null || true)"
  [ -z "$full" ] || sha="$full"
fi

# The deployment of $sha for <name>, newest first — under `--uat`, only the one whose custom
# environment is uat.target (by slug, or by the environment's id). The sha filter first (full SHA
# only); else the newest deployments, matched on meta.githubCommitSha.
pick='sort_by(-.created) | first // empty'
[ "$uat" -eq 0 ] || pick='[.[] | select(((.customEnvironment.slug // "") == $t) or ($id != "" and ((.customEnvironment.id // "") == $id)) or ((.target // "") == $t))] | sort_by(-.created) | first // empty'
declare -A env_ids=()
uat_env_id() { # <name> → the custom environment's id for uat.target, '' when unknown
  local resp
  if [ -z "${env_ids[$1]+x}" ]; then
    env_ids[$1]=""
    resp="$(vercel_get "/v9/projects/$1/custom-environments")" || true
    if [ "$(_vercel_code "$resp")" = "200" ]; then
      env_ids[$1]="$(_vercel_body "$resp" | jq -r --arg t "$ut" '[(.environments // [])[] | select(.slug == $t)] | first | .id // empty')"
    fi
  fi
  printf '%s' "${env_ids[$1]}"
}
find_deployment() { # <name>
  local name="$1" deps="" tgt=() eid=""
  if [ "$uat" -eq 1 ]; then eid="$(uat_env_id "$name")"; else tgt=(--target production); fi
  if [ "${#sha}" -eq 40 ]; then
    deps="$(vercel_deployments "$name" ${tgt[@]+"${tgt[@]}"} --sha "$sha" --limit 10)"
  fi
  if [ -z "$deps" ] || [ "$deps" = "[]" ]; then
    deps="$(vercel_deployments "$name" ${tgt[@]+"${tgt[@]}"} --limit 20 \
      | jq -c --arg s "$sha" '[.[] | select((.meta.githubCommitSha // "") | startswith($s))]')"
  fi
  printf '%s' "$deps" | jq -c --arg t "$ut" --arg id "$eid" "$pick"
}

# --- one read per project, bounded -----------------------------------------------------------------------

deadline=$(( SECONDS + timeout ))
mapfile -t projects < <(deploy_projects)
verdict="READY"; errored=""; lines=(); ready=0; ignored=0

for pj in "${projects[@]}"; do
  name="$(printf '%s' "$pj" | jq -r '.name')"
  class="$(printf '%s' "$pj" | jq -r '.class // "product"')"
  if [ "$uat" -eq 1 ] && [ "$class" = "quiet" ]; then
    lines+=("$name ($class): skipped — a quiet project carries no UAT environment")
    continue
  fi
  state=""; dpl_id=""; dpl_url=""; created=""
  while :; do
    # Under --uat: the custom environment's deployment of this SHA, built from main on the merge.
    dpl="$(find_deployment "$name")"
    if [ -n "$dpl" ]; then
      state="$(printf '%s' "$dpl" | jq -r '.state // .readyState // "UNKNOWN"')"
      dpl_id="$(printf '%s' "$dpl" | jq -r '.uid // .id')"
      dpl_url="$(printf '%s' "$dpl" | jq -r '.url // empty')"
      created="$(printf '%s' "$dpl" | jq -r '.created // 0')"
      # The ignore step's cancel carries Vercel's own words on the list item; nothing else does.
      if [ "$state" = "CANCELED" ] && printf '%s' "$dpl" | jq -e '(.errorMessage // "") | test("Ignored Build Step"; "i")' >/dev/null; then
        state="SKIPPED"
      fi
      case "$state" in READY|ERROR|CANCELED|SKIPPED) break ;; esac
    fi
    if [ "$wait" -eq 0 ] || [ "$SECONDS" -ge "$deadline" ]; then break; fi
    echo "$name: ${state:-no deployment of ${sha:0:7} yet} — waiting ${interval}s" >&2
    sleep "$interval"
  done

  # The previous READY production deployment — newest created before this one — the rollback
  # candidate rollback.sh names. Read once, never acted on here.
  prev_id=""
  if [ -n "$dpl_id" ] && [ "$uat" -eq 0 ]; then
    prev_id="$(vercel_deployments "$name" --target production --limit 20 \
      | jq -r --arg id "$dpl_id" --argjson c "${created:-0}" \
          '[.[] | select((.uid // .id) != $id and ((.state // .readyState) == "READY") and (.created < $c))] | sort_by(-.created) | first | (.uid // .id) // empty')"
  fi

  case "$state" in
    READY)          lines+=("$name ($class): READY — https://${dpl_url} — ${dpl_id}${prev_id:+ (prev ${prev_id})}"); ready=1 ;;
    SKIPPED)        if [ "$uat" -eq 1 ]; then lines+=("$name ($class): SKIPPED — ignore step, the UAT address keeps its last READY — canceled ${dpl_id}")
                    else lines+=("$name ($class): SKIPPED — ignore step, live ${prev_id:-its last READY} — canceled ${dpl_id}"); fi
                    ignored=1 ;;
    ERROR|CANCELED) if [ "$uat" -eq 1 ]; then lines+=("$name ($class): $state — ${dpl_id} — the UAT address keeps its last READY deployment; fix it through a bug lane")
                    else lines+=("$name ($class): $state — ${dpl_id}${prev_id:+ (prev ${prev_id})} — see the hotfix lane (rollback.sh --sha $sha --vercel names the recovery)"); fi
                    errored="${errored:+$errored }$name"; verdict="ERROR" ;;
    "")             lines+=("$name ($class): PENDING — not created — no $label deployment of ${sha:0:7} yet"); [ "$verdict" = "ERROR" ] || verdict="PENDING" ;;
    *)              lines+=("$name ($class): $state — ${dpl_id} (unsettled)"); [ "$verdict" = "ERROR" ] || verdict="PENDING" ;;
  esac
done

# Every project skipped by its ignore step: nothing deployed, production unchanged.
[ "$verdict" != "READY" ] || [ "$ready" -eq 1 ] || [ "$ignored" -eq 0 ] || verdict="SKIPPED"

printf '%s\n' "${lines[@]}"
# The one line Release copies into its record.
record="$(printf '%s\n' "${lines[@]}" | awk -F' — ' '{ split($1, a, " "); printf "%s%s %s", (NR>1 ? " · " : ""), a[1], $2 }' )"
echo "- $label: $verdict on ${sha:0:7} — $record$uat_suffix"

case "$verdict" in
  READY)   echo "RESULT: READY"; exit 0 ;;
  SKIPPED) echo "RESULT: SKIP"; exit 0 ;;
  ERROR)   echo "RESULT: ERROR $errored"; exit 3 ;;
  *)       echo "RESULT: PENDING"; exit 4 ;;
esac
