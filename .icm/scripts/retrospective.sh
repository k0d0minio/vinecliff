#!/usr/bin/env bash
# retrospective.sh — turn the errors a run fixed into rules the next run reads (TEMPLATE-OWNED).
#
# A run that went RED, fixed it and went GREEN has learned something the next run would otherwise
# pay for again. Only the stage that fixed it knows what the fix was, so it records the error where
# it fixes it — `error.log` in its own output folder (Build step 4; every lane's RED path): a dated
# `## ` header naming the source, the failing lines verbatim, a `- resolved:` line once the fix
# landed, and a `- rule:` line only when the fix is a constraint of THIS repo rather than a slip.
# That file is the whole input. Nothing here reads CI, a transcript, or anything the session did
# not write down; a clean run has no error.log and nothing to learn.
#
# What it does — at Release step 7 and at the end of every lane, BEFORE the close-out moves the run:
#   1. Reads the run's error.log — `03_build/output/error.log` (spine) or `lane/output/error.log`
#      (lane), live or already archived — and gives every entry a SIGNATURE: the error CLASS, not
#      the instance. Recognised, in this order: a TypeScript code (`TS2532`), a Rust code (`E0308`),
#      a Biome rule (`lint/style/noVar`), an ESLint rule id (`@typescript-eslint/no-unused-vars`),
#      a Node errno (`ECONNREFUSED`) or error code (`ERR_MODULE_NOT_FOUND`), an exception class
#      (`ModuleNotFoundError`, `PrismaClientKnownRequestError`), a module-resolution failure
#      (`cannot-find-module`), a Prettier `[warn]`, a short lint code (`F401`, `E501`); else the
#      entry's first line with paths and numbers stripped.
#   2. Reads the ARCHIVE's error.logs the same way (`runs_archive` in .icm/project.json — the
#      only other runs it looks at; a live sibling's folder is never read) and counts each
#      signature across this run and the archive. A `security-check.sh` entry's signature is
#      `security-check/<rule id>`, read from its header — its body is a redacted trace, not a class.
#   3. Promotes this run's entry to a CANDIDATE rule when it carries a `- rule:` line (the session
#      judged it at the moment of the fix), or when its signature was seen at least --min times
#      (default 2) and it carries a `- resolved:` line — the resolved text is then the rule. An
#      entry with neither line is listed as unresolved and never promoted. A signature already in
#      `_shared/project-rules.md` is already a rule and is skipped. One candidate per signature.
#   4. Reads the branch's diff (`--base`, default origin/main, to the working tree — empty once
#      the run has merged) for ONE thing: the areas it touched, written into the rule's provenance.
#
# It REPORTS by default. `--apply` appends each candidate to the project-owned
# `_shared/project-rules.md` under `## Learned rules` — inside that section wherever it sits, or a
# new section at the end of the file when absent — in the directive's shape:
#
#   <!-- Retrospective Learned Rule [YYYY-MM-DD] -->
#   - <the rule, 1–2 lines> (`<signature>`, seen <n>× — <run slugs>; <areas>)
#
# The comment is a provenance stamp, not a sync boundary: project-rules.md is project-owned and is
# never synced (D20). Nothing here judges — the rule is the session's own words; nothing here
# commits — the stage commits the appended lines with the run's record, so the operator reads them
# in the PR and the merge is what publishes them; a rule that reads as a slip is deleted from the
# file by hand, and that edit is the whole editorial control. No network. Nothing outside the repo
# is read or written. It never edits error.log and never touches a template-owned file.
#
# Usage:
#   .icm/scripts/retrospective.sh <slug | path-to-run-dir> [--apply] [--min <n>] [--base <ref>]
#
# Verdict (stdout, last line):
#   RESULT: SKIP            exit 0  — no error.log for this run: a clean run, nothing to learn
#   RESULT: NONE            exit 0  — entries read, nothing to promote (or every candidate is already a rule)
#   RESULT: CANDIDATES <n>  exit 0  — <n> rule(s) would be appended; read them, re-run with --apply
#   RESULT: APPENDED <n>    exit 0  — --apply appended <n> rule(s) to _shared/project-rules.md; commit them with the record
set -euo pipefail

