#!/usr/bin/env bash
# run-pack.sh — the canonical file pack every live run carries, for session continuity (TEMPLATE-OWNED).
#
# A run is worked across sessions, machines and harnesses (`_shared/stage-preamble.md`), and what a
# resuming session most needs is not the spec — it is where the last one stopped. Seven plain-text
# files at the root of `.icm/runs/<slug>/` hold exactly that, each with one job:
#
#   project.md    the context card: pointers to the stub, scope and spec; touches; constraints
#   plan.md       the execution plan in passes — Build's layers, in order
#   tasks.md      the queue, with a definition of done (`- [ ]`) per item — human checkboxes
#   decisions.md  the `D-n` ids the run rests on, and any it made itself
#   status.md     phase · step · ci · blocked · updated — five lines, read first on a resume
#   handoff.md    next steps and blockers for the next session — rewritten at every stop
#   FAILURE.md    retrospectives and the learned rules they produced
#
# The templates are `_shared/run-pack/<file>.md` (template-owned, byte-identical everywhere); the
# only thing this script substitutes is the slug on the first line — no other placeholder is ever
# filled by a script (D12). Where a deterministic seed exists it is added below the template's body:
# `tasks.md` gets the spec's acceptance criteria as its definition of done, `decisions.md` gets the
# scope's `| D-n |` rows, `status.md` gets the phase the run's folders say it is in, `project.md`
# gets the pointers `run.md` and `spec.md` already carry. Everything else is the stage's to write.
#
# Verbs:
#   --check (default)  which of the seven are present; `MISSING n` when any is absent.
#   --init             seed the missing ones (never overwrites — a file that exists is the run's).
#                      `new-run.sh` calls this after it writes `run.md`, so every spine and lane
#                      run has the pack from birth; Scope calls it for a front.
#   --sync-rules       copy the `## Learned rules` bullets of `FAILURE.md` into
#                      `.icm/_shared/project-rules.md` → `## Learned rules` (created at the end of
#                      the file when absent), in the shape `retrospective.sh --apply` uses — a
#                      `<!-- Retrospective Learned Rule [date] -->` stamp, then the rule with
#                      `(\`FAILURE.md\` — <slug>)` as its provenance — skipping a rule whose text is
#                      already there. `close-out.sh` calls this before it archives the run, so the
#                      rules ride the same commit; it edits nothing else in that file. The two
#                      writers split one job: retrospective.sh learns from `error.log` (the errors
#                      a tool reported, judged at the fix), this from `FAILURE.md` (what the run
#                      as a whole learned — a wrong assumption, a STOP, a skipped step — which no
#                      tool ever logged).
#
# It never creates a run: `.icm/runs/<slug>/` must exist (live — an archived run is finished).
#
# Usage: .icm/scripts/run-pack.sh <slug> [--check|--init|--sync-rules] [--dry-run]
# Verdict (stdout, last line):
#   RESULT: OK            exit 0  — --check: all seven present
#   RESULT: MISSING <n>   exit 2  — --check: <n> absent (listed above)
#   RESULT: SEEDED <n>    exit 0  — --init: <n> file(s) created (0 when the pack was complete)
#   RESULT: SYNCED <n>    exit 0  — --sync-rules: <n> rule(s) added to project-rules.md (0 is fine)
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$repo_root"
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
die() { echo "error: $*" >&2; exit 1; }
command -v jq >/dev/null 2>&1 || die "jq not found"

# shellcheck source=lib/project.sh
source "$here/lib/project.sh"

slug=""; verb="check"; dry_run=0
while [ $# -gt 0 ]; do
  case "$1" in
    --check)      verb="check"; shift ;;
    --init)       verb="init"; shift ;;
    --sync-rules) verb="sync"; shift ;;
    --dry-run)    dry_run=1; shift ;;
    -h|--help)    sed -n '2,40p' "${BASH_SOURCE[0]}"; exit 0 ;;
    --*)          die "unknown flag: $1" ;;
    *)            [ -z "$slug" ] && slug="$1" || die "unexpected argument: $1"; shift ;;
  esac
done
[ -n "$slug" ] || die "usage: run-pack.sh <slug> [--check|--init|--sync-rules] [--dry-run]"
run_dir=".icm/runs/$slug"
[ -d "$run_dir" ] || die "no live run $run_dir/ — run-pack adopts a run, it never creates one"
tmpl_dir=".icm/_shared/run-pack"
[ -d "$tmpl_dir" ] || tmpl_dir="$here/../_shared/run-pack"      # running from the template itself
[ -d "$tmpl_dir" ] || die "no run-pack templates at .icm/_shared/run-pack/ — icm-sync.sh --apply, or setup.sh --fix"

