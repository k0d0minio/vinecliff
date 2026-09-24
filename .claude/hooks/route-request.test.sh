#!/usr/bin/env bash
# route-request.test.sh — feeds sample prompts through route-request.sh and asserts the hint.
#
# Plain bash, no framework, NOT a repo check (nothing in CI runs it; the block-local-checks hook
# does not match it). Run it after editing the router:
#
#   .claude/hooks/route-request.test.sh
#
# It builds a throwaway project tree (one run, one archived run, one intake stub, one triage stub)
# and points the hook at it via CLAUDE_PROJECT_DIR, so the assertions never depend on what is in
# .icm/runs/ or .icm/intake/ today. Exit 0 when every case passes, 1 otherwise.
set -uo pipefail

hook="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/route-request.sh"
fixture="$(mktemp -d)"
trap 'rm -rf "$fixture"' EXIT

mkdir -p "$fixture/.icm/runs/vendor-funnel-graph" \
         "$fixture/apps/docs/archive/pipeline-runs/csv-export" \
         "$fixture/.icm/intake/preview-visual-smoke/_done" \
         "$fixture/.icm/intake/triage/_done"
mkdir -p "$fixture/.claude/skills/pipeline"; printf '# Pipeline\n' > "$fixture/.claude/skills/pipeline/SKILL.md"
printf '{"runs_archive": "apps/docs/archive/pipeline-runs"}\n' > "$fixture/.icm/project.json"
printf '# Run: vendor-funnel-graph\n\n- lane: feature\n' > "$fixture/.icm/runs/vendor-funnel-graph/run.md"
printf '# Stub\n' > "$fixture/.icm/intake/preview-visual-smoke/smoke-visual-verdict.md"
printf '# Stub\n' > "$fixture/.icm/intake/preview-visual-smoke/_done/spun-out-stub.md"
printf '# Triage\n' > "$fixture/.icm/intake/triage/stale-flag.md"
printf '# Triage\n' > "$fixture/.icm/intake/triage/_done/old-finding.md"
export CLAUDE_PROJECT_DIR="$fixture"

pass=0; fail=0

# run <prompt> → sets $out (the additionalContext text, or "") and $code (exit status).
run() {
  local raw
  raw="$(jq -cn --arg p "$1" '{prompt:$p}' | bash "$hook" 2>/dev/null)"; code=$?
  if [ -n "$raw" ]; then
    out="$(printf '%s' "$raw" | jq -r '.hookSpecificOutput.additionalContext // "<<not hook json>>"' 2>/dev/null || printf '<<invalid json>>')"
  else
    out=""
  fi
}

# expect <label> <prompt> <expected substring, or SILENT>
expect() {
  local label="$1" prompt="$2" want="$3"
  run "$prompt"
  local ok=1
  [ "$code" -eq 0 ] || ok=0
  if [ "$want" = "SILENT" ]; then
    [ -z "$out" ] || ok=0
  else
    case "$out" in *"$want"*) ;; *) ok=0 ;; esac
  fi
  if [ "$ok" -eq 1 ]; then
    pass=$((pass + 1)); printf 'PASS  %s\n' "$label"
  else
    fail=$((fail + 1))
    printf 'FAIL  %s\n      prompt:   %s\n      expected: %s\n      got:      %s (exit %s)\n' \
      "$label" "$prompt" "$want" "${out:-<silent>}" "$code"
  fi
}

