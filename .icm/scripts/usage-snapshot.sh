#!/usr/bin/env bash
# usage-snapshot.sh — record what this session has spent so far, as one line on the run (TEMPLATE-OWNED).
#
# Every stage and lane calls it twice — the first act after the preamble (`start`) and the last act
# before the stop (`end`) — and each call appends ONE line to `.icm/runs/<slug>/usage.md`:
#
#   - usage: <stage> <start|end> <ISO-8601Z> harness=<claude|claude-cloud|opencode> session=<id>
#            source=<transcript|sqlite|skip> model=<provider/model|mixed> in=<n> out=<n>
#            cache_read=<n> cache_write=<n> cost_usd=<n.nnnn|unknown> turns=<n|unknown>
#
# Each number is CUMULATIVE for the session (subagents included) at that moment; a stage's own
# usage is `end − start` when both lines name the same `session=`; a stage resumed in a second
# session is two partial pairs the roll-up reports as such. The file is append-only and travels
# with the run into the archive (close-out.sh moves the whole folder). It is not `run.md`: Scope
# has no run.md at its entry and run.md is the pointer index three scripts parse.
#
# Where the numbers come from — verified on the installed harnesses (agency brief §4.4a):
#   Claude Code (local and cloud)  CLAUDE_CODE_SESSION_ID is exported to every Bash call; the
#                                  transcript is ~/.claude/projects/<cwd-slug>/<session>.jsonl
#                                  (found by name, sidestepping the path encoding). Every API
#                                  response is a `type: "assistant"` line with requestId, model
#                                  and message.usage; streaming repeats a requestId, so the LAST
#                                  line per requestId is summed. Subagents: <session>/subagents/*.jsonl.
#                                  Turns: `type: "user"` lines with origin.kind == "human". Cost is
#                                  not in the transcript: priced here from lib/model-prices.json
#                                  (input, output, cache read, cache write by TTL when the
#                                  breakdown is present) — cost_usd=unknown when the model is
#                                  missing from the table, never zero. The transcript is written
#                                  asynchronously and may lag one request: it under-counts, never over.
#   OpenCode                       OPENCODE_SESSION_ID from the shell.env plugin (icm-session-env.js;
#                                  the binary exports no session variable itself); the SQLite
#                                  store ~/.local/share/opencode/opencode.db (OPENCODE_DB or
#                                  XDG_DATA_HOME respected), read-only: the session row's cost and
#                                  token columns plus its children (parent_id). Turns: message rows
#                                  with data.role == "user". Cost recorded as OpenCode computed it.
#                                  Without the plugin the newest session for this directory is the
#                                  fallback; with neither → source=skip. Needs python3 or sqlite3.
#
# When to call `end`: just before `close-out.sh`, so the archive commit carries the line — nothing
# written after the close-out reaches the PR. An `end` that comes later still lands in the archived
# copy of the run (never a recreated live folder) and is the caller's to commit.
#
# It never estimates and never blocks: a store it cannot read is a `source=skip` line and a SKIP
# verdict, and the stage carries on. Nothing is sent anywhere; nothing outside the repo is
# written; the harness's own files are only ever read.
#
# Usage:
#   .icm/scripts/usage-snapshot.sh <slug> <stage> start|end
#   .icm/scripts/usage-snapshot.sh --report <slug>      the run's totals so far, from its usage.md
#
# Verdict (stdout, last line):
#   RESULT: RECORDED            exit 0  — a line with a real source was appended
#   RESULT: SKIP (<reason>)     exit 0  — a source=skip line was appended (or nothing to report)
#   RESULT: REPORT              exit 0  — --report printed the totals
set -uo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
prices="$here/lib/model-prices.json"
die() { echo "error: $*" >&2; exit 1; }
command -v jq >/dev/null 2>&1 || die "jq not found"

# shellcheck source=lib/project.sh
source "$here/lib/project.sh"

# --- --report ------------------------------------------------------------------------------------------------

