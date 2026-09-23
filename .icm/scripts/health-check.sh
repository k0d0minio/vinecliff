#!/usr/bin/env bash
# health-check.sh — after the merge: is production ANSWERING? One bounded read, then a human decides. (TEMPLATE-OWNED)
#
# deploy-status.sh reads Vercel and says the merge commit's deployment is READY — the platform's
# word. This is the application's: one GET per health endpoint the repo declares, expecting 200,
# retried with exponential backoff (2s, then 4s — three attempts by default) because a fresh
# deployment can answer 502/503 for its first seconds while the old one drains. Release step 9(a)
# runs it right after deploy-status.sh and carries the one `- health:` line it prints into the stop
# message. It is one read at Release, bounded — decision D23 rejected a standing health-check
# workflow — so nothing here schedules, watches, re-runs later, un-merges or rolls back.
#
# Where the endpoints come from (`.icm/project.json`, read by lib/project.sh → health_endpoints):
#   health_endpoint                     a URL, or an array of URLs — the simple case
#   deploy.projects[].health_endpoint   one per deployed project, when they differ
# `--url <u>` (repeatable) overrides both. None declared → `RESULT: SKIP`, exit 0: a fact about the
# repo, not a fault (setup.sh asks for it).
#
# When an endpoint fails — no 200 after the last attempt — three things happen, all of them
# preparation, none of them a recovery:
#   1. The alert.  `.icm/scripts/report.sh alert "<what failed>" --url <endpoint>` — the repo's own
#      channels (`reporting.alert`; the seeded default maps to none, and report.sh prints SKIPPED —
#      that is the repo's decision, not this script's). The message names the merge SHA and the
#      recovery `rollback.sh` prepares. `--no-alert` skips the call.
#   2. The ticket.  One triage stub, `.icm/intake/triage/health-check-<date>-<short-sha>.md`, in the
#      triage shape (`intake/CONTEXT.md` → Triage): `lane: bug`, `found-by: health-check · <date>`,
#      `complexity: high`, the endpoint, the code each attempt saw, the merge SHA, and the two
#      recoveries by name. WRITTEN, NEVER COMMITTED: the stage names it in its stop message and the
#      operator decides — commit it for the bug lane, or open `/pipeline hotfix` by hand and let that
#      lane consume it. One stub per merge SHA: a re-run writes nothing and names the one that
#      exists. `--no-stub` skips it. It parks a stub for the BUG lane; nothing parks a stub for the
#      hotfix lane, which a human opens (`lanes/hotfix/CONTEXT.md`).
#   3. The verdict.  `RESULT: FAIL <endpoint…>`, exit 3 — the exit deploy-status.sh uses for ERROR, so
#      a stage reads the two alike.
#
# A health endpoint is public by definition, so no token is involved. A repo whose endpoint wants a
# header names a variable that holds the whole header line (`--header-env HEALTH_CHECK_HEADER`, the
# variable reading `X-Health-Key: …`): the value comes from the environment and reaches curl on stdin,
# never argv, never a file in git.
#
# Usage: .icm/scripts/health-check.sh [--sha <merge-sha>] [--url <endpoint>]... [--attempts <n>]
#          [--expect <code>] [--timeout <seconds>] [--backoff <seconds>] [--header-env <VAR>]...
#          [--no-alert] [--no-stub] [--dry-run]
# Verdict (stdout, last line):
#   RESULT: OK                 exit 0  — every endpoint answered <expect> (200) within the attempts
#   RESULT: FAIL <endpoint…>   exit 3  — at least one did not; the alert and the stub are described above
#   RESULT: SKIP               exit 0  — no health endpoint declared and none passed
#   RESULT: DRY-RUN            exit 0  — the endpoints and the attempt plan printed; nothing requested
set -euo pipefail

command -v curl >/dev/null 2>&1 || { echo "curl not found" >&2; exit 1; }
command -v jq   >/dev/null 2>&1 || { echo "jq not found"   >&2; exit 1; }

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$repo_root"
die() { echo "error: $*" >&2; exit 1; }

