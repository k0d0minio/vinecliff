#!/usr/bin/env bash
# close-out.sh — move the ticket to done: archive the run, and the epic if this stub finished it.
#
# RUN BY THE RELEASE STAGE (AND EVERY LANE), ON THE RUN'S OWN BRANCH, BEFORE THE MERGE. The archive
# move rides in the run's own PR, so the squash-merge is what publishes it. Nothing is pushed to
# `main` here and nothing runs after the merge — a project that verifies or announces after the
# merge does so in its own CI workflow (`_shared/project-rules.md` → Announcing).
#
# It used to work the other way — CI ran it after the merge and pushed a second commit straight to
# `main`. That push cannot succeed on a branch protected by required status checks: no direct push
# carries them, and GitHub refuses the Actions bot as a ruleset bypass actor. Every merged run was
# left in `.icm/runs/` with its archive commit stranded on a chore branch. Moving the archive into
# the PR removes the second commit, and with it the whole class of problem: no push to a protected
# branch, no bypass, no token, no fallback PR.
#
# The old objection to this shape was that "a run folder moved before the squash is a claim about a
# merge that hasn't happened". It isn't: the move reaches `main` only if the PR merges, and if the
# PR never merges the move never happened. That is the same standing as a changelog page, which
# also says "this shipped" and is also written on the branch before the merge.
#
# Where the archives are: `runs_archive` and `intake_archive` in `.icm/project.json` (lib/project.sh),
# defaulting to the estate's own `.icm/runs/_done/` and `.icm/intake/_done/`. A project that serves
# its archive from a docs tree points both keys there; nothing else changes.
#
# What it does, in order:
#   1. Refuses to run on `main` — this commits to the run's branch, and only there.
#   2. Establishes the run may be closed out:
#        - its PR is OPEN            → the normal path: this run is about to merge.
#        - its PR is already MERGED  → a Release that merged without its close-out — a fault the
#                                      project's verify job (if it has one) has already reported.
#                                      The move is still committed here; the ruleset means it
#                                      reaches main on its own PR.
#        - its PR is CLOSED unmerged → STOP. An abandoned run is not history.
#        - no `- pr:` line at all    → a FRONT (Scope, which opens no PR). Its epic stands in for a
#                                      merge: it archives once `.icm/intake/<slug>/` has moved to
#                                      the intake archive, and is refused while that epic is live.
#   3. Copies the run's learned rules (FAILURE.md → `## Learned rules`) into
#      .icm/_shared/project-rules.md through `run-pack.sh --sync-rules` (appends only, skips what
#      is already there), staged into the same commit — then
#      moves .icm/runs/<slug>/ -> <runs_archive>/<slug>/ — the whole folder, so `usage.md` (the
#      per-stage usage lines usage-snapshot.sh appended) travels with the run into the archive,
#      where run-economics.sh (icm-board) reads it. A hotfix or handover lane run archives the
#      same way as any lane (lib/project.sh → pipeline_lanes).
#   4. If the run came from an intake stub, and that epic now has no active stubs left AND every
#      one of its OTHER spun-out stubs is settled — its run's PR merged, or the stub itself retired
#      with a `> Dropped:` / `superseded-by:` line — moves .icm/intake/<epic>/ ->
#      <intake_archive>/<epic>/ — and with it the front run .icm/runs/<epic>/ that cut the epic, if
#      one is still here, in the same commit. This run is excluded from that sibling test because it
#      is the one merging now. `_done/` alone is not the signal: it means spun out, not shipped,
#      which is why each sibling's PR is checked. .icm/intake/triage/ is exempt: it is a permanent
#      backlog (intake/CONTEXT.md -> Triage), never an epic to archive.
#   5. Commits the move on the current branch.
#
# Where the repo declares a UAT environment (.icm/project.json → uat; .icm/uat/CONTEXT.md) and this
# run's PR targets the UAT branch, step 3 also appends the slug to .icm/uat/batch.json (`stubs`) in
# the same commit — the batch the client signs off as a whole, published onto the UAT branch by the
# same squash that publishes the archive move. A PR into main (a hotfix, a promotion) is not added.
# This script is the only writer of that list; promote-uat.sh reads and resets it.
#
# It is idempotent: a run already archived is reported and skipped, and the epic step still runs —
# so a re-run after a partial close-out (run moved, epic not) finishes the job rather than doubling
# it, and a re-run after a complete one changes nothing.
#
# Config is read straight from the process environment — this script does NOT load any .env file.
# The PR reads go through .icm/scripts/lib/gh.sh (curl with the token, else a logged-in `gh` CLI,
# else one die naming what this environment is missing):
#
#   GITHUB_TOKEN          (one*)      GitHub token (contents, pull-requests, issues) — reads this
#                                     run's PR state and each sibling's.
#   GH_TOKEN              (one*)      Alternative name for the token (*one of the two, or a gh login).
#   GITHUB_REPO           (optional)  owner/repo. Default: derived from `origin` (lib/gh.sh).
#   GITHUB_API_URL        (optional)  API base. Default: https://api.github.com.
#
# Usage:
#   .icm/scripts/close-out.sh <slug> [--dry-run]
#
# Verdict (stdout, last line):
#   RESULT: CLOSED    exit 0  — the run (and the epic, if finished) are archived in a commit on
#                               this branch. Push it; the merge publishes it.
#   RESULT: STOP      exit 3  — nothing was moved, and the reason is on stderr: the PR was closed
#                               unmerged, or a front's epic is still live.
set -euo pipefail

