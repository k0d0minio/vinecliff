#!/usr/bin/env bash
# validate-intake.sh — structural self-check on an intake batch (the cut).
#
# The cut (.icm/stages/01_scope/CONTEXT.md step 6; formats in .icm/intake/CONTEXT.md) states four invariants that are pure
# bookkeeping, and today they are re-verified by the agent, conversationally, every time it re-reads
# the batch — and silently breakable by a hand-edit to breakdown.md afterwards:
#
#   1. every stub carries '- sequence: n of m', unique and contiguous over 1..m;
#   2. m agrees with how many stubs there actually are;
#   3. every 'depends-on:' names a stub in the same batch, sequenced BEFORE its dependent;
#   4. '## Build order' in breakdown.md lists the same slugs, in the same order, as the sequences;
#   5. the scope slug itself is not a name the intake tree or the estate board already owns:
#      'triage' (the parked one-offs), 'backlog' (legacy flat tickets) and 'runs' (the runs in
#      flight) are the board's pseudo-batches and '_done' is the archive — an epic cut under one
#      of them resolves to the pseudo-batch instead of itself, and no board renders it.
#
# All five are deterministic, so the agent shouldn't be spending context on them. This script owns
# them; the agent owns the judgement the contract also asks for (is each stub independently
# shippable, does it sit on a real product seam, is anything stub-sized actually scope-sized).
#
# Stubs already spun out live in <scope>/_done/ (new-run.sh --stub git mv's them there). They are
# still part of the batch for every check here — a partially consumed batch must still be a
# contiguous 1..m, or "next" stops meaning anything.
#
# Run by the SESSION before the intake gate (no workflow runs it — decision D43), ADVISORY — like
# validate-spec.sh, it warns and never blocks a PR. Requires no network. Pure
# bash/awk.
#
# Usage:
#   .icm/scripts/validate-intake.sh <scope-slug>          # resolves .icm/intake/<scope-slug>/
#   .icm/scripts/validate-intake.sh <path-to-intake-dir>  # or point at the folder directly
#
# Verdict (stdout, last line):
#   RESULT: OK        exit 0  — the batch's bookkeeping holds.
#   RESULT: SKIP      exit 0  — nothing to validate (no breakdown.md and no stubs).
#   RESULT: INVALID   exit 2  — one or more problems (listed on stderr) — fix and re-cut.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

die() { echo "error: $*" >&2; exit 1; }

# --- args → intake dir -----------------------------------------------------------------------------

arg=""
while [ $# -gt 0 ]; do
  case "$1" in
    --*) die "unknown flag: $1" ;;
    *)   [ -z "$arg" ] && arg="$1" || die "unexpected argument: $1"; shift ;;
  esac
done
[ -n "$arg" ] || die "usage: validate-intake.sh <scope-slug | path-to-intake-dir>"

if [ -d "$arg" ]; then
  dir="${arg%/}"
else
  dir="$repo_root/.icm/intake/$arg"
fi
[ -d "$dir" ] || die "no intake folder at '$dir' (cut the scope first — .icm/stages/01_scope/CONTEXT.md step 6)"

# --- the scope slug itself (invariant 5) -----------------------------------------------------------
# `triage batch` and Scope both slugify a title, and nothing else stops the result being a name the
# board already renders as a pseudo-batch (`runs`, `triage`, `backlog`) or the intake tree already
# uses (`_done`, the archive). Judged on the folder's own name — the scope slug — never on a stub's
# feature-slug. `triage/` itself is the backlog below, and is refused only once a breakdown.md says
# a batch was cut into it.

scope_slug="$(basename "$dir")"
reserved_slug() { case "$1" in runs|triage|backlog|_done) return 0 ;; *) return 1 ;; esac; }
reject_reserved() { # <slug> <why>
  echo "intake invalid: $dir" >&2
  echo "  ✗ '$1' is a reserved scope slug — $2. Re-cut the batch under another slug (triage batch / Scope's slugify step)" >&2
  echo "RESULT: INVALID"
  exit 2
}
if [ "$scope_slug" != "triage" ] && reserved_slug "$scope_slug"; then
  reject_reserved "$scope_slug" "runs, triage and backlog are the board's pseudo-batches and _done is the archive; an epic cut under one of them resolves to the pseudo-batch, never to itself"
fi

# --- triage/ is a backlog, not a batch -------------------------------------------------------------
# .icm/intake/triage/ holds parked off-ticket findings (intake/CONTEXT.md → Triage): no breakdown,
# no sequence, no depends-on. The only invariant is that every stub names the lane that will
# consume it, so /pipeline bug|tweak|chore can route it.