command -v git >/dev/null || { echo "git not found" >&2; exit 1; }
command -v jq  >/dev/null || { echo "jq not found"  >&2; exit 1; }

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$repo_root"
die() { echo "error: $*" >&2; exit 1; }

# shellcheck source=lib/project.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/project.sh"
# shellcheck source=lib/changed-files.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/changed-files.sh"

# --- args -----------------------------------------------------------------------------------------------

arg=""; apply=0; min=2; base="origin/main"
while [ $# -gt 0 ]; do
  case "$1" in
    --apply)   apply=1; shift ;;
    --min)     min="${2:-}"; shift 2 ;;
    --base)    base="${2:-}"; shift 2 ;;
    -h|--help) sed -n '2,52p' "${BASH_SOURCE[0]}"; exit 0 ;;
    --*)       die "unknown flag: $1" ;;
    *)         [ -z "$arg" ] && arg="$1" || die "unexpected argument: $1"; shift ;;
  esac
done
[ -n "$arg" ] || die "usage: retrospective.sh <slug | path-to-run-dir> [--apply] [--min <n>] [--base <ref>]"
case "$min" in ''|*[!0-9]*|0) die "--min needs a whole number of 1 or more (got '${min}')" ;; esac

rules_file="$repo_root/.icm/_shared/project-rules.md"
[ -f "$rules_file" ] || die ".icm/_shared/project-rules.md is missing — setup.sh --fix seeds it; nothing to append a rule to"

# --- resolve the run folder and its error.log -------------------------------------------------------------

if [ -d "$arg" ]; then
  run_dir="$(cd "$arg" && pwd)"; slug="$(basename "$run_dir")"
else
  slug="$arg"
  if   [ -d ".icm/runs/$slug" ];         then run_dir="$repo_root/.icm/runs/$slug"
  elif [ -d "$runs_archive_rel/$slug" ]; then run_dir="$repo_root/$runs_archive_rel/$slug"
  else die "no run folder for '$slug' in .icm/runs/ or $runs_archive_rel/"
  fi
fi
run_rel="${run_dir#"$repo_root"/}"

log=""
for cand in "$run_dir/03_build/output/error.log" "$run_dir/lane/output/error.log"; do
  [ -f "$cand" ] && { log="$cand"; break; }
done
if [ -z "$log" ]; then
  echo "no error.log under $run_rel/03_build/output/ or $run_rel/lane/output/ — a clean run records nothing, and there is nothing to learn from"
  echo "RESULT: SKIP"; exit 0
fi
log_rel="${log#"$repo_root"/}"

# --- the parser: one error.log → one TSV line per entry ---------------------------------------------------
# Fields: slug · index · header · signature · resolved · rule. An entry starts at a `## ` line; the
# body is everything until the next one, minus the two trailers. A trailer continues on the next
# line when that line is indented (a two-line rule). Tabs in free text become spaces.

tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT

signature() { # stdin: the entry's body lines → stdout: one token, or `text:` + the normalised first line
  local body sig
  body="$(cat)"
  sig="$(printf '%s\n' "$body" | grep -oE 'TS[0-9]{4,5}' | head -1 || true)"
  [ -n "$sig" ] && { printf '%s' "$sig"; return; }
  sig="$(printf '%s\n' "$body" | grep -oE 'error\[E[0-9]{4}\]' | head -1 | sed -E 's/^error\[(E[0-9]+)\]$/\1/' || true)"
  [ -n "$sig" ] && { printf '%s' "$sig"; return; }
  sig="$(printf '%s\n' "$body" | grep -oE '(lint|assist)/[A-Za-z0-9]+/[A-Za-z0-9]+' | head -1 || true)"
  [ -n "$sig" ] && { printf '%s' "$sig"; return; }
  # ESLint's table: `  12:5  error  <message>  <rule-id>` — the last token of an error/warning row,
  # accepted only when it is shaped like a rule id (a slash or a hyphen in it).
  sig="$(printf '%s\n' "$body" | awk '/[[:space:]](error|warning)[[:space:]]/ {print $NF}' \
        | grep -E '^(@?[a-z0-9-]+/)?[a-z][a-z0-9-]*(/[a-z][a-z0-9-]*)*$' | grep -E '[-/]' | head -1 || true)"
  [ -n "$sig" ] && { printf '%s' "$sig"; return; }
  sig="$(printf '%s\n' "$body" | grep -oE '(^|[^A-Za-z0-9_])E[A-Z]{4,}([^A-Za-z0-9_]|$)' | head -1 | tr -cd 'A-Z' || true)"
  [ -n "$sig" ] && { printf '%s' "$sig"; return; }
  sig="$(printf '%s\n' "$body" | grep -oE 'ERR_[A-Z_]+' | head -1 || true)"
  [ -n "$sig" ] && { printf '%s' "$sig"; return; }
  sig="$(printf '%s\n' "$body" | grep -oE '[A-Z][A-Za-z]+(Error|Exception|Warning)([^A-Za-z]|$)' | head -1 | tr -cd 'A-Za-z' || true)"
  [ -n "$sig" ] && { printf '%s' "$sig"; return; }
  if printf '%s\n' "$body" | grep -qiE 'cannot find module|module not found|could not resolve'; then
    printf 'cannot-find-module'; return
  fi
  if printf '%s\n' "$body" | grep -qE '(^|[[:space:]])\[warn\][[:space:]]'; then
    printf 'prettier'; return
  fi
  sig="$(printf '%s\n' "$body" | grep -oE '(^|[^A-Za-z0-9])[A-Z]{1,4}[0-9]{3,4}([^A-Za-z0-9]|$)' | head -1 | tr -cd 'A-Z0-9' || true)"
  [ -n "$sig" ] && { printf '%s' "$sig"; return; }
  # Fallback: the first line of the body, as a class — paths, numbers and case removed.
  sig="$(printf '%s\n' "$body" | grep -m1 -E '[^[:space:]]' \
        | sed -E 's#[A-Za-z0-9_.~-]*/[A-Za-z0-9_./-]+(:[0-9]+)*##g; s/[0-9]+/N/g; s/[[:space:]]+/ /g; s/^[[:space:][:punct:]]+//; s/ $//' \
        | tr '[:upper:]' '[:lower:]' | cut -c1-72 || true)"
  printf 'text:%s' "${sig:-(empty)}"
}

parse_log() { # parse_log <file> <slug> → TSV on stdout
  local file="$1" who="$2" idx=0 header="" body="" resolved="" rule="" last="" line sig
  emit() {
    [ -n "$header" ] || return 0
    # security-check.sh names its rule ids in the header (`<ts> security-check.sh — <rule ids>`); its
    # body is a redacted trace whose first line is scope/head/branch, not a class. The class is the
    # first rule id, prefixed so a gate finding never collides with a compiler's or linter's.
    if [[ "$header" =~ security-check\.sh[^A-Za-z0-9]+([a-z0-9][A-Za-z0-9_./-]*) ]]; then
      sig="security-check/${BASH_REMATCH[1]}"
    else
      sig="$(printf '%s' "$body" | signature)"
    fi
    printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$who" "$idx" "$header" "$sig" "$resolved" "$rule" | tr -d '\r'
  }
  while IFS= read -r line || [ -n "$line" ]; do
    line="${line//$'\t'/ }"
    if [[ "$line" == "## "* ]]; then
      emit; idx=$((idx + 1)); header="${line#\#\# }"; body=""; resolved=""; rule=""; last=""
    elif [ -z "$header" ]; then
      continue                                   # anything above the first `## ` is not an entry
    elif [[ "$line" =~ ^-[[:space:]]*resolved:[[:space:]]*(.*)$ ]]; then
      resolved="${BASH_REMATCH[1]}"; last="resolved"
    elif [[ "$line" =~ ^-[[:space:]]*rule:[[:space:]]*(.*)$ ]]; then
      rule="${BASH_REMATCH[1]}"; last="rule"
    elif [ -n "$last" ] && [[ "$line" =~ ^[[:space:]]+([^[:space:]].*)$ ]]; then
      case "$last" in                            # an indented line continues the trailer above it
        resolved) resolved="$resolved ${BASH_REMATCH[1]}" ;;
        rule)     rule="$rule ${BASH_REMATCH[1]}" ;;
      esac
    else
      last=""; body+="$line"$'\n'
    fi
  done < "$file"
  emit
}