pack=(project.md plan.md tasks.md decisions.md status.md handoff.md FAILURE.md)

# --- the scope this run rests on: its own, or the front of the epic behind its stub -----------------
scope_md() {
  [ -f "$run_dir/01_scope/output/scope.md" ] && { echo "$run_dir/01_scope/output/scope.md"; return; }
  local stub epic
  stub="$(grep -m1 -E '^- stub:' "$run_dir/run.md" 2>/dev/null | sed -E 's/^- stub:[[:space:]]*//; s/[[:space:]]+#.*$//; s/[[:space:]]*$//' || true)"
  [ -n "$stub" ] || return 0
  epic="$(printf '%s' "$stub" | sed -E 's:^\.icm/::; s:^intake/::; s:/.*$::')"
  [ -n "$epic" ] || return 0
  for d in ".icm/runs/$epic" "$runs_archive_rel/$epic"; do
    [ -f "$d/01_scope/output/scope.md" ] && { echo "$d/01_scope/output/scope.md"; return; }
  done
}
phase_of() {
  if   [ -d "$run_dir/lane" ];                          then echo lane
  elif [ -f "$run_dir/03_build/output/notes.md" ];      then echo build
  elif [ -f "$run_dir/02_define/output/spec.md" ];      then echo define
  elif [ -d "$run_dir/01_scope" ];                      then echo scope
  else echo define; fi
}
section_body() { # <file> <heading-regex> → the lines under that heading until the next `## `
  awk -v h="$2" 'f && /^## / { exit } f { print } $0 ~ "^## " h { f = 1 }' "$1"
}

