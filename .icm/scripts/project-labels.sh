#!/usr/bin/env bash
# project-labels.sh — project a run's labels onto its PR from spec.md (one direction: file → PR).
#
# Replaces the conversational "build the full label set and call issue_write" step. The label set is
# a pure function of the spec header + the stage, so a script can project it exactly — no "mostly".
# It reads the PR number from run.md and the personas/complexity from spec.md, assembles the FULL
# label set, and PUTs it (the GitHub labels API replaces the whole set, which is what we want — the
# fixed vocabulary lives in .github/labels.yml). The SESSION is the caller (decision D43 — no
# workflow projects labels any more): new-run.sh calls it once at Define, Build calls it with
# --stage auto after the first push that carries notes.md, Release with --stage release at its
# step 1 (_shared/github.md → Labels). Requires curl + jq.
#
# Config is read straight from the process environment — this script does NOT load any .env file.
# The label write goes through .icm/scripts/lib/gh.sh (curl with the token, else a logged-in `gh`
# CLI, else one die naming what this environment is missing):
#
#   GITHUB_TOKEN          (one*)      GitHub token (contents, pull-requests, issues) — the label write.
#   GH_TOKEN              (one*)      Alternative name for the token (*one of the two, or a gh login).
#   GITHUB_REPO           (optional)  owner/repo the PR lives in. Default: derived from `origin` (lib/gh.sh).
#   GITHUB_API_URL        (optional)  API base. Default: https://api.github.com.
#
# Usage:
#   .icm/scripts/project-labels.sh <slug> --stage <define|build|release|auto> [--pr <n>]
#
#   --stage auto   derive the stage from which run outputs exist on disk (`## Release` in
#                  notes.md → release; notes.md exists → build; else define), so an automated
#                  caller (the .github/workflows/pipeline.yaml labels job) doesn't have to know
#                  the stage.
#   --pr <n>       use this PR number instead of reading it from run.md — for CI, where the PR number
#                  comes from the event and run.md's pointer may not be the one being labelled.
#
# Verdict (stdout, last line):
#   RESULT: APPLIED   exit 0  — the full label set was written to the PR (the set is echoed above it).
set -euo pipefail

command -v curl >/dev/null || { echo "curl not found" >&2; exit 1; }
command -v jq   >/dev/null || { echo "jq not found"   >&2; exit 1; }

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

die() { echo "error: $*" >&2; exit 1; }

# --- args ------------------------------------------------------------------------------------------

slug=""; stage=""; pr_override=""
while [ $# -gt 0 ]; do
  case "$1" in
    --stage) stage="${2:-}"; shift 2 ;;
    --pr)    pr_override="${2:-}"; shift 2 ;;
    --*)     die "unknown flag: $1" ;;
    *)       [ -z "$slug" ] && slug="$1" || die "unexpected argument: $1"; shift ;;
  esac
done
[ -n "$slug" ]  || die "usage: project-labels.sh <slug> --stage <define|build|release|auto> [--pr <n>]"
[ -n "$stage" ] || die "--stage <define|build|release|auto> is required"

run_dir="$repo_root/.icm/runs/$slug"
spec="$run_dir/02_define/output/spec.md"

# A LANE run has no spec: its whole label set is `type:<lane>` (bug, tweak, chore, hotfix,
# handover — lib/project.sh → pipeline_lanes), written once by new-run.sh and re-projected here
# only when asked (CI's labels job skips lane runs). Read the lane from run.md, and never die on
# the missing spec for one.
lane_of_run=""
if [ -f "$run_dir/run.md" ]; then
  lane_of_run="$(grep -m1 '^- lane:' "$run_dir/run.md" | sed -E 's/^- lane:[[:space:]]*//; s/[[:space:]]+#.*$//; s/[[:space:]]*$//' || true)"
  [ "$lane_of_run" = "feature" ] || [ "$lane_of_run" = "front" ] && lane_of_run=""
fi
[ -f "$spec" ] || [ -n "$lane_of_run" ] || die "no spec at $spec — Define must write spec.md first (a lane run needs a '- lane:' line in run.md)"

# --stage auto: derive the current stage from which run outputs exist on disk. Newest wins.
# Release is marked by the `## Release` section Release appends to Build's notes.md (the stage
# writes no run-folder file of its own — its artifact is the repo's changelog page, where it has one).
if [ "$stage" = "auto" ]; then
  notes="$run_dir/03_build/output/notes.md"
  if [ -f "$notes" ] && grep -q '^## Release' "$notes"; then
    stage="release"
  elif [ -f "$notes" ]; then
    stage="build"
  else
    stage="define"
  fi
fi
case "$stage" in define|build|release) : ;; *) die "--stage must be define|build|release|auto, got: $stage" ;; esac

