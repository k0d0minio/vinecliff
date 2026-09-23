#!/usr/bin/env bash
# validate-decisions.sh — trace every `D-n` decision from the settled scope into the spec and the
# build notes, so nothing settled at Scope is silently assumed away downstream (TEMPLATE-OWNED).
#
# Scope's addendum ends in a `## Decisions` table whose ids are permanent (`_shared/scope-template.md`
# → "`D-n` ids are permanent"): `D-4` means `D-4` in the stub's Notes for Define, in `spec.md`,
# in `notes.md`. This script is the deterministic half of that rule. It reads only the `| D-n |`
# rows of that table — never the un-hyphenated `Dn` the estate uses for project-level decisions,
# never a `D-n` mentioned in prose — and checks each id appears in the two downstream outputs:
#
#   .icm/runs/<slug>/02_define/output/spec.md     Define carries every decision it builds on
#   .icm/runs/<slug>/03_build/output/notes.md     Build says which it honoured, and how
#
# Where the scope lives: a FRONT run has it at its own `01_scope/output/scope.md`. A SPINE run spun
# from a stub has none of its own — its scope is the front run of the epic that cut the stub
# (`run.md` → `- stub: intake/<epic>/<slug>.md` → `.icm/runs/<epic>/01_scope/output/scope.md`, live
# or archived). A run with neither — a lane run, a pre-front run, a request Define took directly —
# has nothing to trace and is SKIPPED, never failed. A downstream file that does not exist yet is
# reported as "not yet written" and is not a failure either: the check is meant to be run after
# Define and again after Build, and to be honest about which stage it is looking at.
#
# Usage:
#   .icm/scripts/validate-decisions.sh <slug>            # live run, else the archive
#   .icm/scripts/validate-decisions.sh <path-to-run-dir>
#
# Verdict (stdout, last line):
#   RESULT: OK          exit 0  — every id in the Decisions table appears in each downstream file that exists
#   RESULT: SKIP        exit 0  — no scope.md to trace from (lane run, legacy run, no front)
#   RESULT: MISSING <n> exit 2  — <n> ids absent from a downstream file that exists; the list is above it
set -euo pipefail

command -v jq >/dev/null || { echo "jq not found" >&2; exit 1; }

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$repo_root"

die() { echo "error: $*" >&2; exit 1; }

# shellcheck source=lib/project.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/project.sh"

[ $# -eq 1 ] || die "usage: validate-decisions.sh <slug | path-to-run-dir>"
arg="$1"

# --- resolve the run folder ---------------------------------------------------------------------------

if [ -d "$arg" ]; then
  run_dir="$(cd "$arg" && pwd)"
  slug="$(basename "$run_dir")"
else
  slug="$arg"
  if   [ -d ".icm/runs/$slug" ];             then run_dir="$repo_root/.icm/runs/$slug"
  elif [ -d "$runs_archive_rel/$slug" ];     then run_dir="$repo_root/$runs_archive_rel/$slug"
  else die "no run folder for '$slug' in .icm/runs/ or $runs_archive_rel/"
  fi
fi
run_rel="${run_dir#"$repo_root"/}"

# --- find the scope: the run's own front, else the front of the epic that cut its stub -------------------

scope=""
if [ -f "$run_dir/01_scope/output/scope.md" ]; then
  scope="$run_dir/01_scope/output/scope.md"
elif [ -f "$run_dir/run.md" ]; then
  # `- stub: intake/<epic>/<slug>.md` (with or without the `.icm/` prefix, with or without `_done/`).
  epic="$(grep -m1 -E '^- *stub:' "$run_dir/run.md" \
    | sed -E 's/^- *stub:[[:space:]]*//; s/[[:space:]]+#.*$//; s#^\.icm/##; s#^intake/##; s#/.*$##' || true)"
  if [ -n "$epic" ]; then
    for cand in ".icm/runs/$epic" "$runs_archive_rel/$epic"; do
      [ -f "$cand/01_scope/output/scope.md" ] && { scope="$repo_root/$cand/01_scope/output/scope.md"; break; }
    done
  fi
fi

if [ -z "$scope" ]; then
  echo "no scope.md for '$slug' — not a front run, and no front run behind its stub: nothing to trace"
  echo "RESULT: SKIP"; exit 0
fi
scope_rel="${scope#"$repo_root"/}"

# --- the ids: only the `| D-n |` rows of the `## Decisions` table -----------------------------------------

ids="$(awk '
  /^## /            { in_dec = ($0 ~ /^## Decisions/) }
  in_dec && /^\|/   { if (match($0, /^\|[[:space:]]*D-[0-9]+[[:space:]]*\|/)) {
                        s = substr($0, RSTART, RLENGTH); gsub(/[|[:space:]]/, "", s); print s } }
' "$scope" | sort -t- -k2,2n -u)"

if [ -z "$ids" ]; then
  echo "scope $scope_rel has a Decisions table with no D-n rows — nothing to trace"
  echo "RESULT: OK"; exit 0
fi
n_ids="$(printf '%s\n' "$ids" | wc -l | tr -d ' ')"
echo "scope: $scope_rel — $n_ids decision(s): $(printf '%s\n' "$ids" | paste -sd' ' -)"

# --- check each downstream file that exists ---------------------------------------------------------------

missing_total=0
check_file() { # check_file <label> <path>
  local label="$1" path="$2" rel missing=""
  rel="${path#"$repo_root"/}"
  if [ ! -f "$path" ]; then
    echo "$label: $rel not yet written — skipped"
    return 0
  fi
  while IFS= read -r id; do
    [ -n "$id" ] || continue
    # The id as a whole token: not `D-10` when looking for `D-1`, not `XD-1`.
    grep -qE "(^|[^A-Za-z0-9-])${id}([^0-9]|$)" "$path" || missing="${missing:+$missing }$id"
  done <<< "$ids"
  if [ -n "$missing" ]; then
    echo "$label: $rel is MISSING $missing"
    missing_total=$((missing_total + $(printf '%s\n' "$missing" | wc -w)))
  else
    echo "$label: $rel carries every decision"
  fi
}

check_file "define" "$run_dir/02_define/output/spec.md"
check_file "build"  "$run_dir/03_build/output/notes.md"

if [ "$missing_total" -gt 0 ]; then
  echo "a decision settled at Scope is absent downstream — carry it forward explicitly (or record in the file why it no longer applies, by id)" >&2
  echo "RESULT: MISSING $missing_total"; exit 2
fi
echo "every decision in $scope_rel is carried into the downstream outputs that exist for $run_rel"
echo "RESULT: OK"; exit 0