if [ "${1:-}" = "--report" ]; then
  slug="${2:-}"; [ -n "$slug" ] || die "usage: usage-snapshot.sh --report <slug>"
  f="$repo_root/.icm/runs/$slug/usage.md"; [ -f "$f" ] || f="$repo_root/$runs_archive_rel/$slug/usage.md"
  [ -f "$f" ] || { echo "no usage.md for '$slug' (live or archived)"; echo "RESULT: SKIP (no usage.md)"; exit 0; }
  echo "=== usage for $slug (prices as of $(jq -r .as_of "$prices")) ==="
  awk '
    /^- usage: / {
      stage=$3; kind=$4; sess=""; for (i=5;i<=NF;i++) { split($i, kv, "="); v[kv[1]]=kv[2] }
      key=stage "|" v["session"]
      if (kind=="start") { s_in[key]=v["in"]; s_out[key]=v["out"]; s_cr[key]=v["cache_read"]; s_cw[key]=v["cache_write"]; s_cost[key]=v["cost_usd"]; seen[key]=1 }
      if (kind=="end")   { e_in[key]=v["in"]; e_out[key]=v["out"]; e_cr[key]=v["cache_read"]; e_cw[key]=v["cache_write"]; e_cost[key]=v["cost_usd"]; seen[key]=1; model[key]=v["model"]; harness[key]=v["harness"] }
    }
    END {
      printf "%-12s %-10s %-24s %10s %10s %12s %12s %10s\n", "stage", "harness", "session", "in", "out", "cache_read", "cache_write", "cost_usd"
      for (k in seen) {
        split(k, p, "|")
        if (k in s_in && k in e_in) {
          c = (s_cost[k]=="unknown" || e_cost[k]=="unknown") ? "unknown" : sprintf("%.4f", e_cost[k]-s_cost[k])
          printf "%-12s %-10s %-24s %10d %10d %12d %12d %10s\n", p[1], harness[k], substr(p[2],1,24), e_in[k]-s_in[k], e_out[k]-s_out[k], e_cr[k]-s_cr[k], e_cw[k]-s_cw[k], c
          t_in+=e_in[k]-s_in[k]; t_out+=e_out[k]-s_out[k]; t_cr+=e_cr[k]-s_cr[k]; t_cw+=e_cw[k]-s_cw[k]; if (c!="unknown") t_cost+=c; else unk=1
        } else printf "%-12s %-10s %-24s %s\n", p[1], "", substr(p[2],1,24), (k in s_in) ? "(start only — stage still open or resumed elsewhere)" : "(end without start)"
      }
      printf "%-12s %-10s %-24s %10d %10d %12d %12d %10s\n", "total", "", "", t_in, t_out, t_cr, t_cw, unk ? sprintf("%.4f+unknown", t_cost) : sprintf("%.4f", t_cost)
    }' "$f"
  echo "RESULT: REPORT"; exit 0
fi

# --- args ---------------------------------------------------------------------------------------------------

slug="${1:-}"; stage="${2:-}"; mark="${3:-}"
[ -n "$slug" ] && [ -n "$stage" ] && [ -n "$mark" ] || die "usage: usage-snapshot.sh <slug> <stage> start|end   |   --report <slug>"
case "$mark" in start|end) : ;; *) die "third argument must be start|end" ;; esac
run_dir="$repo_root/.icm/runs/$slug"
# A stage's `end` can come after close-out.sh has archived the run: the line then belongs where the
# run now lives, never in a fresh live folder — a live folder for a closed-out run is the archive
# alarm (runs/README.md). The contracts place `end` just before the close-out so its commit carries
# the line; this is the safety net for a call that comes later.
if [ ! -d "$run_dir" ] && [ -d "$repo_root/$runs_archive_rel/$slug" ]; then run_dir="$repo_root/$runs_archive_rel/$slug"; fi
mkdir -p "$run_dir"
out="$run_dir/usage.md"
stamp="$(date -u +%FT%TZ)"

harness="none"; session=""; source="skip"; model="unknown"; t_in=0; t_out=0; t_cr=0; t_cw=0; cost="unknown"; turns="unknown"; reason=""

if [ "${CLAUDE_CODE_REMOTE:-}" = "true" ] || [ -n "${CLAUDE_CODE_REMOTE_SESSION_ID:-}" ]; then harness="claude-cloud"
elif [ -n "${CLAUDECODE:-}" ] || [ -n "${CLAUDE_CODE_SESSION_ID:-}" ]; then harness="claude"
elif [ -n "${OPENCODE_SESSION_ID:-}" ] || env | grep -q '^OPENCODE'; then harness="opencode"
fi

