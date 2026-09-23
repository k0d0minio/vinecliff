#!/usr/bin/env bash
# list-skills.sh — the Level-1 registry of the pipeline's capability skills (TEMPLATE-OWNED).
#
# `.icm/skills/<name>/SKILL.md` is a capability skill in three tiers (`.icm/skills/README.md`):
#   Level 1  the YAML front matter — `name`, `description`, `triggers` — thirty to fifty tokens,
#            the only part that is ever in a prompt by default;
#   Level 2  the body — the step-by-step procedure, loaded ONLY when a trigger matches the work;
#   Level 3  `references/` and `scripts/` beside it — read or run on demand from inside the body.
# This script prints Level 1 for every skill, compactly, so a session-start hook or a stage can
# put the registry in front of the model without loading a single body: one line per skill, the
# triggers on it, nothing else. It parses front matter with awk (a scalar, a `>-`/`|` block, a
# `- item` list, an inline `[a, b]` list) and reads nothing outside `.icm/skills/`.
#
# It PRINTS. It loads no skill, runs no script and decides nothing — a stage reads the line whose
# triggers match what it is doing and then loads that one SKILL.md itself.
#
# Usage:
#   .icm/scripts/list-skills.sh              # markdown: one bullet per skill, then RESULT
#   .icm/scripts/list-skills.sh --json       # a JSON array [{name, description, triggers, path}]
#   .icm/scripts/list-skills.sh --bare       # the markdown lines only, no RESULT — for injection
#   .icm/scripts/list-skills.sh --check      # validate every SKILL.md: the three keys, a body,
#                                            # the folder named after `name`, Level 1 ≤ 80 tokens
#   … [--dir <path>]                         # another skills folder (default .icm/skills)
#
# Verdict (stdout, last line; omitted with --bare; on stderr with --json so the JSON pipes clean):
#   RESULT: OK <n>        exit 0  — <n> skills listed (0 is fine: the folder is optional)
#   RESULT: INVALID <n>   exit 2  — --check found <n> problem(s); each is listed above it
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$repo_root"
die() { echo "error: $*" >&2; exit 1; }

mode="md"; check=0; bare=0; dir=".icm/skills"
while [ $# -gt 0 ]; do
  case "$1" in
    --json)    mode="json"; shift ;;
    --bare)    bare=1; shift ;;
    --check)   check=1; shift ;;
    --dir)     dir="${2:-}"; [ -n "$dir" ] || die "--dir needs a path"; shift 2 ;;
    -h|--help) sed -n '2,28p' "${BASH_SOURCE[0]}"; exit 0 ;;
    *)         die "unknown argument: $1 (usage: list-skills.sh [--json|--bare] [--check] [--dir <path>])" ;;
  esac
done
dir="${dir%/}"

# --- parse one SKILL.md's front matter into "key<TAB>value" lines, plus body<TAB><line count> -------
front_matter() { # <file>
  awk '
    BEGIN { fm = 0; done = 0; key = ""; mode = ""; body = 0 }
    NR == 1 { if ($0 == "---") { fm = 1; next } else { done = 1 } }
    fm && $0 == "---" { fm = 0; done = 1; next }
    done { if ($0 ~ /[^[:space:]]/) body++; next }
    fm {
      if (match($0, /^[A-Za-z_][A-Za-z0-9_-]*:/)) {
        key = substr($0, 1, RLENGTH - 1); rest = substr($0, RLENGTH + 1)
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", rest)
        if (rest == ">-" || rest == ">" || rest == "|" || rest == "|-") { mode = "block"; val[key] = "" }
        else if (rest == "")                                             { mode = "list";  val[key] = "" }
        else {
          mode = "scalar"
          if (rest ~ /^\[.*\]$/) { rest = substr(rest, 2, length(rest) - 2) }
          gsub(/^["\047]|["\047]$/, "", rest)
          val[key] = rest
        }
        next
      }
      if (mode == "block" && $0 ~ /^[[:space:]]+/) {
        line = $0; gsub(/^[[:space:]]+|[[:space:]]+$/, "", line)
        val[key] = (val[key] == "" ? line : val[key] " " line); next
      }
      if (mode == "list" && $0 ~ /^[[:space:]]*-[[:space:]]+/) {
        line = $0; sub(/^[[:space:]]*-[[:space:]]+/, "", line); gsub(/^["\047]|["\047]$/, "", line)
        val[key] = (val[key] == "" ? line : val[key] ", " line); next
      }
    }
    END {
      for (k in val) printf "%s\t%s\n", k, val[k]
      printf "body\t%d\n", body
    }
  ' "$1"
}
field() { # <parsed> <key>
  printf '%s\n' "$1" | awk -F'\t' -v k="$2" '$1 == k { print substr($0, length(k) + 2); exit }'
}