if [ "$scope_slug" = "triage" ]; then
  [ -f "$dir/breakdown.md" ] && reject_reserved "triage" ".icm/intake/triage/ is the parked-findings backlog, never an epic, yet it holds a breakdown.md — a batch was cut into it"
  shopt -s nullglob
  t_problems=(); t_count=0
  for f in "$dir"/*.md "$dir"/_done/*.md; do
    t_count=$((t_count + 1))
    lane="$(awk '/^-[[:space:]]+lane:/ { val = substr($0, index($0, ":") + 1);
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", val); print val; exit }' "$f")"
    case "$lane" in
      bug|tweak|chore) : ;;
      "") t_problems+=("$(basename "$f"): missing '- lane: bug|tweak|chore' — nothing can consume it") ;;
      *)  t_problems+=("$(basename "$f"): '- lane: $lane' is not bug|tweak|chore") ;;
    esac
  done
  shopt -u nullglob
  if [ "${#t_problems[@]}" -eq 0 ]; then
    echo "triage ok: $dir ($t_count stub(s), lane-tagged; no batch invariants apply)"
    echo "RESULT: OK"
    exit 0
  fi
  echo "triage invalid: $dir" >&2
  for p in "${t_problems[@]}"; do echo "  ✗ $p" >&2; done
  echo "RESULT: INVALID"
  exit 2
fi

breakdown="$dir/breakdown.md"

# --- collect the stubs -----------------------------------------------------------------------------
# Every .md in the folder except breakdown.md, plus everything under _done/ (spun out, still in the
# batch). Sorted for determinism; nullglob so an empty folder yields an empty list, not a literal.

shopt -s nullglob
stubs=()
for f in "$dir"/*.md "$dir"/_done/*.md; do
  [ "$(basename "$f")" = "breakdown.md" ] && continue
  stubs+=("$f")
done
shopt -u nullglob

if [ ! -f "$breakdown" ] && [ "${#stubs[@]}" -eq 0 ]; then
  echo "intake skipped: $dir has no breakdown.md and no stubs — nothing cut yet"
  echo "RESULT: SKIP"
  exit 0
fi

problems=()
add() { problems+=("$1"); }

[ -f "$breakdown" ] || add "missing breakdown.md — the cut's single review surface"

# --- header field reader ---------------------------------------------------------------------------
# Header fields are '- <name>: <value>' and prettier wraps long ones onto indented continuation
# lines (see vendor-metrics/vendor-dashboard-reconciliation.md → depends-on). Join them back up.

field() { # <file> <field-name>
  awk -v want="$2" '
    !grab && $0 ~ "^-[[:space:]]+" want ":" { val = substr($0, index($0, ":") + 1); grab = 1; next }
    grab && /^[[:space:]]+[^[:space:]]/ { val = val " " $0; next }
    grab { exit }
    END { gsub(/^[[:space:]]+|[[:space:]]+$/, "", val); gsub(/[[:space:]]+/, " ", val); print val }
  ' "$1"
}

# --- per-stub parse --------------------------------------------------------------------------------

declare -A seq_of=()      # feature-slug → sequence n
declare -A slug_at=()     # sequence n   → feature-slug
declare -A deps_of=()     # feature-slug → space-separated depends-on
declare -a batch_slugs=()
declared_m=""

for stub in "${stubs[@]}"; do
  base="$(basename "$stub" .md)"
  slug="$(field "$stub" "feature-slug")"

  if [ -z "$slug" ]; then
    add "$(basename "$stub"): missing '- feature-slug:' header"
    slug="$base"
  elif [ "$slug" != "$base" ]; then
    add "$(basename "$stub"): '- feature-slug: $slug' doesn't match the filename ('$base.md') — /pipeline new resolves stubs by filename"
    slug="$base"
  fi

  if [ -n "${seq_of[$slug]+x}" ]; then
    add "duplicate feature-slug '$slug' — two stubs claim the same slug"
    continue
  fi

  raw_seq="$(field "$stub" "sequence")"
  n="" ; m=""
  if [[ "$raw_seq" =~ ^([0-9]+)[[:space:]]+of[[:space:]]+([0-9]+) ]]; then
    n="${BASH_REMATCH[1]}"; m="${BASH_REMATCH[2]}"
  else
    add "$slug: missing or malformed '- sequence: <n> of <m>' (found: '${raw_seq:-}')"
  fi

  batch_slugs+=("$slug")
  deps_of[$slug]="$(field "$stub" "depends-on")"

  [ -n "$n" ] || continue
  seq_of[$slug]="$n"
  if [ -n "${slug_at[$n]+x}" ]; then
    add "sequence $n is claimed twice: '${slug_at[$n]}' and '$slug' — sequence must be unique"
  else
    slug_at[$n]="$slug"
  fi
  if [ -z "$declared_m" ]; then
    declared_m="$m"
  elif [ "$m" != "$declared_m" ]; then
    add "$slug: 'of $m' disagrees with 'of $declared_m' elsewhere in the batch — every stub sees the same total"
  fi
done

count="${#batch_slugs[@]}"

# 1. m agrees with the stub count.
if [ -n "$declared_m" ] && [ "$declared_m" -ne "$count" ]; then
  add "stubs say 'of $declared_m' but the batch holds $count stub(s) (including _done/) — re-cut, or a stub is missing"
fi

# 2. sequences are contiguous 1..count.
i=1
while [ "$i" -le "$count" ]; do
  [ -n "${slug_at[$i]+x}" ] || add "no stub carries 'sequence: $i of $count' — the order isn't contiguous"
  i=$((i + 1))
done

# 3. depends-on names an in-batch stub, sequenced before its dependent.
for slug in "${batch_slugs[@]}"; do
  deps="${deps_of[$slug]:-}"
  # Normalise: strip backticks, treat 'none' (any case, alone) as no dependency, split on commas.
  deps="${deps//\`/}"
  printf '%s' "$deps" | grep -Eiq '^[[:space:]]*none[[:space:].]*$' && continue
  [ -n "$deps" ] || { add "$slug: missing '- depends-on:' header (write 'none' when there are none)"; continue; }
  IFS=',' read -r -a dep_list <<< "$deps"
  for dep in "${dep_list[@]}"; do
    dep="$(printf '%s' "$dep" | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//')"
    [ -n "$dep" ] && [ "$dep" != "none" ] || continue
    if [ -z "${seq_of[$dep]+x}" ]; then
      add "$slug: depends-on '$dep', which isn't a stub in this batch (cross-scope dependencies belong in ## Notes for Define)"
    elif [ -n "${seq_of[$slug]+x}" ] && [ "${seq_of[$dep]}" -ge "${seq_of[$slug]}" ]; then
      add "$slug (sequence ${seq_of[$slug]}) depends-on '$dep' (sequence ${seq_of[$dep]}) — a dependency must be sequenced first"
    fi
  done
done

# 4. '## Build order' agrees with the stubs' sequences.
#    Numbered lines only ('1. <slug> — …'); the slug is the first token, backticks optional. Wrapped
#    continuation lines don't start with a number, so they're ignored.
if [ -f "$breakdown" ]; then
  order_section="$(awk '
    /^##[[:space:]]+Build order[[:space:]]*$/ { grab = 1; next }
    grab && /^##[[:space:]]/ { grab = 0 }
    grab { print }
  ' "$breakdown")"

  if ! grep -Eq '^##[[:space:]]+Build order[[:space:]]*$' "$breakdown"; then
    add "breakdown.md has no '## Build order' section — the order /pipeline new walks"
  else
    order_lines="$(printf '%s\n' "$order_section" | grep -E '^[0-9]+\.[[:space:]]' || true)"
    order_n=0
    while IFS= read -r line; do
      [ -n "$line" ] || continue
      order_n=$((order_n + 1))
      num="$(printf '%s' "$line" | sed -E 's/^([0-9]+)\..*/\1/')"
      ord_slug="$(printf '%s' "$line" | sed -E 's/^[0-9]+\.[[:space:]]+//; s/^`?([A-Za-z0-9_-]+)`?.*/\1/')"
      if [ "$num" -ne "$order_n" ]; then
        add "breakdown.md ## Build order: line $order_n is numbered '$num.' — the list must be contiguous 1..$count"
      fi
      if [ -z "${slug_at[$num]+x}" ]; then
        add "breakdown.md ## Build order: '$num. $ord_slug' has no stub at sequence $num"
      elif [ "${slug_at[$num]}" != "$ord_slug" ]; then
        add "breakdown.md ## Build order: '$num. $ord_slug' but the stub at sequence $num is '${slug_at[$num]}' — the two must agree"
      fi
    done <<< "$order_lines"

    if [ "$order_n" -ne "$count" ]; then
      add "breakdown.md ## Build order lists $order_n feature(s) but the batch holds $count stub(s) — every stub gets a line, including ones already in _done/"
    fi
  fi
fi

# --- verdict ---------------------------------------------------------------------------------------

if [ "${#problems[@]}" -eq 0 ]; then
  echo "intake ok: $dir ($count stub(s), sequenced 1..$count)"
  echo "RESULT: OK"
  exit 0
fi

echo "intake invalid: $dir" >&2
for p in "${problems[@]}"; do echo "  ✗ $p" >&2; done
echo "RESULT: INVALID"
exit 2
