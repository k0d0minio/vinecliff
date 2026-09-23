#!/usr/bin/env bash
# new-run.sh — scaffold a pipeline run: commit it, open its PR, label it, consume the stub.
#
# Two modes:
#   • Spine (default) — the mechanical half of Define (.icm/stages/02_define/CONTEXT.md).
#     Define writes spec.md and hands the one-line PR Summary in via --summary; this script commits
#     the run + pushes, opens the DRAFT PR with a body projected from spec.md (project-body.sh —
#     template headings + both gate anchors + acceptance criteria mirrored unticked; `revise <slug>`
#     re-projects it with the same script), writes/extends run.md, seeds the run's canonical file
#     pack (run-pack.sh --init: project/plan/tasks/decisions/status/handoff/FAILURE.md), projects
#     the labels (project-labels.sh), and — if --stub was passed — git mv's the stub into _done/.
#   • Lane (--lane bug|tweak|chore|hotfix|handover — the vocabulary is lib/project.sh's
#     `pipeline_lanes`) — the fast-lane scaffold (.icm/lanes/*/CONTEXT.md). No spec required:
#     opens a PR whose body carries Summary (with a `- slug:` line, so resolve-run.sh finds lane
#     PRs by body like spine ones — its branch-name fallback covers PRs without one) and Steps to
#     test — and NO gate checkboxes: a lane PR is merged by a human from the GitHub UI, so the
#     merge button is its gate. Labels it type:<lane> and writes run.md with a `lane:` line.
#     bug/tweak/chore/handover open DRAFT like the spine (blind-until-ready, deployment-economics
#     stub 9): draft pushes run the cheap CI tier and build no previews; the lane flips ready when
#     its fix is settled, which starts the full gate and the affected product-app previews.
#     `hotfix` opens READY — an incident wants one full gate and the previews at once, and that
#     first ready push's cost is accepted (agency brief §4.5). `--ready` forces it for any lane.
#
# The spine PR body mirrors .github/pull_request_template.md — the same sections in the same
# order (Summary, the Spec table, Acceptance criteria, Steps to test, the Gates block), and the
# gate anchors kept byte-identical because the pipeline parses them (see .icm/_shared/github.md).
# The lane body carries neither anchor by design; the "missing gate:ready-to-merge anchor is
# malformed" rule applies to spine PRs only.
#
# Before anything is created it reads this run's `- touches:` against every live run's spec and
# prints `[WARN] overlaps <slug> on <path>` per shared surface (decision D26) — a warning for the
# operator, never a refusal; the cut is where overlap is avoided, and Build merges main early.
#
# THE BASE BRANCH is the pipeline's, not the caller's: `main`, or the UAT branch where the repo
# declares a persistent client UAT environment (`.icm/project.json` → uat.branch; lib/project.sh
# → pipeline_base_branch; .icm/uat/CONTEXT.md). A hotfix targets `main` regardless — production
# is wrong now. `--base` overrides either. When the base is the UAT branch this script also brings
# origin/main into the run branch before anything is committed (the intake cut and any hotfix
# land on main first), and warns when the branch was not cut from the UAT branch.
#
# --dry-run prints the PR body this call would open (the spine body straight from
# project-body.sh, or the lane body) and creates NOTHING: no branch, no commit, no push, no PR,
# no run.md, no labels, no stub move. It needs no GitHub credential. Use it to check the layout.
#
# THIS SCRIPT IS THE ONLY WAY A PIPELINE PR IS OPENED AND A RUN BRANCH IS NAMED. No other script,
# stage contract, lane, or hand-typed MCP call may create a branch or open a PR for a run
# (.icm/_shared/github.md → PR regime 2). Branch naming: when HEAD is main/master or detached the
# script creates and checks out `claude/<slug>` itself (plain local use); on any other branch it
# uses the CURRENT branch as the run branch — a harness-named branch (a Claude Code cloud session,
# OpenCode, an Actions checkout) is accepted as-is and recorded in run.md's `- branch:` line, which
# is what resolve-run.sh checks out later. The branch is pushed and the PR opened from it here.
#
# Config from the process environment (no .env loading) — the GitHub calls go through
# .icm/scripts/lib/gh.sh, which falls back to a logged-in `gh` CLI when the token route fails and
# dies naming what this environment is missing when neither works:
#   GITHUB_TOKEN / GH_TOKEN  (one, or a gh login)  GitHub token: contents, pull-requests, issues.
#   GITHUB_REPO              (optional)            owner/repo. Default: derived from `origin` (lib/gh.sh).
#   GITHUB_API_URL           (optional)            API base. Default: https://api.github.com.
#
# Usage:
#   .icm/scripts/new-run.sh <slug> --summary "<one plain sentence>" \
#       [--stub .icm/intake/<scope>/<feature>.md] [--steps "<steps to test>"] [--base <branch>] \
#       [--lane bug|tweak|chore|hotfix|handover] [--ready] [--title "<PR title — lane mode>"] [--dry-run]
#
#   With --lane, --stub may name a TRIAGE stub only (.icm/intake/triage/<name>.md — the parked
#   off-ticket finding the lane is picking up); scope-epic stubs still go through Define.
#
# Verdict (stdout, last line):
#   RESULT: CREATED   exit 0  — run committed, PR opened + labelled, run.md written/extended,
#                              stub consumed (if given). The PR URL is echoed above the verdict.
#   (--dry-run: stdout is the body and nothing else, so it can be piped; `RESULT: DRY-RUN` goes to stderr.)
set -euo pipefail