run_md="$run_dir/run.md"
if [ -z "$pr_override" ]; then
  [ -f "$run_md" ] || die "no run.md at $run_md — resolve the run first (resolve-run.sh), or pass --pr <n>"
fi

# --- config from env (lib/gh.sh: GH_API, repo, gh_token + the curl→gh fallback) --------------------

# shellcheck source=lib/gh.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/gh.sh"
# shellcheck source=lib/project.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/project.sh"
gh_require "writing PR labels"

# --- PR number: explicit --pr wins, else read it from run.md ---------------------------------------

if [ -n "$pr_override" ]; then
  pr_number="$(printf '%s' "$pr_override" | grep -oE '[0-9]+' | head -n1 || true)"
  [ -n "$pr_number" ] || die "--pr must be a number, got: '$pr_override'"
else
  pr_number="$(grep -m1 '^- pr:' "$run_md" \
    | sed -E 's/^- pr:[[:space:]]*//; s/[[:space:]]+#.*$//' \
    | grep -oE '[0-9]+' | head -n1 || true)"
  [ -n "$pr_number" ] || die "could not read a PR number from $run_md ('- pr:' line)"
fi

# --- lane run: type:<lane> and nothing else -----------------------------------------------------------

if [ -n "$lane_of_run" ]; then
  is_lane "$lane_of_run" || die "run.md names lane '$lane_of_run', which is not one of: $(pipeline_lanes)"
  payload="$(jq -n --arg l "type:$lane_of_run" '{labels: [$l]}')"
  echo "Projecting labels onto PR #$pr_number: type:$lane_of_run (lane run — no spec, no stage label)" >&2
  resp="$(gh_api PUT "/repos/${repo}/issues/${pr_number}/labels" "$payload")" || exit 1
  http="$(printf '%s' "$resp" | tail -n1)"
  [ "$http" = "200" ] || die "label write returned HTTP $http (does 'type:$lane_of_run' exist? see .github/labels.yml)"
  echo "RESULT: APPLIED"; exit 0
fi

# --- spec header → label set -----------------------------------------------------------------------

complexity="$(grep -m1 '^- complexity:' "$spec" | sed -E 's/^- complexity:[[:space:]]*//; s/[[:space:]]*$//' | tr '[:upper:]' '[:lower:]')"
case "$complexity" in trivial|standard|complex) : ;; *) die "spec complexity must be trivial|standard|complex, found: '$complexity'" ;; esac

personas_raw="$(grep -m1 '^- personas:' "$spec" | sed -E 's/^- personas:[[:space:]]*//; s/[[:space:]]*$//')"
[ -n "$personas_raw" ] || die "spec has no '- personas:' header to project persona labels from"

# Persona headers are free-form prose in practice — parentheticals, semicolons, role notes, even
# non-vocabulary words like "platform" or "Partner". So we don't tokenise the line; we scan it for
# each keyword of the repo's persona vocabulary (`personas` in .icm/project.json, mirrored in its
# labels file) as a whole word, case-insensitive, and
# emit those in canonical order. Anything outside the vocabulary is ignored, so the projection is
# deterministic regardless of wording. Any persona NAMED in this control-point header is projected.
labels=("type:feature" "stage:${stage}" "complexity:${complexity}")
found_persona=0
# The persona vocabulary is the repo's own: the `personas` array in .icm/project.json (matching
# its labels file). A repo that declares none projects no persona labels and is not wrong.
persona_vocab="$(project_list '.personas')"
for vocab in $persona_vocab; do
  if printf '%s' "$personas_raw" | grep -iqwE "$vocab"; then
    labels+=("persona:${vocab}")
    found_persona=1
  fi
done
if [ -n "$persona_vocab" ] && [ "$found_persona" -eq 0 ]; then
  die "no known persona in '- personas: $personas_raw' — valid (personas in .icm/project.json): $(printf '%s' "$persona_vocab" | paste -sd', ' -)"
fi

deduped=("${labels[@]}")  # type/stage/complexity are distinct and personas are emitted once each

# --- write the full set (PUT replaces every label on the PR) ---------------------------------------

payload="$(printf '%s\n' "${deduped[@]}" | jq -R . | jq -s '{labels: .}')"
echo "Projecting labels onto PR #$pr_number: ${deduped[*]}" >&2

resp="$(gh_api PUT "/repos/${repo}/issues/${pr_number}/labels" "$payload")" || exit 1

http="$(printf '%s' "$resp" | tail -n1)"
body="$(printf '%s' "$resp" | sed '$d')"
if [ "$http" != "200" ]; then
  reason="$(printf '%s' "$body" | jq -r '.message // empty' 2>/dev/null || true)"
  die "label write returned HTTP $http — ${reason:-no message} (do the labels exist in the repo? see .github/labels.yml)"
fi

echo "RESULT: APPLIED"