parse_log "$log" "$slug" > "$tmp/run.tsv"
n_entries="$(wc -l < "$tmp/run.tsv" | tr -d ' ')"

# The archive: every other run's error.log, for the counts and the provenance — never a live sibling.
: > "$tmp/archive.tsv"
n_archive=0
if [ -d "$runs_archive_rel" ]; then
  for d in "$runs_archive_rel"/*/; do
    [ -d "$d" ] || continue
    other="$(basename "$d")"
    [ "$other" = "$slug" ] && continue
    for f in "$d/03_build/output/error.log" "$d/lane/output/error.log"; do
      [ -f "$f" ] || continue
      parse_log "$f" "$other" >> "$tmp/archive.tsv"
      n_archive=$((n_archive + 1))
    done
  done
fi
cat "$tmp/run.tsv" "$tmp/archive.tsv" > "$tmp/all.tsv"

# --- the diff: the areas this run touched, for the provenance line --------------------------------------

areas=""; diff_note=""
if git rev-parse --verify --quiet "${base}^{commit}" >/dev/null 2>&1; then
  fork="$(git merge-base "$base" HEAD 2>/dev/null || true)"
  if [ -n "$fork" ]; then
    files="$(changed_files "$fork" | grep -v '^\.icm/' || true)"
    n_files="$(printf '%s' "$files" | grep -c . || true)"
    areas="$(printf '%s\n' "$files" | grep . | awk -F/ '
      NF >= 3 { print $1 "/" $2; next }
      NF == 2 { print $1; next }
      { print "root" }' | sort -u | head -4 | paste -sd',' - | sed 's/,/, /g' || true)"
    diff_note="$n_files file(s) changed since the fork point off $base${areas:+ — areas: $areas}"
    [ "$n_files" = "0" ] && diff_note="no branch diff against $base (a merged run has none) — areas omitted"
  else
    diff_note="no merge-base with $base — areas omitted"
  fi
else
  diff_note="base $base does not resolve (fetch first, or --base <ref>) — areas omitted"
fi

# --- decide, entry by entry ---------------------------------------------------------------------------------

echo "=== retrospective: $slug ($log_rel — $n_entries entries; archive: $n_archive error.log(s) read) ==="
echo "diff: $diff_note"
if [ "$n_entries" = "0" ]; then
  echo "no \`## \` entries in $log_rel — the shape is in stages/03_build/CONTEXT.md → Outputs"
  echo "RESULT: NONE"; exit 0
fi

today="$(date -u +%F)"
: > "$tmp/candidates.tsv"    # signature · rule-text · count · slugs
n_cand=0; n_known=0; n_unresolved=0; n_below=0; n_dup=0
promoted=" "

while IFS=$'\t' read -r who idx header sig resolved rule; do
  [ -n "$sig" ] || continue
  count="$(awk -F'\t' -v s="$sig" '$4 == s' "$tmp/all.tsv" | wc -l | tr -d ' ')"
  slugs="$( { echo "$slug"; awk -F'\t' -v s="$sig" '$4 == s {print $1}' "$tmp/archive.tsv" | sort -u; } | paste -sd',' - | sed 's/,/, /g')"
  disp="$sig"; kind=""
  case "$sig" in text:*) disp="${sig#text:}"; kind=" (from the first line — no code recognised)" ;; esac
  echo "  #$idx $header"
  printf '     signature: %s%s   seen %s× (%s)   %s\n' "$disp" "$kind" "$count" "$slugs" \
    "$( [ -n "$rule" ] && echo 'resolved · rule flagged' || { [ -n "$resolved" ] && echo 'resolved' || echo 'UNRESOLVED'; } )"
  if [ -z "$resolved" ] && [ -z "$rule" ]; then
    echo "     → no \`- resolved:\` line — the fix never landed, or the record was never finished; nothing to learn from yet"
    n_unresolved=$((n_unresolved + 1)); continue
  fi
  case "$promoted" in *" $sig "*)
    echo "     → same signature as an earlier entry of this run — one rule per signature"
    n_dup=$((n_dup + 1)); continue ;;
  esac
  if grep -qF -- "\`$disp\`" "$rules_file"; then
    echo "     → already a rule in _shared/project-rules.md — skipped"
    n_known=$((n_known + 1)); continue
  fi
  if [ -z "$rule" ] && [ "$count" -lt "$min" ]; then
    echo "     → seen fewer than --min $min times and not flagged with \`- rule:\` — not promoted"
    n_below=$((n_below + 1)); continue
  fi
  text="${rule:-$resolved}"
  echo "     → CANDIDATE: $text"
  printf '%s\t%s\t%s\t%s\n' "$disp" "$text" "$count" "$slugs" >> "$tmp/candidates.tsv"
  promoted="$promoted$sig "
  n_cand=$((n_cand + 1))
done < "$tmp/run.tsv"

echo "candidates: $n_cand (already rules: $n_known · unresolved: $n_unresolved · below --min $min: $n_below · repeated in this run: $n_dup)"

if [ "$n_cand" = "0" ]; then
  echo "RESULT: NONE"; exit 0
fi
if [ "$apply" = "0" ]; then
  echo "re-run with --apply to append them to .icm/_shared/project-rules.md → Learned rules (nothing is committed; the stage commits them with the record)"
  echo "RESULT: CANDIDATES $n_cand"; exit 0
fi

# --- --apply: append inside `## Learned rules`, creating the section at the end when absent ------------------

block="$tmp/block.md"
: > "$block"
while IFS=$'\t' read -r disp text count slugs; do
  {
    echo
    echo "<!-- Retrospective Learned Rule [$today] -->"
    echo "- $text (\`$disp\`, seen ${count}× — $slugs${areas:+; $areas})"
  } >> "$block"
done < "$tmp/candidates.tsv"

# A file that does not end in a newline would glue the marker onto its last line.
[ -s "$rules_file" ] && [ "$(tail -c1 "$rules_file" | od -An -c | tr -d ' ')" != '\n' ] && echo >> "$rules_file"

start="$(grep -n '^## Learned rules' "$rules_file" | head -1 | cut -d: -f1 || true)"
out="$tmp/rules.md"
if [ -z "$start" ]; then
  {
    cat "$rules_file"
    echo
    echo "## Learned rules"
    echo
    echo "*Appended by \`.icm/scripts/retrospective.sh --apply\` at Release and at the end of every lane —"
    echo "one rule per error class a run fixed and flagged, or fixed again. Edit or delete lines freely:"
    echo "this file is the repo's own, never synced.*"
    cat "$block"
  } > "$out"
  echo "created the \`## Learned rules\` section at the end of .icm/_shared/project-rules.md"
else
  next="$(awk -v s="$start" 'NR > s && /^## / {print NR; exit}' "$rules_file")"
  if [ -z "$next" ]; then
    cat "$rules_file" "$block" > "$out"
  else
    # Inside the section: before the heading that follows it, keeping one blank line before that heading.
    {
      head -n "$((next - 1))" "$rules_file" | sed -e :a -e '/^\n*$/{$d;N;ba' -e '}'
      cat "$block"
      echo
      tail -n "+$next" "$rules_file"
    } > "$out"
  fi
fi
cp "$out" "$rules_file"

echo "appended to .icm/_shared/project-rules.md → Learned rules:"
sed 's/^/  /' "$block"
echo "commit it with the run's record — the operator reads the rule in the PR; a slip is deleted by hand"
echo "RESULT: APPENDED $n_cand"; exit 0