command -v curl >/dev/null || { echo "curl not found" >&2; exit 1; }
command -v jq   >/dev/null || { echo "jq not found"   >&2; exit 1; }
command -v git  >/dev/null || { echo "git not found"  >&2; exit 1; }

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$repo_root"

die()  { echo "error: $*" >&2; exit 1; }
stop() { echo "$*" >&2; echo "RESULT: STOP"; exit 3; }

# --- args ------------------------------------------------------------------------------------------

slug=""; dry_run=0
while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run) dry_run=1; shift ;;
    --*)       die "unknown flag: $1" ;;
    *)         [ -z "$slug" ] && slug="$1" || die "unexpected argument: $1"; shift ;;
  esac
done
[ -n "$slug" ] || die "usage: close-out.sh <slug> [--dry-run]"

# --- config from env (lib/gh.sh: GH_API, repo, gh_token + the curl→gh fallback) --------------------

# shellcheck source=lib/gh.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/gh.sh"
# shellcheck source=lib/project.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/project.sh"
gh_require "reading the PR's state"

gh_get() { gh_api GET "$1"; }

run_dir="$repo_root/.icm/runs/$slug"
runs_archive="$runs_archive_rel"       # repo-relative, from .icm/project.json (lib/project.sh)
intake_archive="$intake_archive_rel"

# The `- pr:` line carries anything from "#456" to a full URL with a trailing "# comment".
pr_from_run_md() {
  grep -m1 '^- pr:' "$1" 2>/dev/null \
    | sed -E 's/^- pr:[[:space:]]*//; s/[[:space:]]+#.*$//; s#^.*/pull/##; s/^#//; s/[^0-9].*$//'
}

# A front run (Scope only) never opens a PR of its own — the front pushes straight to
# main — so a run.md with no usable `- pr:` line is the whole test for one.
front_only() {
  [ -f "$1" ] || return 1
  [ -z "$(pr_from_run_md "$1")" ]
}

# A stub retired without a run: `> Dropped: <reason, date>` (the estate's convention) or
# `superseded-by:` (a triage batch folded it into another stub). Settled, not unshipped.
stub_retired() {
  grep -qE '^> *Dropped:|^- *superseded-by:' "$1" 2>/dev/null
}

# Echoes the PR's base branch name; empty when the PR could not be read.
pr_base() {
  local n="$1" resp http
  case "$n" in ''|*[!0-9]*) echo ""; return 0 ;; esac
  resp="$(gh_get "/repos/${repo}/pulls/${n}")" || { echo ""; return 0; }
  http="$(printf '%s' "$resp" | tail -n1)"
  [ "$http" = "200" ] || { echo ""; return 0; }
  printf '%s' "$resp" | sed '$d' | jq -r '.base.ref // ""'
}

