#!/usr/bin/env bash
# project-body.sh — project a run's PR body from spec.md (one direction: file → PR).
#
# The single implementation of the spine PR body. new-run.sh calls it once when Define opens the
# PR; `revise <slug>` calls it with --apply every time the spec changes, so the body never has a
# second, hand-typed shape. The body mirrors .github/pull_request_template.md — same sections in
# the same order, and the gate anchors kept byte-identical because the pipeline parses them (see
# .icm/_shared/github.md): Summary (the one AI-authored line), the Spec table (slug / personas /
# complexity / a LINK to spec.md — never an embedded copy), the whole Acceptance criteria section
# mirrored with every checkbox reset to [ ] under a one-line "n criteria" count, Steps to test,
# and the Gates block — a rule above and below, `### Gates`, one anchored checkbox per gate,
# both unticked. A projection always resets the gates: a revised spec re-opens the Spec-approved
# gate and the operator re-ticks it (stage 02, step 6). The slug lives in the Spec table's first row;
# resolve-run.sh matches that row (and the lane body's `- slug:` line) to find a run's PR.
#
# Two modes:
#   • Print (default) — write the projected body to stdout. new-run.sh feeds it to the PR-create
#     call. Needs --summary; the spec link points at --branch (default: the current branch).
#   • --apply — PATCH the run's existing PR body in place (the scripted `update_pull_request`).
#     Reads the PR number from run.md (or --pr), the branch from the PR itself, and — unless
#     --summary / --steps override them — keeps the Summary and Steps to test the current body
#     already carries, so a revision changes only what the spec changed. Reports on stderr when a
#     gate box was ticked on the body it replaced. Requires curl + jq.
#
# Config from the process environment (no .env loading) — the GitHub calls (--apply only) go
# through .icm/scripts/lib/gh.sh: curl with the token, else a logged-in `gh` CLI, else one die
# naming what this environment is missing:
#   GITHUB_TOKEN / GH_TOKEN  (one, or a gh login)  GitHub token: contents, pull-requests, issues.
#   GITHUB_REPO              (optional)            owner/repo. Default: derived from `origin` (lib/gh.sh).
#   GITHUB_API_URL           (optional)            API base. Default: https://api.github.com.
#
# Usage:
#   .icm/scripts/project-body.sh <slug> --summary "<one plain sentence>" [--branch <b>] [--steps "<steps>"]
#   .icm/scripts/project-body.sh <slug> --apply [--summary "…"] [--steps "…"] [--pr <n>]
#
# Verdict (stdout, last line — --apply only; print mode emits the body and nothing else):
#   RESULT: APPLIED   exit 0  — the PR body was replaced with the projection (URL echoed above).
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

die() { echo "error: $*" >&2; exit 1; }

# --- args ------------------------------------------------------------------------------------------

slug=""; summary=""; steps=""; branch=""; apply=0; pr_override=""
while [ $# -gt 0 ]; do
  case "$1" in
    --summary) summary="${2:-}"; shift 2 ;;
    --steps)   steps="${2:-}"; shift 2 ;;
    --branch)  branch="${2:-}"; shift 2 ;;
    --pr)      pr_override="${2:-}"; shift 2 ;;
    --apply)   apply=1; shift ;;
    --*)       die "unknown flag: $1" ;;
    *)         [ -z "$slug" ] && slug="$1" || die "unexpected argument: $1"; shift ;;
  esac
done
[ -n "$slug" ] || die "usage: project-body.sh <slug> --summary \"<one sentence>\" [--branch <b>] | <slug> --apply [--summary …] [--pr <n>]"

run_dir="$repo_root/.icm/runs/$slug"
run_md="$run_dir/run.md"
spec="$run_dir/02_define/output/spec.md"
[ -f "$spec" ] || die "no spec at .icm/runs/$slug/02_define/output/spec.md — Define must write spec.md first"

# lib/gh.sh sets GH_API, repo and gh_token (the spec link needs `repo` even in print mode).
# shellcheck source=lib/gh.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/gh.sh"

