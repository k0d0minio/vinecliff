#!/usr/bin/env bash
# triage-report.sh — one deterministic read of the triage backlog (.icm/intake/triage/).
#
# The folder is the pipeline's parking lane (.icm/intake/CONTEXT.md → Triage): every stage parks
# its off-ticket findings there as small stubs, and only the lanes consume them. Nothing else
# reads the folder as a whole, so it grows silently and duplicates of one finding pile up. This
# script is the read: `/pipeline triage report` runs it, and every stage that parks a finding
# checks the active count against the cap it prints.
#
# What it prints (markdown, stdout):
#   - totals: active stubs (top level), _done/ stubs, and the cap verdict;
#   - counts by lane, by found-by source (Release review kind / Build / lane / audit …), by
#     area (derived from the repo paths each stub cites — apps/<app>, packages/<pkg>, .icm,
#     .github, .claude; a stub citing several counts once in each), and by age (days since the
#     date on its found-by line);
#   - a near-duplicate list: stubs whose titles share >= 4 significant words, and stubs that cite
#     the same file:line.
# It reads only the top-level stubs as "active"; _done/ is counted but never classified. The last
# line is the verdict:
#   RESULT: OK — <active> active (<by lane>) · <done> done · cap <cap>: <UNDER | OVER by n>
# exit 0 always when the folder exists (an over-cap folder is a fact to report, not a failure);
# exit 1 on a usage error or a missing folder.
#
# Pure bash + awk + coreutils (mawk-compatible: no gawk extensions). No network, no git.
# NOT a repo check — the block-local-checks hook does not match it; run it freely.
#
# Usage:
#   .icm/scripts/triage-report.sh                       # .icm/intake/triage/, today, cap 60
#   .icm/scripts/triage-report.sh --dir <path>          # another folder with the same shape
#   .icm/scripts/triage-report.sh --today 2026-09-15    # pin "today" (ages are deterministic)
#   .icm/scripts/triage-report.sh --cap 60              # the cap (intake/CONTEXT.md → Triage → cap)
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

die() { echo "error: $*" >&2; exit 1; }

dir="$repo_root/.icm/intake/triage"
today="$(date -u +%F)"
cap=60   # the number lives in .icm/intake/CONTEXT.md (Triage → cap); this is its default copy
while [ $# -gt 0 ]; do
  case "$1" in
    --dir)   dir="${2:-}"; shift 2 ;;
    --today) today="${2:-}"; shift 2 ;;
    --cap)   cap="${2:-}"; shift 2 ;;
    -h|--help) sed -n '2,32p' "${BASH_SOURCE[0]}"; exit 0 ;;
    *) die "unknown argument: $1 (usage: triage-report.sh [--dir <path>] [--today YYYY-MM-DD] [--cap N])" ;;
  esac
done
[ -d "$dir" ] || die "no triage folder at '$dir'"
printf '%s' "$today" | grep -Eq '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' || die "--today must be YYYY-MM-DD"
printf '%s' "$cap" | grep -Eq '^[0-9]+$' || die "--cap must be an integer"
today_s="$(date -u -d "$today" +%s)"
rel="${dir#"$repo_root"/}"

# --- collect -----------------------------------------------------------------------------------------