# --- layer 1: bare stage forms ------------------------------------------------------------------
expect "bare new"                    "new"                                 "Route: /pipeline new (bare new"
expect "bare new, capitalised + dot" "New."                                "Route: /pipeline new (bare new"
expect "build <run slug>"            "build vendor-funnel-graph"           "Route: /pipeline build vendor-funnel-graph (run found in .icm/runs/"
expect "release <run slug>"          "release vendor-funnel-graph"         "Route: /pipeline release vendor-funnel-graph (run found"
expect "revise <run slug>"           "revise vendor-funnel-graph"          "Route: /pipeline revise vendor-funnel-graph (run found"
expect "revise <slug> \"<change>\""       "revise vendor-funnel-graph \"drop the totals row criterion\"" "Route: /pipeline revise vendor-funnel-graph (run found"
expect "build <slug> <text> is not a form" "build vendor-funnel-graph \"now\""  "names existing pipeline work (run found in .icm/runs/vendor-funnel-graph/)"
expect "retired define verb is not a form" "define vendor-funnel-graph"        "names existing pipeline work (run found in .icm/runs/vendor-funnel-graph/)"
expect "build <archived slug>"       "build csv-export"                    "Route: /pipeline build csv-export (archived run"
expect "new <stub name>"             "new smoke-visual-verdict"            "Route: /pipeline new smoke-visual-verdict (intake stub .icm/intake/preview-visual-smoke/smoke-visual-verdict.md"
expect "new ignores triage stubs"    "new stale-flag"                      "Route: /pipeline new stale-flag (no stub with that exact name"
expect "new ignores _done stubs"     "new spun-out-stub"                   "Route: /pipeline new spun-out-stub (no stub with that exact name"
expect "bug <triage stub>"           "bug stale-flag"                      "Route: /pipeline bug stale-flag (triage stub .icm/intake/triage/stale-flag.md"
expect "tweak <triage stub>"         "tweak stale-flag"                    "Route: /pipeline tweak stale-flag (triage stub"
expect "chore <run slug> is not a resume" "chore vendor-funnel-graph"      "lanes are not resumed"
expect "bug <archived slug> is not a resume" "bug csv-export"              "lanes are not resumed"
expect "bug <_done triage stub> is not a stub" "bug old-finding"           "no triage stub with that exact name"
expect "bug <name not in triage>"    "bug fix-login-loop"                  "Route: /pipeline bug fix-login-loop (no triage stub with that exact name"
expect "bug \"<report>\" is a fresh report" "bug \"the export button crashes on an empty list\"" "Route: /pipeline bug \"<the text after 'bug'>\" (explicit lane verb with a fresh report"
expect "tweak <free text> is a fresh report" "tweak the padding on the invoice header" "Route: /pipeline tweak \"<the text after 'tweak'>\""
expect "bare lane verb is silent"    "chore"                               "SILENT"
expect "build <slug not in tree>"    "build lead-intake-hardening"         "Route: /pipeline build lead-intake-hardening (no run or stub named"
expect "build <plain word> is silent" "build faster"                       "SILENT"
expect "scope <input>"               "scope Vendors should see a funnel graph on their dashboard" "Route: /pipeline scope"
expect "explicit /pipeline untouched" "/pipeline build vendor-funnel-graph" "SILENT"
expect "bare triage lists the verbs" "triage"                              "Route: /pipeline triage (bare triage"
expect "triage report"               "triage report"                       "Route: /pipeline triage report (runs .icm/scripts/triage-report.sh"
expect "triage report, capitalised + dot" "Triage report."                 "Route: /pipeline triage report"
expect "triage prune"                "triage prune"                        "Route: /pipeline triage prune (lists stubs older than 30 days"
expect "triage batch <area> \"<title>\"" "triage batch apps/web \"Web warts from the dashboard runs\"" "Route: /pipeline triage batch <the selector and title after 'triage batch'>"
expect "triage batch <lane> \"<title>\"" "triage batch chore \"Pipeline tooling debt\"" "Route: /pipeline triage batch"
expect "triage report <text> is not a form" "triage report on the backlog please" "SILENT"
expect "triage <free text> is silent"  "triage the backlog"                "SILENT"
expect "explicit /pipeline triage untouched" "/pipeline triage report"    "SILENT"
expect "bare knowledge lists the verbs" "knowledge"                        "Route: /pipeline knowledge (bare knowledge"
expect "knowledge add \"<what>\""     "knowledge add \"the 2026-Q3 OKR page under business/okrs\"" "Route: /pipeline knowledge add \"<the request after 'knowledge add'>\" (knowledge lane"
expect "knowledge edit <free text>"    "knowledge edit the roles page: the SDM now owns escalations" "Route: /pipeline knowledge edit \"<the request after 'knowledge edit'>\""
expect "knowledge remove, capitalised + dot" "Knowledge remove the cache-tags page." "Route: /pipeline knowledge remove"
expect "knowledge <verb> with no request is silent" "knowledge edit"       "SILENT"
expect "knowledge <other verb> lists the forms" "knowledge update the roles page" "Route: /pipeline knowledge (unknown verb 'update'"
expect "explicit /pipeline knowledge untouched" "/pipeline knowledge edit the roles page" "SILENT"

# --- silences -----------------------------------------------------------------------------------
expect "short conversational"        "hi there"                            "SILENT"
expect "question opener"             "Why does the invoice page load slowly?" "SILENT"
expect "analysis verb"               "Please review the auth middleware for gaps" "SILENT"
expect "webhook payload"             "<github-webhook-activity>{\"action\":\"opened\"}</github-webhook-activity> fix the build" "SILENT"

# --- layer 2: lane classifiers (advisory) -------------------------------------------------------
expect "bug report"                  "The export button crashes when the list is empty" "Suggest: /pipeline bug"
expect "tweak"                       "Fix the typo on the invoice header"  "Suggest: /pipeline tweak"
expect "chore"                       "Refactor the lead service to drop the unused helper" "Suggest: /pipeline chore"

# --- layer 3: new content → Scope ----------------------------------------------------------------
expect "new content → scope"         "Vendors should be able to see a funnel graph of their leads on the dashboard" "Route: /pipeline scope \"<the request>\" (new content"
expect "names an existing run"       "Add a totals row to vendor-funnel-graph before we ship it" "names existing pipeline work (run found in .icm/runs/vendor-funnel-graph/)"
expect "names a triage stub"         "We should add the stale-flag fix to this sprint" "names existing pipeline work (triage stub"
dump="$(printf 'We need the vendor area reworked:\n- funnel graph\n- lead export\n- bid history\n- SLA badges\n- invoice list\n- CSAT widget\n')"
expect "multi-feature dump → scope"  "$dump"                               "Route: /pipeline scope \"<the story>\" (multi-feature dump"

# --- robustness ----------------------------------------------------------------------------------
raw="$(printf 'not json at all' | bash "$hook" 2>/dev/null)"; code=$?
if [ "$code" -eq 0 ] && [ -z "$raw" ]; then pass=$((pass + 1)); printf 'PASS  malformed input is silent and exits 0\n'
else fail=$((fail + 1)); printf 'FAIL  malformed input: exit %s, output %s\n' "$code" "${raw:-<silent>}"; fi

printf '\n%s passed, %s failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