command -v curl >/dev/null || { echo "curl not found" >&2; exit 1; }
command -v jq   >/dev/null || { echo "jq not found"   >&2; exit 1; }
command -v git  >/dev/null || { echo "git not found"  >&2; exit 1; }

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

die() { echo "error: $*" >&2; exit 1; }

# --- args ------------------------------------------------------------------------------------------

slug=""; summary=""; stub=""; steps=""; base=""; lane=""; title_flag=""; dry_run=0; ready_flag=0
while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run) dry_run=1; shift ;;
    --ready)   ready_flag=1; shift ;;
    --summary) summary="${2:-}"; shift 2 ;;
    --stub)    stub="${2:-}"; shift 2 ;;
    --steps)   steps="${2:-}"; shift 2 ;;
    --base)    base="${2:-}"; shift 2 ;;
    --lane)    lane="${2:-}"; shift 2 ;;
    --title)   title_flag="${2:-}"; shift 2 ;;
    --*)       die "unknown flag: $1" ;;
    *)         [ -z "$slug" ] && slug="$1" || die "unexpected argument: $1"; shift ;;
  esac
done
# shellcheck source=lib/project.sh
source "$here/lib/project.sh"

[ -n "$slug" ]    || die "usage: new-run.sh <slug> --summary \"<one sentence>\" [--stub <path>] [--lane $(pipeline_lanes | tr ' ' '|')] [--ready] [--dry-run]"
[ -n "$summary" ] || die "--summary \"<one plain sentence>\" is required (the PR Summary — the one AI-authored line)"
if [ -n "$lane" ] && ! is_lane "$lane"; then die "--lane must be one of: $(pipeline_lanes | tr ' ' '|'), got: $lane"; fi
# A hotfix opens ready — the whole point of the lane is one full gate now (lib/project.sh → lanes).
[ "$lane" = "hotfix" ] && ready_flag=1
# The base branch: --base wins; else the pipeline's (main, or the UAT branch where one is
# declared); a hotfix goes to main regardless — production is wrong now (lanes/hotfix/CONTEXT.md).
if [ -z "$base" ]; then
  base="$(pipeline_base_branch)"
  [ "$lane" = "hotfix" ] && base="main"