# Echoes "merged" / "open" / "closed"; empty when the PR could not be read at all.
pr_status() {
  local n="$1" resp http body
  case "$n" in ''|*[!0-9]*) echo ""; return 0 ;; esac
  resp="$(gh_get "/repos/${repo}/pulls/${n}")" || { echo ""; return 0; }
  http="$(printf '%s' "$resp" | tail -n1)"
  body="$(printf '%s' "$resp" | sed '$d')"
  [ "$http" = "200" ] || { echo ""; return 0; }
  printf '%s' "$body" | jq -r 'if .merged then "merged" else .state end'
}

# --- 1. this commits to the run's branch, and only there ---------------------------------------------

branch="$(git symbolic-ref --quiet --short HEAD || echo '')"
if [ "$dry_run" = "0" ] && { [ "$branch" = "main" ] || [ -z "$branch" ]; }; then
  die "close-out commits to the run's own branch (currently: ${branch:-detached HEAD}). The archive rides in the run's PR — it is never pushed to main."
fi

# --- 2. the run must be closable ---------------------------------------------------------------------

# The run's record is read from wherever it is — live, or already archived by an earlier pass.
# An archived run is not the end of the job: its epic may still be waiting (step 4).
run_md=""
if [ -d "$run_dir" ]; then
  run_md="$run_dir/run.md"
elif [ -d "$runs_archive/$slug" ]; then
  run_md="$runs_archive/$slug/run.md"
  echo "run '$slug' is already archived — checking whether its epic still needs moving" >&2
else
  die "no .icm/runs/$slug/ and no $runs_archive/$slug/ — wrong slug?"
fi

pr_number="$(pr_from_run_md "$run_md" || true)"

front_close=0
if [ -z "$pr_number" ]; then
  # No PR to check, so this is a front. Its work left the front as an intake epic under the same
  # slug, and that epic's own archival is the record that every stub it cut has shipped — which
  # makes the archived epic the front's merge, and the only signal there is.
  if [ -d "$intake_archive/$slug" ]; then
    front_close=1
    echo "front-only run '$slug' — its epic is archived, so the front is history too" >&2
  elif [ -d ".icm/intake/$slug" ]; then
    stop "'$slug' is a front-only run and its epic .icm/intake/$slug/ is still live — the front stays until the epic is archived with it."
  else
    stop "run.md for '$slug' has no usable '- pr:' line and there is no '$slug' epic in .icm/intake/ or $intake_archive/ — nothing here says this run is finished."
  fi
else
  status="$(pr_status "$pr_number")"
  [ -n "$status" ] || die "could not read PR #$pr_number — close-out needs its state, and must not guess"
  case "$status" in
    open)
      echo "PR #$pr_number is open — archiving on '$branch' so the squash-merge publishes it" >&2 ;;
    merged)
      # A Release that merged without its close-out: a fault (fix the contract or the run, not a
      # sweep chore); the move itself still reaches main only on its own PR, because a protected
      # main refuses a direct push.
      echo "PR #$pr_number already merged — Release merged without its close-out (a fault: fix the contract or the run). Archiving late; this commit reaches main on its own PR" >&2 ;;
    closed)
      stop "PR #$pr_number for '$slug' was closed without merging. An abandoned run is not history — delete the folder deliberately or reopen the PR." ;;
    *)
      die "unexpected state '$status' for PR #$pr_number" ;;
  esac
fi

# --- 3. archive the run --------------------------------------------------------------------------------

