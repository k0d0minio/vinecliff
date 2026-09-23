#!/usr/bin/env bash
# session-start.sh — canonical estate hook (icm-board _system/template/claude/hooks/).
# Opens every session in this repo knowing its own board: open stubs per epic (with the
# next in sequence), the triage backlog, and any legacy flat tickets still unmigrated.
# Quiet on failure — a hook must never break session start (exit 0, always).
#
# What it does, in order:
#   0. In a Claude Code cloud container only (CLAUDE_CODE_REMOTE=true) with no rsync on PATH
#      and apt-get present: install rsync, which .icm/scripts/env-check.sh requires — the cloud
#      image ships without it, so every /setup there would end `[FAIL] Missing required binary:
#      rsync`. One retry after `apt-get update`; all output discarded; on failure one line says
#      env-check.sh will FAIL on rsync. A local machine is never touched. The only step that
#      writes anything.
#   1. The cloud env hydrate step (vercel-env-hydrate.sh), where the repo carries it.
#   2. The capability-skills registry, where the repo has .icm/skills/.
#   3. The board: open stubs per epic, triage, legacy flat tickets.
set -uo pipefail

# 0. rsync in a cloud container. `timeout` bounds a held dpkg lock; nothing here can fail the session.
if [[ "${CLAUDE_CODE_REMOTE:-}" == "true" ]] && ! command -v rsync >/dev/null 2>&1 && command -v apt-get >/dev/null 2>&1; then
  apt_rsync() { DEBIAN_FRONTEND=noninteractive timeout 180 apt-get install -y -qq rsync >/dev/null 2>&1; }
  if ! apt_rsync && ! { DEBIAN_FRONTEND=noninteractive timeout 180 apt-get update -qq >/dev/null 2>&1; apt_rsync; }; then
    echo "session-start: could not install rsync in this cloud container — .icm/scripts/env-check.sh will FAIL on rsync (and setup.sh report GAPS) until it is on PATH."
  fi
fi

# The cloud env step, in repos that carry it. It lives in its own file — reporting a
# board and hydrating an environment are different jobs, and only one of them touches the
# network — but it is invoked from here rather than registered in settings.json, so that
# one SessionStart entry carries both and a repo's hand-owned settings.json gains nothing
# new to diverge over. (That entry is now `icm-check --fix`'s to add where it is absent,
# decision D18 — the divergence this originally routed around is no longer the argument;
# one registration for two hooks still is.) Inert unless the session was handed a
# VERCEL_TOKEN, which is no local session — see that file's header.
hydrate="${CLAUDE_PROJECT_DIR:-.}/.claude/hooks/vercel-env-hydrate.sh"
if [[ -x "$hydrate" ]]; then "$hydrate" || true; fi

# The capability-skills registry (Level 1 only — one line per skill, its triggers on it), so a
# stage sees what it may load without loading any of it. Quiet when the repo has none.
skills="${CLAUDE_PROJECT_DIR:-.}/.icm/scripts/list-skills.sh"
if [[ -x "$skills" ]] && [[ -d "${CLAUDE_PROJECT_DIR:-.}/.icm/skills" ]]; then
  reg="$("$skills" --bare 2>/dev/null || true)"
  if [[ -n "$reg" ]]; then
    echo "Capability skills (.icm/skills/ — load a SKILL.md only when one of its triggers matches the work):"
    printf '%s\n' "$reg"
  fi
fi

intake="${CLAUDE_PROJECT_DIR:-.}/.icm/intake"
[[ -d "$intake" ]] || exit 0

open=0; legacy=0; triage=0
lines=()

# Epics: every directory except triage/ and _done/.
for epic in "$intake"/*/; do
  [[ -d "$epic" ]] || continue
  name="$(basename "$epic")"
  [[ "$name" == "triage" || "$name" == "_done" ]] && continue
  n=0; next=""; next_seq=999999
  for f in "$epic"*.md; do
    [[ -e "$f" ]] || continue
    [[ "$(basename "$f")" == "breakdown.md" ]] && continue
    n=$((n + 1))
    seq="$(grep -m1 -E '^- *sequence:' "$f" 2>/dev/null | grep -oE '[0-9]+' | head -1 || true)"
    [[ -n "$seq" ]] || seq=999998
    if (( seq < next_seq )); then next_seq=$seq; next="$(basename "$f" .md)"; fi
  done
  (( n > 0 )) || continue
  open=$((open + n))
  lines+=("  $name: $n open — next: ${next:-?}")
done

# Triage backlog.
if [[ -d "$intake/triage" ]]; then
  for f in "$intake/triage"/*.md; do
    [[ -e "$f" ]] || continue
    triage=$((triage + 1))
  done
fi
open=$((open + triage))

# Legacy flat tickets (pre-2026-08-28 shape) — still open, awaiting a /project re-cut.
for f in "$intake"/[A-Z]*-[0-9]*.md; do
  [[ -e "$f" ]] || continue
  legacy=$((legacy + 1))
done
open=$((open + legacy))

(( open > 0 )) || exit 0
(( ${#lines[@]} > 0 )) && printf '%s\n' "${lines[@]}"
(( triage > 0 )) && echo "  triage: $triage parked"
(( legacy > 0 )) && echo "  legacy: $legacy unmigrated flat ticket(s)"
echo "$open open stub(s) in .icm/intake/ — planning lives there, never a loose TODO.md."
exit 0