shopt -s nullglob
active=()
for f in "$dir"/*.md; do active+=("$f"); done
done_n=0
for f in "$dir"/_done/*.md; do done_n=$((done_n + 1)); done
shopt -u nullglob
active_n="${#active[@]}"

# Header fields are '- <name>: <value>'; prettier wraps long ones onto indented continuation lines.
field() { # <file> <field-name>
  awk -v want="$2" '
    !grab && $0 ~ "^-[[:space:]]+" want ":" { val = substr($0, index($0, ":") + 1); grab = 1; next }
    grab && /^[[:space:]]+[^[:space:]]/ { val = val " " $0; next }
    grab { exit }
    END { gsub(/^[[:space:]]+|[[:space:]]+$/, "", val); gsub(/[[:space:]]+/, " ", val); print val }
  ' "$1"
}

# The title: the first '# ' line, minus the '<Kind>: ' prefix ('# Stub: …', '# Triage: …').
title_of() {
  awk '/^# / { sub(/^# +/, ""); sub(/^[A-Za-z]+: +/, ""); print; exit }' "$1"
}

# The found-by line names where a stub came from in free prose. Classify by keyword, most specific
# first: the three Release review passes, then Release itself, Build, a lane, an audit, a chat.
source_of() { # <found-by text, lowercased>
  local s="$1"
  case "$s" in
    *readiness*)                         echo "Release · production-readiness" ;;
    *security*)                          echo "Release · security review" ;;
    *code-review*|*"code review"*)       echo "Release · code review" ;;
    *release*|*review*)                  echo "Release · review (kind not named)" ;;
    *"(build"*|*" build"*|*"build)"*)    echo "Build" ;;
    *"bug lane"*|*"tweak lane"*|*"chore lane"*|*"(bug)"*|*"(tweak)"*|*"(chore)"*|*lane*)
                                         echo "Lane" ;;
    *audit*)                             echo "Audit" ;;
    *conversation*|*chat*|*operator*)    echo "Conversation" ;;
    "")                                  echo "(no found-by line)" ;;
    *)                                   echo "Run named, stage not named" ;;
  esac
}

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
: > "$tmp/rows"      # name \t lane \t source \t run \t date \t age-bucket
: > "$tmp/areas"     # area \t name
: > "$tmp/cites"     # file:line \t name
: > "$tmp/titles"    # name \t significant words (space-separated, sorted, unique)

stop_re='^(the|and|for|are|but|not|with|from|that|this|than|then|into|out|over|under|after|before|when|its|has|have|does|did|was|were|will|can|per|via|one|two|any|all|each|every|only|never|still|should|would|could|also|too|very|off|own|our|your|their|them|they|there|where|what|which|who|how|why|is|it|in|on|at|by|to|of|as|an|or|be|no|so|up|do|if|we|us|you|a|i|s|t)$'

for f in "${active[@]}"; do
  name="$(basename "$f" .md)"

  lane="$(field "$f" lane)"
  case "$lane" in bug|tweak|chore) : ;; "") lane="(no lane)" ;; *) lane="(invalid: $lane)" ;; esac

  fb="$(field "$f" found-by)"
  fb_lc="$(printf '%s' "$fb" | tr '[:upper:]' '[:lower:]')"
  src="$(source_of "$fb_lc")"
  run="$(printf '%s' "$fb" | awk '{ w = $1; gsub(/[^A-Za-z0-9_-]/, "", w); print w }')"
  [ -n "$run" ] || run="(none)"

  d="$(printf '%s' "$fb" | grep -oE '[0-9]{4}-[0-9]{2}-[0-9]{2}' | tail -n1 || true)"
  if [ -n "$d" ] && d_s="$(date -u -d "$d" +%s 2>/dev/null)"; then
    days=$(( (today_s - d_s) / 86400 ))
    if   [ "$days" -le 7 ];  then bucket="1 · 0–7 days"
    elif [ "$days" -le 14 ]; then bucket="2 · 8–14 days"
    elif [ "$days" -le 30 ]; then bucket="3 · 15–30 days"
    else                          bucket="4 · over 30 days"; fi
  else
    d="(no date)"; bucket="5 · no date on found-by"
  fi
  printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$name" "$lane" "$src" "$run" "$d" "$bucket" >> "$tmp/rows"

  # Areas: every repo path the stub cites, anywhere in its body (the Problem section is where
  # they are meant to be; a path first named under Proposed change still places the stub).
  areas="$(grep -oE '(^|[^A-Za-z0-9_/.-])((apps|packages)/[A-Za-z0-9_-]+|\.icm|\.github|\.claude)' "$f" \
    | sed -E 's/^[^A-Za-z0-9_.]//' | sort -u || true)"
  if [ -n "$areas" ]; then
    printf '%s\n' "$areas" | awk -v n="$name" '{ print $0 "\t" n }' >> "$tmp/areas"
  else
    printf '(no path cited)\t%s\n' "$name" >> "$tmp/areas"
  fi

  # file:line citations — the same defect written up twice tends to point at the same line.
  grep -oE '[A-Za-z0-9_./-]+\.(ts|tsx|js|mjs|cjs|sh|md|mdx|yaml|yml|json|css):[0-9]+' "$f" \
    | sort -u | awk -v n="$name" '{ print $0 "\t" n }' >> "$tmp/cites" || true

  # Title words: lowercased, punctuation stripped, stop words and short tokens dropped.
  words="$(title_of "$f" | tr '[:upper:]' '[:lower:]' | tr -c 'a-z0-9\n' ' ' | tr ' ' '\n' \
    | grep -E '^[a-z0-9]{3,}$' | grep -Ev "$stop_re" | sort -u | tr '\n' ' ' || true)"
  printf '%s\t%s\n' "$name" "${words% }" >> "$tmp/titles"
done

# --- tables -------------------------------------------------------------------------------------------

# count_table <column-title> <file> <field-index> [byname] — a two-column markdown table, count
# desc then name asc; `byname` orders by the name instead (the age buckets carry a sort prefix).
count_table() {
  local head="$1" file="$2" col="$3" order="${4:-bycount}" keys
  case "$order" in byname) keys="-k1,1" ;; *) keys="-k2,2nr -k1,1" ;; esac
  printf '| %s | stubs |\n| --- | ---: |\n' "$head"
  if [ -s "$file" ]; then
    # shellcheck disable=SC2086 — $keys is two sort flags on purpose
    cut -f"$col" "$file" | sort | uniq -c | awk '{ c = $1; $1 = ""; sub(/^ /, ""); print $0 "\t" c }' \
      | sort -t"$(printf '\t')" $keys | awk -F'\t' '{ printf "| %s | %s |\n", $1, $2 }'
  else
    printf '| (none) | 0 |\n'
  fi
}

lane_summary="$(cut -f2 "$tmp/rows" | sort | uniq -c | awk '{ c = $1; $1 = ""; sub(/^ /, ""); print $0 "\t" c }' \
  | sort -t"$(printf '\t')" -k2,2nr -k1,1 | awk -F'\t' '{ printf "%s%s %s", (NR > 1 ? " · " : ""), $2, $1 }')"
[ -n "$lane_summary" ] || lane_summary="empty"

if [ "$active_n" -gt "$cap" ]; then
  cap_verdict="OVER by $((active_n - cap))"
else
  cap_verdict="UNDER"
fi

printf '# Triage report — %s\n\n' "$today"
printf -- '- folder: `%s/`\n' "$rel"
printf -- '- active stubs: **%s** (%s) · in `_done/`: %s\n' "$active_n" "$lane_summary" "$done_n"
if [ "$active_n" -gt "$cap" ]; then
  printf -- '- cap: %s — **over by %s**. Every stage that parks a finding says so in its stop message (`.icm/intake/CONTEXT.md` → Triage → cap); `triage batch <area|lane> "<epic-title>"` and `triage prune` bring it down.\n' "$cap" "$((active_n - cap))"
else
  printf -- '- cap: %s — under (%s left).\n' "$cap" "$((cap - active_n))"
fi

printf '\n## By lane\n\n'
count_table "lane" "$tmp/rows" 2

printf '\n## By found-by source\n\n'
count_table "source" "$tmp/rows" 3

printf '\n### Top originating runs\n\n'
printf '| run / origin (first token of found-by) | stubs |\n| --- | ---: |\n'
cut -f4 "$tmp/rows" | sort | uniq -c | awk '{ c = $1; $1 = ""; sub(/^ /, ""); print $0 "\t" c }' \
  | sort -t"$(printf '\t')" -k2,2nr -k1,1 | head -n 12 | awk -F'\t' '{ printf "| %s | %s |\n", $1, $2 }'

printf '\n## By area\n\n'
printf '(from the repo paths each stub cites — a stub naming several areas counts once in each)\n\n'
count_table "area" "$tmp/areas" 1

printf '\n## By age\n\n'
printf '(days from the date on the found-by line to %s)\n\n' "$today"
count_table "age" "$tmp/rows" 6 byname
oldest="$(cut -f5 "$tmp/rows" | grep -E '^[0-9]{4}-' | sort | head -n1 || true)"
newest="$(cut -f5 "$tmp/rows" | grep -E '^[0-9]{4}-' | sort | tail -n1 || true)"
[ -n "$oldest" ] && printf '\noldest: %s · newest: %s\n' "$oldest" "$newest"

# Older than 30 days — the prune candidates, by name, so `triage prune` needs no second read.
old_list="$(awk -F'\t' '$6 ~ /^4 / { print $1 " (" $5 ")" }' "$tmp/rows" | sort)"
printf '\n### Older than 30 days (prune candidates)\n\n'
if [ -n "$old_list" ]; then printf '%s\n' "$old_list" | sed 's/^/- /'; else printf '(none)\n'; fi

printf '\n## Near-duplicates\n\n'
dup_n=0

printf '### Same file:line cited\n\n'
same_cite="$(sort -u "$tmp/cites" | awk -F'\t' '
  { n[$1]++; who[$1] = (who[$1] ? who[$1] ", " : "") $2 }
  END { for (c in n) if (n[c] > 1) print c "\t" who[c] }' | sort)"
if [ -n "$same_cite" ]; then
  printf '%s\n' "$same_cite" | awk -F'\t' '{ printf "- `%s` — %s\n", $1, $2 }'
  dup_n=$((dup_n + $(printf '%s\n' "$same_cite" | wc -l)))
else
  printf '(none)\n'
fi

printf '\n### Titles sharing 4 or more significant words\n\n'
shared="$(sort "$tmp/titles" | awk -F'\t' '
  { name[NR] = $1; words[NR] = $2 }
  END {
    for (i = 1; i <= NR; i++) {
      delete seen; ni = split(words[i], wi, " ")
      for (k = 1; k <= ni; k++) seen[wi[k]] = 1
      for (j = i + 1; j <= NR; j++) {
        nj = split(words[j], wj, " "); common = 0; list = ""
        for (k = 1; k <= nj; k++) if (wj[k] in seen) { common++; list = list (list ? " " : "") wj[k] }
        if (common >= 4) printf "%d\t%s\t%s\t%s\n", common, name[i], name[j], list
      }
    }
  }' | sort -t"$(printf '\t')" -k1,1nr -k2,2 -k3,3)"
if [ -n "$shared" ]; then
  printf '%s\n' "$shared" | awk -F'\t' '{ printf "- %s · %s — %s shared: %s\n", $2, $3, $1, $4 }'
  dup_n=$((dup_n + $(printf '%s\n' "$shared" | wc -l)))
else
  printf '(none)\n'
fi

printf '\n## Stubs with a problem\n\n'
bad="$(awk -F'\t' '$2 ~ /^\(/ { print $1 ": " $2 } $6 ~ /^5 / { print $1 ": no YYYY-MM-DD on its found-by line" }' "$tmp/rows" | sort)"
if [ -n "$bad" ]; then printf '%s\n' "$bad" | sed 's/^/- /'; else printf '(none)\n'; fi

printf '\n'
printf 'RESULT: OK — %s active (%s) · %s done · %s near-duplicate pair(s)/citation(s) · cap %s: %s\n' \
  "$active_n" "$lane_summary" "$done_n" "$dup_n" "$cap" "$cap_verdict"
exit 0