# --- section extraction (shared by the spec and the current PR body) -------------------------------
# Body of `## <heading>` up to the next heading of level 2 or deeper (`## `, `### `…) or the next
# horizontal rule (`---`, which opens the Gates block), leading/trailing blank lines dropped.
section() {
  awk -v h="$2" '
    $0 ~ "^##[[:space:]]+" h "[[:space:]]*$" { grab=1; next }
    grab && (/^##+[[:space:]]/ || /^---+[[:space:]]*$/) { grab=0 }
    grab { lines[++n] = $0 }
    END {
      s = 1; while (s <= n && lines[s] ~ /^[[:space:]]*$/) s++
      e = n; while (e >= s && lines[e] ~ /^[[:space:]]*$/) e--
      for (i = s; i <= e; i++) print lines[i]
    }
  ' "$1"
}

# --- --apply: read the current PR so the projection keeps what the spec does not own ----------------

if [ "$apply" -eq 1 ]; then
  command -v curl >/dev/null || { echo "curl not found" >&2; exit 1; }
  command -v jq   >/dev/null || { echo "jq not found"   >&2; exit 1; }
  gh_require "updating the PR body"

  if [ -n "$pr_override" ]; then
    pr_number="$(printf '%s' "$pr_override" | grep -oE '[0-9]+' | head -n1 || true)"
    [ -n "$pr_number" ] || die "--pr must be a number, got: '$pr_override'"
  else
    [ -f "$run_md" ] || die "no run.md at $run_md — resolve the run first (resolve-run.sh), or pass --pr <n>"
    pr_number="$(grep -m1 '^- pr:' "$run_md" \
      | sed -E 's/^- pr:[[:space:]]*//; s/[[:space:]]+#.*$//' \
      | grep -oE '[0-9]+' | head -n1 || true)"
    [ -n "$pr_number" ] || die "could not read a PR number from $run_md ('- pr:' line) — a run with no PR is opened by new-run.sh, not revised"
  fi

  resp="$(gh_api GET "/repos/${repo}/pulls/${pr_number}")" || exit 1
  http="$(printf '%s' "$resp" | tail -n1)"
  pr_json="$(printf '%s' "$resp" | sed '$d')"
  [ "$http" = "200" ] || die "PR read returned HTTP $http for #$pr_number — $(printf '%s' "$pr_json" | jq -r '.message // "no message"' 2>/dev/null)"
  [ "$(printf '%s' "$pr_json" | jq -r '.state')" = "open" ] || die "PR #$pr_number is not open — a merged or closed run is not revised"
  branch="$(printf '%s' "$pr_json" | jq -r '.head.ref')"
  pr_url="$(printf '%s' "$pr_json" | jq -r '.html_url')"

  current="$(mktemp)"; trap 'rm -f "$current"' EXIT
  printf '%s' "$pr_json" | jq -r '.body // ""' > "$current"
  grep -q '<!-- gate:ready-to-merge -->' "$current" \
    || die "PR #$pr_number body carries no gate:ready-to-merge anchor — not a pipeline PR body; fix it by hand first"

  [ -n "$summary" ] || summary="$(section "$current" "Summary")"
  [ -n "$steps" ]   || steps="$(section "$current" "Steps to test")"
  [ -n "$summary" ] || die "the current PR body has no ## Summary text and none was given — pass --summary"

  # The projection resets both gate boxes: say so when a tick is being cleared, so the revision
  # can tell the operator plainly that the gate is re-opened and needs their tick again.
  ticked="$(awk '
    /<!-- gate:spec-approved -->/  { g="Spec approved"; next }
    /<!-- gate:ready-to-merge -->/ { g="Ready to merge"; next }
    g != "" && /^[[:space:]]*-[[:space:]]+\[[xX]\]/ { print g; g="" ; next }
    g != "" && /^[[:space:]]*-[[:space:]]+\[ \]/   { g="" }
  ' "$current")"
fi

[ -n "$summary" ] || die "--summary \"<one plain sentence>\" is required (the PR Summary — the one AI-authored line)"
[ -n "$branch" ]  || branch="$(git -C "$repo_root" rev-parse --abbrev-ref HEAD)"

# --- spec → body -----------------------------------------------------------------------------------

personas="$(grep -m1 '^- personas:' "$spec" | sed -E 's/^- personas:[[:space:]]*//; s/[[:space:]]*$//')"
complexity="$(grep -m1 '^- complexity:' "$spec" | sed -E 's/^- complexity:[[:space:]]*//; s/[[:space:]]*$//')"

# Mirror the whole Acceptance criteria section body verbatim — criteria often wrap across indented
# continuation lines. Only a bullet's leading checkbox is reset to unticked (the PR tracks tick
# state; the text stays the spec's). validate-spec.sh has already guaranteed ≥1 checkbox.
criteria="$(section "$spec" "Acceptance criteria" | sed -E '/^[[:space:]]*-[[:space:]]+\[[ xX]\]/ s/\[[ xX]\]/[ ]/')"
[ -n "$criteria" ] || die "no acceptance-criteria checkboxes found in $spec — run validate-spec.sh"
criteria_n="$(printf '%s\n' "$criteria" | grep -cE '^[[:space:]]*-[[:space:]]+\[ \]' || true)"
if [ "$criteria_n" -eq 1 ]; then criteria_count="1 criterion"; else criteria_count="$criteria_n criteria"; fi

# The PR opens draft and blind — previews exist only from the ready flip (Build flips ready, then
# pushes; the previews land on that push).
[ -n "$steps" ] || steps=$'1. Wait for Build to flip the PR ready — the affected product-app previews build on the post-flip push\n2. Open those previews and exercise each acceptance criterion above'

spec_rel="${spec#"$repo_root/"}"
# Branch link so the spec is readable while the PR is open; Release repoints it to blob/main right
# after the squash-merge (the branch — and this link — dies with the merge).
spec_link="https://github.com/${repo}/blob/${branch}/${spec_rel}"

body="$(cat <<EOF
<!-- PIPELINE RUN — do not delete the markers; the pipeline reads them. -->

## Summary

${summary}

## Spec

| Field | Value |
| --- | --- |
| **Slug** | \`${slug}\` |
| **Personas** | ${personas} |
| **Complexity** | ${complexity} |
| **Full spec** | [spec.md — canonical, read it there](${spec_link}) |

## Acceptance criteria

<!-- text mirrored from spec.md — edit the spec, not these lines; the PR tracks tick state only -->

_${criteria_count}_

${criteria}

## Steps to test

${steps}

---

### Gates

<!-- gate:spec-approved -->

- [ ] **Spec approved** — _Define gate: a human ticks this before Build starts._

<!-- gate:ready-to-merge -->

- [ ] **Ready to merge** — _Release gate: a human ticks this to authorise the squash-merge; the tick attests your own preview smoke-test._

---
EOF
)"

if [ "$apply" -eq 0 ]; then
  printf '%s\n' "$body"
  exit 0
fi

# --- --apply: PATCH the PR body ----------------------------------------------------------------------

resp="$(gh_api PATCH "/repos/${repo}/pulls/${pr_number}" "$(jq -n --arg body "$body" '{body: $body}')")" || exit 1
http="$(printf '%s' "$resp" | tail -n1)"
[ "$http" = "200" ] || die "PR update returned HTTP $http — $(printf '%s' "$resp" | sed '$d' | jq -r '.message // "no message"' 2>/dev/null)"

if [ -n "$ticked" ]; then
  while IFS= read -r g; do
    echo "NOTE: '$g' was ticked on PR #$pr_number and is now unticked — the revision re-opens that gate; the operator must re-tick it." >&2
  done <<< "$ticked"
fi
echo "PR #$pr_number body re-projected from .icm/runs/$slug/02_define/output/spec.md — $pr_url"
echo "RESULT: APPLIED"