moved_run=0
if [ -d ".icm/runs/$slug" ]; then
  [ -d "$runs_archive/$slug" ] && die "$runs_archive/$slug already exists — resolve by hand"
  # First, what the run learned: the `## Learned rules` of its FAILURE.md go into the repo's own
  # _shared/project-rules.md (run-pack.sh --sync-rules — idempotent, appends only, never removes),
  # in this same commit, so the next run starts with them. A run without a FAILURE.md syncs nothing.
  if [ -f ".icm/runs/$slug/FAILURE.md" ] && [ -x "$here/run-pack.sh" ]; then
    if [ "$dry_run" = "1" ]; then
      "$here/run-pack.sh" "$slug" --sync-rules --dry-run >&2 || true
    else
      "$here/run-pack.sh" "$slug" --sync-rules >&2 || echo "WARNING: run-pack.sh --sync-rules failed — the run's learned rules were not copied into _shared/project-rules.md" >&2
      git diff --quiet -- .icm/_shared/project-rules.md 2>/dev/null || git add .icm/_shared/project-rules.md
    fi
  fi
  mkdir -p "$runs_archive"
  if [ "$dry_run" = "1" ]; then
    echo "[dry-run] would move .icm/runs/$slug/ → $runs_archive/$slug/" >&2
  else
    git mv ".icm/runs/$slug" "$runs_archive/$slug" \
      || die "could not archive the run folder"
    echo "archived run: .icm/runs/$slug/ → $runs_archive/$slug/" >&2
  fi
  moved_run=1
else
  echo "run '$slug' already archived on this branch — skipping" >&2
fi

# --- 3b. the UAT batch: a run merging into the UAT branch joins the batch the client signs off --------------

moved_batch=0
if uat_declared && [ -n "$pr_number" ]; then
  ub="$(uat_branch)"; bf=".icm/uat/batch.json"
  base_ref="$(pr_base "$pr_number")"
  if [ "$base_ref" = "$ub" ]; then
    if [ ! -f "$bf" ]; then
      mkdir -p "$(dirname "$bf")"
      jq -n '{stubs: [], client_approved: false, approved_by: "", approved_on: "", approved_head: "", approved_note: "", promotions: []}' > "$bf"
      echo "created $bf (promote-uat.sh init would have) — it rides in this commit" >&2
    fi
    jq -e . "$bf" >/dev/null 2>&1 || die "$bf is not valid JSON — fix it before closing out"
    if jq -e --arg s "$slug" '(.stubs // []) | index($s)' "$bf" >/dev/null 2>&1; then
      echo "'$slug' is already in the UAT batch ($bf)" >&2
    else
      if [ "$dry_run" = "1" ]; then
        echo "[dry-run] would add '$slug' to $bf (stubs) — PR #$pr_number targets the UAT branch $ub" >&2
      else
        tmpf="$(mktemp)"
        jq --arg s "$slug" '.stubs = ((.stubs // []) + [$s])' "$bf" > "$tmpf" && mv "$tmpf" "$bf" || die "could not write $bf"
        git add "$bf" || die "could not stage $bf"
        echo "added '$slug' to the UAT batch ($bf) — PR #$pr_number targets $ub; the client signs the batch off as a whole (.icm/uat/CONTEXT.md)" >&2
      fi
      moved_batch=1
    fi
  else
    echo "PR #$pr_number targets '${base_ref:-?}', not the UAT branch '$ub' — not added to the batch (a hotfix or a promotion goes to main directly)" >&2
  fi
fi

# --- 4. archive the epic, if this stub finished it -------------------------------------------------------

epic=""
moved_epic=0
moved_front=0
epic_note="no intake epic behind this run"

if [ "$front_close" = "1" ]; then
  # The front IS the epic's other half — and the epic went first, which is why we are here.
  epic_note="'$slug' is the front for the already-archived '$slug' epic"