case "$verb" in
  check)
    missing=0
    for f in "${pack[@]}"; do
      if [ -f "$run_dir/$f" ]; then echo "  present  $run_dir/$f"; else echo "  MISSING  $run_dir/$f"; missing=$((missing + 1)); fi
    done
    if [ "$missing" -gt 0 ]; then echo "seed with: .icm/scripts/run-pack.sh $slug --init"; echo "RESULT: MISSING $missing"; exit 2; fi
    echo "RESULT: OK"; exit 0 ;;

  init)
    seeded=0
    spec="$run_dir/02_define/output/spec.md"
    scope="$(scope_md || true)"
    # A placeholder line in a template is REPLACED by its seeded value(s) — never left beside them,
    # so `grep -m1 '^- phase:'` reads the truth and a reader sees one line per fact.
    replace_line() { # <file> <line-prefix-regex> <replacement text (may be several lines)>
      awk -v pre="$2" -v rep="$3" 'BEGIN { done = 0 } { if (!done && $0 ~ pre) { print rep; done = 1 } else print }' "$1" > "$1.tmp" && mv "$1.tmp" "$1"
    }
    for f in "${pack[@]}"; do
      dst="$run_dir/$f"
      if [ -f "$dst" ]; then echo "  kept     $dst"; continue; fi
      [ -f "$tmpl_dir/$f" ] || die "template missing: $tmpl_dir/$f"
      if [ "$dry_run" -eq 1 ]; then echo "  [dry-run] would seed $dst"; seeded=$((seeded + 1)); continue; fi
      sed "1s/<slug>/$slug/" "$tmpl_dir/$f" > "$dst"
      case "$f" in
        tasks.md)
          if [ -f "$spec" ]; then
            crit="$(section_body "$spec" 'Acceptance criteria' | grep -E '^- \[[ xX]\] ' | sed -E 's/^- \[[ xX]\] /- [ ] /' || true)"
            [ -z "$crit" ] || replace_line "$dst" '^- \[ \] <criterion' "$crit"
          fi ;;
        decisions.md)
          if [ -n "$scope" ]; then
            rows="$(section_body "$scope" 'Decisions' | awk -F'|' '$2 ~ /^[[:space:]]*D-[0-9]+[[:space:]]*$/ { id=$2; txt=$3; gsub(/^[[:space:]]+|[[:space:]]+$/, "", id); gsub(/^[[:space:]]+|[[:space:]]+$/, "", txt); print "- " id " — " txt }' || true)"
            [ -z "$rows" ] || replace_line "$dst" '^- <D-n — the decision' "$rows"
          fi ;;
        status.md)
          replace_line "$dst" '^- phase:'   "- phase: $(phase_of)"
          replace_line "$dst" '^- step:'    "- step: 1"
          replace_line "$dst" '^- ci:'      "- ci: none yet"
          replace_line "$dst" '^- blocked:' "- blocked: no"
          replace_line "$dst" '^- updated:' "- updated: $(date -u +%F)" ;;
        project.md)
          stub_line="$(grep -m1 -E '^- stub:' "$run_dir/run.md" 2>/dev/null | sed -E 's/^- stub:[[:space:]]*//; s/[[:space:]]+#.*$//' || true)"
          replace_line "$dst" '^- stub:'  "- stub: ${stub_line:-none}"
          replace_line "$dst" '^- scope:' "- scope: ${scope:-none}"
          if [ -f "$spec" ]; then
            replace_line "$dst" '^- spec:' "- spec: 02_define/output/spec.md"
            t="$(grep -m1 -E '^- touches:' "$spec" | sed -E 's/^- touches:[[:space:]]*//' || true)"
            [ -z "$t" ] || replace_line "$dst" '^- touches:' "- touches: $t"
            c="$(grep -m1 -E '^- complexity:' "$spec" | sed -E 's/^- complexity:[[:space:]]*//' || true)"
            if [ -n "$c" ]; then
              m="$("$here/select-model.sh" "$spec" --stage 03_build 2>/dev/null | sed -n 's/^RESULT: MODEL //p' || true)"
              replace_line "$dst" '^- complexity:' "- complexity: $c${m:+ → model: $m (executor — select-model.sh --stage 03_build)}"
            fi
          else
            replace_line "$dst" '^- spec:' "- spec: none yet (Define writes 02_define/output/spec.md)"
          fi ;;
      esac
      echo "  seeded   $dst"; seeded=$((seeded + 1))
    done
    echo "RESULT: SEEDED $seeded"; exit 0 ;;

  sync)
    failure="$run_dir/FAILURE.md"
    rules_md=".icm/_shared/project-rules.md"
    [ -f "$failure" ] || { echo "no $failure — nothing to sync"; echo "RESULT: SYNCED 0"; exit 0; }
    [ -f "$rules_md" ] || { echo "no $rules_md (project-owned; seeded by icm-check.sh --fix) — nothing to sync into"; echo "RESULT: SYNCED 0"; exit 0; }
    # Only real bullets: the template's own "<one sentence, …>" placeholder is not a rule.
    mapfile -t rules < <(section_body "$failure" 'Learned rules' | grep -E '^- ' | sed -E 's/^- //' | grep -vE '^<.*>$' | grep -v '^$' || true)
    if [ "${#rules[@]}" -eq 0 ]; then echo "FAILURE.md has no learned rules — nothing to sync"; echo "RESULT: SYNCED 0"; exit 0; fi
    stamp="$(date -u +%F)"; added=0
    if ! grep -q '^## Learned rules' "$rules_md"; then
      if [ "$dry_run" -eq 0 ]; then
        printf '\n## Learned rules\n\n*The constraints earlier runs paid for — appended by `retrospective.sh --apply` (from a run'"'"'s\n`error.log`) and by `run-pack.sh --sync-rules` (from its `FAILURE.md`) before the close-out. Edit or\ndelete lines freely — this file is the repo'"'"'s own, never synced.*\n\n' >> "$rules_md"
      fi
      echo "  (adding the ## Learned rules section to $rules_md)"
    fi
    # The same shape retrospective.sh appends in (its header documents it): a provenance stamp,
    # then the rule with its source in the trailing parenthesis — one section, two writers, one look.
    for r in "${rules[@]}"; do
      if grep -qF -- "- $r (" "$rules_md" || grep -qxF -- "- $r" "$rules_md"; then echo "  known    $r"; continue; fi
      if [ "$dry_run" -eq 1 ]; then echo "  [dry-run] would add: $r"; else
        # Append at the end of the file: the section is the file's last, by construction and by
        # retrospective.sh's own rule; `## Learned rules` elsewhere is honoured the same way it does.
        awk -v stamp="<!-- Retrospective Learned Rule [$stamp] -->" -v line="- $r (\`FAILURE.md\` — $slug)" '
          { buf[NR] = $0 }
          END {
            last = NR
            for (i = NR; i >= 1; i--) { if (buf[i] ~ /[^[:space:]]/) { last = i; break } }
            for (i = 1; i <= NR; i++) { print buf[i]; if (i == last) { print stamp; print line } }
            if (NR == 0) { print stamp; print line }
          }' "$rules_md" > "$rules_md.tmp" && mv "$rules_md.tmp" "$rules_md"
        echo "  added    $r"
      fi
      added=$((added + 1))
    done
    echo "RESULT: SYNCED $added"; exit 0 ;;
esac