sha=""; attempts=3; expect=200; timeout=10; backoff=2; alert=1; stub=1; dry=0
declare -a urls=() header_envs=()
while [ $# -gt 0 ]; do
  case "$1" in
    --sha)        sha="${2:-}"; shift 2 ;;
    --url)        [ -n "${2:-}" ] || die "--url needs an endpoint"; urls+=("$2"); shift 2 ;;
    --attempts)   attempts="${2:-}"; shift 2 ;;
    --expect)     expect="${2:-}"; shift 2 ;;
    --timeout)    timeout="${2:-}"; shift 2 ;;
    --backoff)    backoff="${2:-}"; shift 2 ;;
    --header-env) [ -n "${2:-}" ] || die "--header-env needs a variable NAME"; header_envs+=("$2"); shift 2 ;;
    --no-alert)   alert=0; shift ;;
    --no-stub)    stub=0; shift ;;
    --dry-run)    dry=1; shift ;;
    -h|--help)    sed -n '2,45p' "${BASH_SOURCE[0]}"; exit 0 ;;
    *)            die "unknown argument: $1 (usage: health-check.sh [--sha <sha>] [--url <u>]... [--attempts n] [--expect code] [--timeout s] [--backoff s] [--header-env VAR]... [--no-alert] [--no-stub] [--dry-run])" ;;
  esac
done
case "$attempts" in ''|*[!0-9]*|0) die "--attempts must be a whole number, at least 1" ;; esac
case "$expect"   in [1-5][0-9][0-9]) : ;; *) die "--expect must be a three-digit HTTP status" ;; esac
case "$timeout"  in ''|*[!0-9]*|0) die "--timeout must be a whole number of seconds" ;; esac
case "$backoff"  in ''|*[!0-9]*) die "--backoff must be a whole number of seconds" ;; esac

# shellcheck source=lib/project.sh
source "$here/lib/project.sh"

if [ "${#urls[@]}" -eq 0 ]; then mapfile -t urls < <(health_endpoints); fi
if [ "${#urls[@]}" -eq 0 ]; then
  echo "health: not declared (no health_endpoint in .icm/project.json — setup.sh asks for it)"
  echo "- health: SKIP — no health endpoint declared"
  echo "RESULT: SKIP"; exit 0
fi
for u in "${urls[@]}"; do
  case "$u" in http://*|https://*) : ;; *) die "not an http(s) URL: $u" ;; esac
done

[ -n "$sha" ] || sha="$(git -C "$repo_root" rev-parse HEAD 2>/dev/null || true)"
short="${sha:0:7}"
name="$(project_field .name "$(basename "$repo_root")")"
today="$(date -u +%F)"
now="$(date -u +%FT%TZ)"

# The header lines, resolved from the environment once; a named variable that is unset is a die,
# before any request — a probe sent without the header it needs would fail for the wrong reason.
declare -a headers=()
for v in "${header_envs[@]}"; do
  [ -n "${!v:-}" ] || die "--header-env $v: the variable is unset in this environment"
  headers+=("${!v}")
done

# One GET. Prints "<http_code> <seconds>"; the code is 000 when curl itself failed (DNS, timeout,
# refused). curl reads its configuration on stdin so a header value never appears in argv.
probe() {
  local url="$1" cfg out h
  cfg="url = \"$url\"\nlocation\nmax-redirs = 5\nmax-time = $timeout\nsilent\noutput = /dev/null\nuser-agent = \"icm-health-check\"\nwrite-out = \"%{http_code} %{time_total}\"\n"
  for h in "${headers[@]}"; do cfg+="header = \"${h//\"/\\\"}\"\n"; done
  out="$(printf '%b' "$cfg" | curl --config - 2>/dev/null || true)"
  case "${out%% *}" in [0-9][0-9][0-9]) printf '%s' "$out" ;; *) printf '000 0' ;; esac
}

declare -a failed=() record=()
declare -A codes_of=()

for url in "${urls[@]}"; do
  ok=0; i=1; seen=""
  while [ "$i" -le "$attempts" ]; do
    if [ "$dry" -eq 1 ]; then
      echo "  would GET $url — attempt $i/$attempts, expect $expect, timeout ${timeout}s$( [ "$i" -lt "$attempts" ] && echo ", then wait $(( backoff * (1 << (i - 1)) ))s" )"
      i=$((i + 1)); continue
    fi
    out="$(probe "$url")"; code="${out%% *}"; secs="${out#* }"
    seen="${seen:+$seen,}$code"
    if [ "$code" = "$expect" ]; then
      echo "  $url → $code (${secs}s) on attempt $i/$attempts"; ok=1; break
    fi
    if [ "$i" -lt "$attempts" ]; then
      wait=$(( backoff * (1 << (i - 1)) ))
      echo "  $url → $code (${secs}s) on attempt $i/$attempts — expected $expect; retry in ${wait}s"
      sleep "$wait"
    else
      echo "  $url → $code (${secs}s) on attempt $i/$attempts — expected $expect; giving up"
    fi
    i=$((i + 1))
  done
  [ "$dry" -eq 0 ] || continue
  codes_of["$url"]="$seen"
  if [ "$ok" -eq 1 ]; then record+=("$url $code")
  else failed+=("$url"); record+=("$url FAIL ($seen)"); fi