else
  for d in .icm/intake/*/; do
    [ -d "$d" ] || continue
    # triage/ is the permanent parking lane, not an epic — a lane run spun out of one of its stubs
    # must never cause the folder to be archived, however empty it gets. The intake archive itself
    # (when it lives inside intake/, as the default `_done/` does) is not an epic either.
    case "$(basename "$d")" in triage) continue ;; esac
    [ "${d%/}" = "$intake_archive" ] && continue
    [ -e "$d/_done/$slug.md" ] && { epic="$(basename "$d")"; break; }
  done
fi

if [ -n "$epic" ]; then
  active="$(find ".icm/intake/$epic" -maxdepth 1 -name '*.md' ! -name 'breakdown.md' | wc -l | tr -d ' ')"
  if [ "$active" != "0" ]; then
    epic_note="epic '$epic' has $active stub(s) still to spin out — left in place"
  else
    unmerged=""
    for stub in ".icm/intake/$epic/_done/"*.md; do
      [ -e "$stub" ] || continue
      sib="$(basename "$stub" .md)"
      # This run is the one merging now — it is why the epic can finish, so it is not a sibling
      # the epic waits on. (Its folder has just moved to the archive anyway.)
      [ "$sib" = "$slug" ] && continue
      sib_run_md=""
      [ -f ".icm/runs/$sib/run.md" ] && sib_run_md=".icm/runs/$sib/run.md"
      [ -z "$sib_run_md" ] && [ -f "$runs_archive/$sib/run.md" ] \
        && sib_run_md="$runs_archive/$sib/run.md"
      if [ -z "$sib_run_md" ]; then
        # No run ever spun out of it: settled only if the stub itself says it was retired.
        stub_retired "$stub" && continue
        unmerged="${unmerged:+$unmerged, }$sib (no run folder)"; continue
      fi
      sib_pr="$(pr_from_run_md "$sib_run_md" || true)"
      [ "$(pr_status "$sib_pr")" = "merged" ] || unmerged="${unmerged:+$unmerged, }$sib"
    done
    if [ -n "$unmerged" ]; then
      epic_note="epic '$epic' is fully spun out but not fully shipped — waiting on: $unmerged"
    else
      [ -d "$intake_archive/$epic" ] && die "$intake_archive/$epic already exists — resolve by hand"
      mkdir -p "$intake_archive"
      if [ "$dry_run" = "1" ]; then
        echo "[dry-run] would move .icm/intake/$epic/ → $intake_archive/$epic/" >&2
      else
        git mv ".icm/intake/$epic" "$intake_archive/$epic" \
          || die "could not archive the intake epic"
      fi
      moved_epic=1
      epic_note="epic '$epic' shipped in full — archived"

      # The front that cut this epic carries the same slug and never opened a PR of its own, so
      # nothing else will ever move it. It is finished history the moment the epic is: it rides
      # along in this commit. A run folder at that slug WITH a PR is a spine run, not a front —
      # left alone, for rule 2 to close out on its own Release.
      if [ -d ".icm/runs/$epic" ] && front_only ".icm/runs/$epic/run.md"; then
        [ -d "$runs_archive/$epic" ] && die "$runs_archive/$epic already exists — resolve by hand"
        mkdir -p "$runs_archive"
        if [ "$dry_run" = "1" ]; then
          echo "[dry-run] would move the front .icm/runs/$epic/ → $runs_archive/$epic/" >&2
        else
          git mv ".icm/runs/$epic" "$runs_archive/$epic" \
            || die "could not archive the front run behind the epic"
          echo "archived front run: .icm/runs/$epic/ → $runs_archive/$epic/" >&2
        fi
        moved_front=1
      fi
    fi
  fi
fi
echo "$epic_note" >&2

# --- 5. commit on this branch ----------------------------------------------------------------------------

if [ "$dry_run" = "1" ]; then
  echo "[dry-run] nothing committed"
  echo "RESULT: CLOSED"; exit 0
fi

if [ "$moved_run" = "0" ] && [ "$moved_epic" = "0" ] && [ "$moved_front" = "0" ] && [ "$moved_batch" = "0" ]; then
  echo "nothing left to archive for '$slug'"
  echo "RESULT: CLOSED"; exit 0
fi

msg="chore: close out $slug — archive the shipped run"
[ "$front_close" = "1" ] && msg="chore: close out $slug — archive the front behind the archived epic"
[ "$moved_run" = "0" ] && [ "$moved_epic" = "1" ] && msg="chore: close out $slug — archive the completed $epic epic"
[ "$moved_run" = "1" ] && [ "$moved_epic" = "1" ] && msg="$msg and the completed $epic epic"
[ "$moved_front" = "1" ] && msg="$msg (front included)"
[ "$moved_batch" = "1" ] && msg="$msg — into the UAT batch"

git commit -q -m "$msg" || die "nothing staged to commit — the git mv did not take"

echo "committed on '$branch': $msg"
echo "RESULT: CLOSED"; exit 0