fi
# A lane may consume a triage stub (the parking lane it exists to drain) — but never a scope-epic
# stub, which must go through Define so the spec and the Spec-approved gate exist.
if [ -n "$lane" ] && [ -n "$stub" ]; then
  case "$stub" in
    *.icm/intake/triage/*|.icm/intake/triage/*) : ;;
    *) die "--lane consumes only triage stubs (.icm/intake/triage/*) — scope-epic stubs go through /pipeline new" ;;
  esac
fi

run_dir="$repo_root/.icm/runs/$slug"
run_md="$run_dir/run.md"

spec=""
if [ -z "$lane" ]; then
  spec="$run_dir/02_define/output/spec.md"
  [ -f "$spec" ] || die "no spec at .icm/runs/$slug/02_define/output/spec.md — Define must write spec.md first"
fi

# Guard the "exactly one PR per run" rule: never open a second PR for a run that already has one.
# (A run.md written by Scope — story:/author:/personas: lines, no `- pr:` — is fine: we extend it.)
if [ -f "$run_md" ] && grep -Eq '^- pr:[[:space:]]*#?[0-9]+' "$run_md"; then
  die "run.md already records a PR for '$slug' — use 'revise $slug' to change the spec, not new-run.sh"
fi

# --- config from env (lib/gh.sh: GH_API, repo, gh_token + the curl→gh fallback) --------------------

# shellcheck source=lib/gh.sh
source "$here/lib/gh.sh"
# Preflight before any commit or push: a scaffold that dies here is cleanly re-runnable. A dry run
# touches nothing on GitHub, so it needs no credential.
[ "$dry_run" -eq 1 ] || gh_require "opening the PR"

git_c() { git -C "$repo_root" "$@"; }

# Push with bounded exponential backoff — network blips shouldn't fail the scaffold.
git_push() {
  local delay=2 attempt
  for attempt in 1 2 3 4; do
    if git_c push -u origin "$1"; then return 0; fi
    [ "$attempt" -lt 4 ] || break
    echo "  push failed (attempt $attempt) — retrying in ${delay}s" >&2
    sleep "$delay"; delay=$((delay * 2))
  done
  die "git push of '$1' failed after retries"
}

# --- branch ----------------------------------------------------------------------------------------
# Use the current branch; only fall back to creating one if we're on main/master or detached. A
# harness-named branch (cloud session, OpenCode, Actions) is accepted as the run branch and
# recorded in run.md below; the `claude/<slug>` fallback is for plain local use. This is the one
# place in the pipeline that names or creates a run branch (see the header).

branch="$(git_c rev-parse --abbrev-ref HEAD)"
if [ "$branch" = "main" ] || [ "$branch" = "master" ] || [ "$branch" = "HEAD" ] || [ "$branch" = "$base" ]; then
  branch="claude/$slug"
  if [ "$dry_run" -eq 1 ]; then
    echo "on $(git_c rev-parse --abbrev-ref HEAD) — a real run would create run branch $branch from it, targeting $base (dry run: not created)" >&2
  else
    echo "on $(git_c rev-parse --abbrev-ref HEAD) — creating run branch $branch from it, targeting $base" >&2
    git_c checkout -b "$branch"
  fi
else
  echo "on $branch — using it as the run branch (harness-named branches are accepted and recorded in run.md)" >&2
fi

# --- UAT repos: the run branch carries main (.icm/uat/CONTEXT.md) ----------------------------------------
# Where the PR targets the UAT branch, the intake cut (Scope pushes to main) and any hotfix (its
# lane merges into main) are on main and not yet on the UAT branch. Bring origin/main into this
# run branch before anything is committed, so the stub the run consumes is here and the run's PR
# carries main's newer commits into UAT. A conflict is the operator's — aborted and named, never
# resolved by guesswork. Skipped on a dry run and when the base is main (nothing to bring in).
if [ "$dry_run" -eq 0 ] && uat_declared && [ "$base" = "$(uat_branch)" ]; then
  if GIT_TERMINAL_PROMPT=0 git_c fetch origin --quiet >/dev/null 2>&1; then
    if git_c rev-parse --verify -q "origin/$base" >/dev/null 2>&1 && ! git_c merge-base --is-ancestor "origin/$base" HEAD 2>/dev/null; then
      echo "[WARN] $branch does not contain origin/$base's tip — this run is not built on the current UAT batch; cut run branches from origin/$base (.icm/uat/CONTEXT.md)" >&2
    fi
    if git_c rev-parse --verify -q origin/main >/dev/null 2>&1 && ! git_c merge-base --is-ancestor origin/main HEAD 2>/dev/null; then
      if git_c merge --no-edit origin/main >/dev/null 2>&1; then
        echo "brought origin/main into $branch — the UAT branch was behind main (an intake cut or a hotfix travels with this run)" >&2
      elif [ "$(git_c diff --name-only --diff-filter=U 2>/dev/null)" = ".icm/uat/batch.json" ] \
           && git_c checkout --ours -- .icm/uat/batch.json >/dev/null 2>&1 && git_c add .icm/uat/batch.json && git_c commit -q --no-edit >/dev/null 2>&1; then
        # The one file main and the UAT branch both write: main's copy is a promotion's snapshot,
        # the UAT branch's is the live batch — keep the UAT branch's (promote-uat.sh does the same).
        echo "brought origin/main into $branch — .icm/uat/batch.json kept from the UAT branch (main's copy is a promotion's snapshot)" >&2
      else
        git_c merge --abort >/dev/null 2>&1 || true
        die "origin/main does not merge cleanly into $branch — bring main into the UAT branch first (.icm/scripts/promote-uat.sh sync; a conflict there is the operator's to resolve), then re-run"
      fi
    fi
  else
    echo "[WARN] git fetch origin failed — could not check whether main has moved past the UAT branch" >&2
  fi
fi

# --- PR title + body -------------------------------------------------------------------------------

if [ -z "$lane" ]; then
  title="$(grep -m1 '^# ' "$spec" | sed -E 's/^#[[:space:]]+//; s/^Spec:[[:space:]]*//; s/[[:space:]]*$//')"
  [ -n "$title" ] || title="$slug"

  # The body is projected by project-body.sh — the one implementation shared with `revise <slug>`
  # (which re-projects it with --apply). It mirrors the template headings + both gate anchors and
  # the whole Acceptance criteria section unticked, and links (never embeds) spec.md on this branch.
  body_args=("$slug" --summary "$summary" --branch "$branch")
  [ -n "$steps" ] && body_args+=(--steps "$steps")
  body="$("$here/project-body.sh" "${body_args[@]}")" || die "project-body.sh failed — see above"
  draft=true