names=(); descs=(); trigs=(); paths=()
problems=0
if [ -d "$dir" ]; then
  while IFS= read -r skill_md; do
    folder="$(basename "$(dirname "$skill_md")")"
    parsed="$(front_matter "$skill_md")"
    name="$(field "$parsed" name)"; desc="$(field "$parsed" description)"
    trig="$(field "$parsed" triggers)"; body="$(field "$parsed" body)"
    if [ "$check" -eq 1 ]; then
      [ -n "$name" ] || { echo "  [INVALID] $skill_md: no \`name\` in the front matter"; problems=$((problems + 1)); }
      [ -n "$desc" ] || { echo "  [INVALID] $skill_md: no \`description\` in the front matter"; problems=$((problems + 1)); }
      [ -n "$trig" ] || { echo "  [INVALID] $skill_md: no \`triggers\` in the front matter (a list, or a comma-separated line)"; problems=$((problems + 1)); }
      [ -z "$name" ] || [ "$name" = "$folder" ] || { echo "  [INVALID] $skill_md: name '$name' is not the folder name '$folder'"; problems=$((problems + 1)); }
      [ "${body:-0}" -gt 0 ] || { echo "  [INVALID] $skill_md: no body after the front matter — Level 2 is the procedure"; problems=$((problems + 1)); }
      # Level 1 budget: ~1.3 tokens per word is the usual estimate; 80 is the ceiling, 30–50 the aim.
      words="$(printf '%s %s %s' "$name" "$desc" "$trig" | wc -w | tr -d ' ')"
      est=$(( words * 13 / 10 ))
      if [ "$est" -gt 80 ]; then echo "  [INVALID] $skill_md: Level 1 is ~$est tokens (aim 30–50, ceiling 80) — shorten description/triggers"; problems=$((problems + 1)); fi
    fi
    names+=("${name:-$folder}"); descs+=("$desc"); trigs+=("$trig"); paths+=("$skill_md")
  done < <(find "$dir" -mindepth 2 -maxdepth 2 -name SKILL.md 2>/dev/null | sort)
fi
n="${#names[@]}"

if [ "$mode" = "json" ]; then
  command -v jq >/dev/null 2>&1 || die "--json needs jq"
  if [ "$n" -eq 0 ]; then echo "[]"; else
    for i in $(seq 0 $((n - 1))); do
      jq -n --arg name "${names[$i]}" --arg desc "${descs[$i]}" --arg trig "${trigs[$i]}" --arg path "${paths[$i]}" \
        '{name: $name, description: $desc, triggers: ($trig | split(",") | map(gsub("^\\s+|\\s+$"; "")) | map(select(. != ""))), path: $path}'
    done | jq -s .
  fi
else
  if [ "$n" -gt 0 ]; then
    [ "$bare" -eq 1 ] || echo "## Capability skills ($dir/) — load a SKILL.md only when one of its triggers matches the work"
    for i in $(seq 0 $((n - 1))); do
      echo "- ${names[$i]} — ${descs[$i]}${trigs[$i]:+ · triggers: ${trigs[$i]}}"
    done
  elif [ "$bare" -eq 0 ]; then
    echo "no capability skills under $dir/ (optional — see .icm/skills/README.md)"
  fi
fi

[ "$bare" -eq 1 ] && exit 0
# --json keeps stdout for the JSON alone, so `list-skills.sh --json | jq` works; the verdict goes to stderr.
if [ "$mode" = "json" ]; then exec >&2; fi
if [ "$check" -eq 1 ] && [ "$problems" -gt 0 ]; then echo "RESULT: INVALID $problems"; exit 2; fi
echo "RESULT: OK $n"