# --- Claude Code: the transcript ------------------------------------------------------------------------------

read_claude() {
  session="${CLAUDE_CODE_SESSION_ID:-}"
  [ -n "$session" ] || { reason="CLAUDE_CODE_SESSION_ID unset"; return; }
  local f; f="$(find "${HOME:-/root}/.claude/projects" -maxdepth 2 -name "${session}.jsonl" 2>/dev/null | head -1)"
  [ -n "$f" ] || { reason="transcript ${session}.jsonl not found under ~/.claude/projects"; return; }
  local files=("$f"); local subs; subs="$(dirname "$f")/${session}/subagents"
  [ -d "$subs" ] && while IFS= read -r s; do files+=("$s"); done < <(find "$subs" -name '*.jsonl' 2>/dev/null)
  local agg
  agg="$(cat "${files[@]}" | jq -c 'select(.type == "assistant" and .requestId != null) | {r: .requestId, m: .message.model, u: .message.usage}' 2>/dev/null \
    | jq -s '
      group_by(.r) | map(last)
      | { in: (map(.u.input_tokens // 0) | add // 0),
          out: (map(.u.output_tokens // 0) | add // 0),
          cr: (map(.u.cache_read_input_tokens // 0) | add // 0),
          cw: (map(.u.cache_creation_input_tokens // 0) | add // 0),
          cw5: (map(.u.cache_creation.ephemeral_5m_input_tokens // 0) | add // 0),
          cw1: (map(.u.cache_creation.ephemeral_1h_input_tokens // 0) | add // 0),
          models: (map(.m) | unique),
          per_model: (group_by(.m) | map({ (.[0].m): {
              in: (map(.u.input_tokens // 0) | add), out: (map(.u.output_tokens // 0) | add),
              cr: (map(.u.cache_read_input_tokens // 0) | add), cw: (map(.u.cache_creation_input_tokens // 0) | add),
              cw5: (map(.u.cache_creation.ephemeral_5m_input_tokens // 0) | add), cw1: (map(.u.cache_creation.ephemeral_1h_input_tokens // 0) | add) } }) | add // {})
        }' 2>/dev/null)"
  [ -n "$agg" ] || { reason="transcript unreadable"; return; }
  t_in="$(jq -r .in <<<"$agg")"; t_out="$(jq -r .out <<<"$agg")"; t_cr="$(jq -r .cr <<<"$agg")"; t_cw="$(jq -r .cw <<<"$agg")"
  local nm; nm="$(jq -r '.models | length' <<<"$agg")"
  if [ "$nm" -eq 1 ]; then model="anthropic/$(jq -r '.models[0]' <<<"$agg")"; elif [ "$nm" -gt 1 ]; then model="mixed"; fi
  turns="$(cat "${files[@]}" | jq -c 'select(.type == "user" and .origin.kind == "human")' 2>/dev/null | wc -l | tr -d ' ')"
  # Price per model from the synced table; a dated id matches its undated row.
  cost="$(jq -r --slurpfile p "$prices" '
    ($p[0].models) as $tbl
    | [ .per_model | to_entries[]
        | (.key | sub("-[0-9]{8}$"; "")) as $id
        | if ($tbl[$id] == null) then "unknown"
          else ((.value.in * $tbl[$id].input) + (.value.out * $tbl[$id].output) + (.value.cr * $tbl[$id].cache_read)
                + (if (.value.cw5 + .value.cw1) > 0 then (.value.cw5 * $tbl[$id].cache_write_5m + .value.cw1 * $tbl[$id].cache_write_1h)
                   else (.value.cw * $tbl[$id].cache_write_5m) end)) / 1000000 end ]
    | if any(. == "unknown") then "unknown" else (add // 0 | . * 10000 | round / 10000 | tostring) end' <<<"$agg")"
  source="transcript"
}

# --- OpenCode: the SQLite store -------------------------------------------------------------------------------

read_opencode() {
  local db="${OPENCODE_DB:-${XDG_DATA_HOME:-$HOME/.local/share}/opencode/opencode.db}"
  [ -f "$db" ] || { reason="opencode.db not found at $db"; return; }
  session="${OPENCODE_SESSION_ID:-}"
  local q
  if command -v python3 >/dev/null 2>&1; then
    q="$(OC_DB="$db" OC_SID="$session" OC_DIR="$repo_root" python3 - <<'PY'
import os, sqlite3, json
db, sid, d = os.environ["OC_DB"], os.environ["OC_SID"], os.environ["OC_DIR"]
c = sqlite3.connect("file:%s?mode=ro" % db, uri=True)
if not sid:
    r = c.execute("select id from session where directory = ? and parent_id is null order by time_created desc limit 1", (d,)).fetchone()
    if r is None:
        r = c.execute("select id from session where directory like ? and parent_id is null order by time_created desc limit 1", (d + "%",)).fetchone()
    if r is None: print("nosession"); raise SystemExit
    sid = r[0]; fallback = "fallback"
else: fallback = "plugin"
rows = c.execute("select id, cost, tokens_input, tokens_output, tokens_reasoning, tokens_cache_read, tokens_cache_write, model from session where id = ? or parent_id = ?", (sid, sid)).fetchall()
if not rows: print("nosession"); raise SystemExit
cost = sum(r[1] or 0 for r in rows); ti = sum((r[2] or 0) + (r[4] or 0) for r in rows); to = sum(r[3] or 0 for r in rows)
cr = sum(r[5] or 0 for r in rows); cw = sum(r[6] or 0 for r in rows)
models = set()
for r in rows:
    try:
        m = json.loads(r[7]) if r[7] else {}
        if m: models.add("%s/%s" % (m.get("providerID", "?"), m.get("id", "?")))
    except Exception: pass
turns = c.execute("select count(*) from message where session_id = ? and json_extract(data, '$.role') = 'user'", (sid,)).fetchone()[0]
model = list(models)[0] if len(models) == 1 else ("mixed" if models else "unknown")
print("\t".join([sid, fallback, str(ti), str(to), str(cr), str(cw), "%.4f" % cost, str(turns), model]))
PY
)" || q=""
  elif command -v sqlite3 >/dev/null 2>&1; then
    [ -n "$session" ] || session="$(sqlite3 -readonly "$db" "select id from session where directory = '$repo_root' and parent_id is null order by time_created desc limit 1;" 2>/dev/null)"
    [ -n "$session" ] || { q="nosession"; }
    if [ -z "${q:-}" ]; then
      q="$(sqlite3 -readonly -separator $'\t' "$db" "select '$session', 'sqlite3', sum(tokens_input+tokens_reasoning), sum(tokens_output), sum(tokens_cache_read), sum(tokens_cache_write), printf('%.4f', sum(cost)), (select count(*) from message where session_id='$session' and json_extract(data,'\$.role')='user'), coalesce((select json_extract(model,'\$.providerID')||'/'||json_extract(model,'\$.id') from session where id='$session'),'unknown') from session where id='$session' or parent_id='$session';" 2>/dev/null)"
    fi
  else
    reason="neither python3 nor sqlite3 to read opencode.db"; return
  fi
  [ -n "$q" ] && [ "$q" != "nosession" ] || { reason="no OpenCode session for this directory (install icm-session-env.js so OPENCODE_SESSION_ID is exported)"; return; }
  IFS=$'\t' read -r session _ t_in t_out t_cr t_cw cost turns model <<<"$q"
  source="sqlite"
}

case "$harness" in
  claude|claude-cloud) read_claude ;;
  opencode)            read_opencode ;;
  *)                   reason="no harness detected (neither CLAUDECODE/CLAUDE_CODE_SESSION_ID nor OPENCODE_SESSION_ID in the environment)" ;;
esac

line="- usage: $stage $mark $stamp harness=$harness session=${session:-none} source=$source model=$model in=$t_in out=$t_out cache_read=$t_cr cache_write=$t_cw cost_usd=$cost turns=$turns"
[ -f "$out" ] || printf '# Usage: %s\n\n' "$slug" > "$out"
printf '%s\n' "$line" >> "$out"
echo "$line"
if [ "$source" = "skip" ]; then echo "RESULT: SKIP ($reason)"; else echo "RESULT: RECORDED"; fi
exit 0