done

if [ "$dry" -eq 1 ]; then
  echo "- health: DRY-RUN on ${short:-<no sha>} — ${#urls[@]} endpoint(s), $attempts attempt(s) each, nothing requested"
  echo "RESULT: DRY-RUN"; exit 0
fi

# --- the record line Release copies -----------------------------------------------------------------------------
join() { local IFS="$1"; shift; printf '%s' "$*"; }

if [ "${#failed[@]}" -eq 0 ]; then
  echo "- health: OK on ${short:-<no sha>} — $(join '·' "${record[@]}" | sed 's/·/ · /g')"
  echo "RESULT: OK"; exit 0
fi

# --- a failure: the alert, the ticket — preparation only --------------------------------------------------------
summary="$name: production health check failed after merge ${short:-<unknown>} — $(join ';' "${failed[@]}" | sed 's/;/; /g') answered $(for u in "${failed[@]}"; do printf '%s ' "${codes_of[$u]}"; done | sed 's/ $//') (expected $expect, $attempts attempts). Recovery: .icm/scripts/rollback.sh --sha ${sha:-<merge-sha>} --vercel names the previous READY deployment; --revert prepares the revert PR."
alert_line="not sent (--no-alert)"
if [ "$alert" -eq 1 ]; then
  if [ -x "$here/report.sh" ]; then
    echo "alert → report.sh alert:"
    out="$("$here/report.sh" alert "$summary" --url "${failed[0]}" 2>&1 || true)"
    printf '%s\n' "$out" | sed 's/^/  /'
    alert_line="$(printf '%s\n' "$out" | tail -n1 | sed 's/^RESULT: //')"
  else
    echo "  [WARN] .icm/scripts/report.sh missing (project-owned; setup.sh --fix seeds it) — no alert sent"
    alert_line="not sent (report.sh missing)"
  fi
fi

stub_line="not written (--no-stub)"
if [ "$stub" -eq 1 ]; then
  triage=".icm/intake/triage"
  key="${short:-unknown}"
  existing="$(find "$triage" -maxdepth 2 -name "health-check-*-${key}.md" 2>/dev/null | sort | head -n1 || true)"
  if [ -n "$existing" ]; then
    echo "stub already parked for ${key}: $existing — nothing written"
    stub_line="$existing (already parked)"
  else
    mkdir -p "$triage"
    stub_path="$triage/health-check-${today}-${key}.md"
    first_host="$(printf '%s' "${failed[0]}" | sed -E 's#^https?://([^/]+).*#\1#')"
    {
      echo "# Stub: Production health check failed after ${key} — ${first_host}"
      echo
      echo "- lane: bug"
      echo "- found-by: health-check · $today"
      echo "- complexity: high"
      echo
      echo "## Problem"
      echo
      echo "After merge \`${sha:-<unknown>}\` ($now), production did not answer as the repo expects ($expect, $attempts attempts, backoff ${backoff}s):"
      echo
      for u in "${failed[@]}"; do echo "- \`$u\` → ${codes_of[$u]}"; done
      echo
      echo "The alert went through \`report.sh alert\`: $alert_line."
      echo
      echo "## Proposed change"
      echo
      echo "Investigate — a human chooses the recovery, this stub chooses nothing. Production down →"
      echo "\`/pipeline hotfix \"<what is wrong>\"\`: \`.icm/scripts/rollback.sh --sha ${sha:-<merge-sha>} --vercel\` names"
      echo "the previous READY deployment (the operator runs the call), \`--revert\` prepares the revert PR."
      echo "A slow start → re-run \`.icm/scripts/health-check.sh --sha ${sha:-<merge-sha>}\` and, on OK, retire this"
      echo "stub to \`_done/\` with a \`- superseded-by:\` line."
    } > "$stub_path"
    echo "parked $stub_path — written, not committed: the operator commits it for the bug lane, or opens /pipeline hotfix"
    stub_line="$stub_path"
    active="$(find "$triage" -maxdepth 1 -name '*.md' 2>/dev/null | wc -l | tr -d ' ')"
    [ "${active:-0}" -le 60 ] || echo "triage/ holds $active active stubs (cap 60) — run triage report"
  fi
fi

echo "Nothing was rolled back, promoted or re-deployed — the recovery is the operator's (rollback.sh prepares it)."
echo "- health: FAIL on ${short:-<no sha>} — $(join '·' "${record[@]}" | sed 's/·/ · /g') — alert: $alert_line · stub: $stub_line"
echo "RESULT: FAIL $(join ' ' "${failed[@]}")"
exit 3