else
  title="${title_flag:-$slug}"
  [ -n "$steps" ] || steps=$'1. Open the preview URLs the lane reported (they build on the post-flip push; the lane hands over on a full-gate GREEN)\n2. Confirm the change described above, then squash-merge from GitHub — the merge button is the gate'

  # No Pipeline checklist and no gate anchor: nobody reads a checkbox on a lane PR — the human
  # merges from the GitHub UI once the smoke passes (.icm/_shared/github.md → fast-lane PRs).
  body="$(cat <<EOF
<!-- PIPELINE RUN (lane: ${lane}) — do not delete the markers; the pipeline reads them. -->

## Summary

${summary}

- slug: ${slug}

## Steps to test

${steps}
EOF
)"
  # Draft like the spine — the lane itself flips ready once its fix is settled (stub 9) —
  # unless the lane is a hotfix or --ready was passed: then the PR opens ready.
  draft=true
  [ "$ready_flag" -eq 0 ] || draft=false
fi

# --- overlap with a live run (D26): warn, never refuse ----------------------------------------------------
# Runs are cut for disjoint surfaces. Read this run's `- touches:` (the spec's header on the spine,
# the stub's Notes-for-Define guess in a lane) and every LIVE run's spec (`.icm/runs/*/02_define/
# output/spec.md`, the archive excluded — the same set resolve-run.sh adopts from), and print one
# [WARN] per shared path. A warning is information for the operator who cuts and merges; the
# scaffold proceeds regardless, and --dry-run shows it too.

touches_of() { # <file> → one path per line from its `- touches:` line
  [ -f "$1" ] || return 0
  grep -m1 -E '^-[[:space:]]*touches:' "$1" | sed -E 's/^-[[:space:]]*touches:[[:space:]]*//' \
    | tr ',' '\n' | sed -E 's/^[[:space:]]+|[[:space:]]+$//g; s/`//g' | grep -v '^$' || true
}
my_touches=""
if [ -n "$spec" ]; then my_touches="$(touches_of "$spec")"
elif [ -n "$stub" ]; then my_touches="$(touches_of "$stub"; [ -f "$stub" ] && grep -oE 'touches:[^\n]*' "$stub" | head -1 | sed -E 's/^touches:[[:space:]]*//' | tr ',' '\n' | sed -E 's/^[[:space:]]+|[[:space:]]+$//g; s/`//g' | grep -v '^$' || true)"; fi
if [ -n "$my_touches" ]; then
  for other_spec in "$repo_root"/.icm/runs/*/02_define/output/spec.md; do
    [ -f "$other_spec" ] || continue
    other_slug="$(basename "$(dirname "$(dirname "$(dirname "$other_spec")")")")"
    [ "$other_slug" = "$slug" ] && continue
    while IFS= read -r mine; do
      [ -n "$mine" ] || continue
      while IFS= read -r theirs; do
        [ -n "$theirs" ] || continue
        # A shared path, or one that contains the other (apps/web vs apps/web/app/x).
        case "$mine" in "$theirs"|"$theirs"/*) hit=1 ;; *) case "$theirs" in "$mine"/*) hit=1 ;; *) hit=0 ;; esac ;; esac
        [ "$hit" -eq 1 ] && echo "[WARN] overlaps $other_slug on $mine — two live runs on one surface; sequence them, or merge $other_slug first (D26)" >&2
      done <<< "$(touches_of "$other_spec")"
    done <<< "$my_touches"
  done
fi

# --- --dry-run: print the body, create nothing ------------------------------------------------------

if [ "$dry_run" -eq 1 ]; then
  label_note="type:feature"; [ -z "$lane" ] || label_note="type:$lane"
  echo "dry run — printing the ${lane:+$lane-lane }PR body for '$slug' (branch $branch, base $base, $([ "$draft" = true ] && echo draft || echo READY), label $label_note); nothing created" >&2
  printf '%s\n' "$body"
  # The verdict goes to stderr so stdout stays the body alone (pipeable, as the header promises).
  echo "RESULT: DRY-RUN" >&2
  exit 0
fi

# --- commit the run (+ consume the stub) + push ----------------------------------------------------
# The stub is retired BEFORE the PR opens: if anything here fails, no PR exists yet and the run is
# cleanly re-runnable — an orphaned PR with a still-active stub was the old failure mode.

if [ -z "$lane" ]; then
  commit_msg="feat: $slug — define spec"
else
  commit_msg="chore: $slug — open $lane lane"
fi
git_c add ".icm/runs/$slug/"
if git_c diff --cached --quiet; then
  echo "run files already committed" >&2
else
  git_c commit -m "$commit_msg" >/dev/null
fi

if [ -n "$stub" ]; then
  stub_path="$stub"
  [ -f "$stub_path" ] || stub_path="$repo_root/$stub"
  [ -f "$stub_path" ] || die "--stub given but no file at: $stub"
  stub_dir="$(dirname "$stub_path")"
  done_dir="$stub_dir/_done"
  mkdir -p "$done_dir"
  feature_slug="$(basename "$stub_path" .md)"
  git_c mv "$stub_path" "$done_dir/$(basename "$stub_path")"
  git_c commit -m "chore: mark $feature_slug stub spun out" >/dev/null
  echo "marked stub consumed: $stub → $done_dir/" >&2
fi

git_push "$branch"

# --- open the PR -----------------------------------------------------------------------------------

payload="$(jq -n --arg title "$title" --arg head "$branch" --arg base "$base" --arg body "$body" \
  --argjson draft "$draft" '{title: $title, head: $head, base: $base, draft: $draft, body: $body}')"

# lib/gh.sh: curl with the token, else the gh CLI, else one die naming the missing credential.
resp="$(gh_api POST "/repos/${repo}/pulls" "$payload")" || exit 1

http="$(printf '%s' "$resp" | tail -n1)"
pr_body="$(printf '%s' "$resp" | sed '$d')"
if [ "$http" != "201" ]; then
  reason="$(printf '%s' "$pr_body" | jq -r '.errors[0].message // .message // empty' 2>/dev/null || true)"
  die "PR create returned HTTP $http — ${reason:-no message}"
fi
pr_number="$(printf '%s' "$pr_body" | jq -r '.number')"
pr_url="$(printf '%s' "$pr_body" | jq -r '.html_url')"
[ -n "$pr_number" ] && [ "$pr_number" != "null" ] || die "PR create returned no number"

# --- write / extend run.md (branch + pr pointers), commit, push ------------------------------------
# A front run already has a run.md (lane:/story:/author:/personas:/stubs: lines) — append,
# don't clobber.

mkdir -p "$run_dir"
if [ ! -f "$run_md" ]; then
  {
    echo "# Run: $slug"
    echo
    [ -n "$lane" ] && echo "- lane: $lane"
  } > "$run_md"
fi
# The stub this run was spun from — the pointer validate-decisions.sh and run-pack.sh follow to
# the epic's scope (`intake/<epic>/<slug>.md`, without the `.icm/` prefix; it has just moved to
# that epic's `_done/`, which both readers tolerate).
[ -z "$stub" ] || grep -Eq '^- stub:' "$run_md" || echo "- stub: ${stub#./}" | sed 's#^- stub: \.icm/#- stub: #' >> "$run_md"
grep -Eq '^- branch:' "$run_md" || echo "- branch: $branch" >> "$run_md"
grep -Eq '^- pr:'     "$run_md" || echo "- pr: #$pr_number" >> "$run_md"
# The canonical file pack (run-pack.sh header): seeded once, here, so every run has project.md,
# plan.md, tasks.md, decisions.md, status.md, handoff.md and FAILURE.md from birth. Never
# overwrites; a failure to seed is a warning, never a failed run.
"$here/run-pack.sh" "$slug" --init >/dev/null 2>&1 \
  || echo "WARNING: run-pack.sh could not seed the run's canonical files — run: .icm/scripts/run-pack.sh $slug --init" >&2
git_c add ".icm/runs/$slug/run.md"
for f in project.md plan.md tasks.md decisions.md status.md handoff.md FAILURE.md; do
  [ -f "$run_dir/$f" ] && git_c add ".icm/runs/$slug/$f"
done
git_c diff --cached --quiet || git_c commit -m "chore: $slug — run pointers (branch + PR) and the canonical file pack" >/dev/null
git_push "$branch"

# --- labels ----------------------------------------------------------------------------------------

if [ -z "$lane" ]; then
  # Spine: full projection from spec.md (single source of truth for the label set). A label
  # failure must not orphan the just-opened PR — validate-spec.sh has already vetted the header,
  # and the CI labels job re-projects on the next push, so degrade to a loud warning.
  # The token (if any) is inherited from the environment; the child sources lib/gh.sh itself.
  GITHUB_REPO="$repo" GITHUB_API_URL="$GH_API" \
    "$here/project-labels.sh" "$slug" --stage define >&2 \
    || echo "WARNING: labels could not be projected onto PR #$pr_number — fix and re-run project-labels.sh (the PR itself is fine; CI re-projects on the next push)" >&2
else
  # Lane: just type:<lane> — no spec to project from.
  lresp="$(gh_api PUT "/repos/${repo}/issues/${pr_number}/labels" \
    "$(jq -n --arg l "type:$lane" '{labels: [$l]}')")" || exit 1
  lhttp="$(printf '%s' "$lresp" | tail -n1)"
  [ "$lhttp" = "200" ] || die "label write returned HTTP $lhttp (does 'type:$lane' exist? see .github/labels.yml)"
fi

# --- verdict ---------------------------------------------------------------------------------------

echo "run '$slug' created — branch: $branch, ${lane:+$lane lane }PR: $pr_url ($([ "$draft" = true ] && echo draft || echo ready))"
echo "RESULT: CREATED"
