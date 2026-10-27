#!/usr/bin/env bash
# route-request.test.sh — feeds sample prompts through route-request.sh and asserts the line.
#
# Plain bash, no framework. check.yml in the blueprint runs it in each rendered build. Run it
# after editing the router:
#
#   bash .claude/hooks/route-request.test.sh
#
# It builds three throwaway trees and points the hook at each via CLAUDE_PROJECT_DIR, so the
# assertions never depend on what is in .icm/intake/ today:
#   - the main tree: intake/CONTEXT.md, README.md with § Order, two open epics with a breakdown,
#     one epic outside the order, one stub in an epic's _done/, one open triage stub, one triage
#     stub in triage/_done/, one closed epic, and one slug in two epics,
#   - the same tree with .icm/uat/CONTEXT.md, for the UAT forms,
#   - a tree without .icm/intake/CONTEXT.md, where the hook is silent.
# Each hook call must take less than 100 ms. Exit 0 when every case passes, 1 otherwise.
set -uo pipefail

hook="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/route-request.sh"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

main="$tmp/main"; uat="$tmp/uat"; bare="$tmp/bare"
i="$main/.icm/intake"
mkdir -p "$i/zz-epic/_done" "$i/zz-later/_done" "$i/zz-other" "$i/triage/_done" \
         "$i/_done/zz-shipped/_done" "$bare/.icm"
printf '# Intake\n' > "$i/CONTEXT.md"
printf '# Intake\n\n## Order\n\nSet by Jamie on 2026-10-27.\n\n1. triage\n2. zz-later\n3. `zz-epic`\n\n## Other\n\n1. zz-other\n' > "$i/README.md"
stub() {  # stub <path> <priority> [<sequence>]
  { printf '# Stub: %s\n\n' "$(basename "$1" .md)"
    [ -n "${3:-}" ] && printf -- '- sequence: %s of 9\n' "$3"
    printf -- '- priority: %s\n' "$2"; } > "$1"
}
printf '# Breakdown\n' > "$i/zz-epic/breakdown.md"
printf '# Breakdown\n' > "$i/zz-later/breakdown.md"
stub "$i/zz-epic/funnel-graph.md" P2 1
stub "$i/zz-epic/export-csv.md" P1 2
stub "$i/zz-epic/shared-name.md" P2 9
stub "$i/zz-epic/_done/lead-intake.md" P1 3
stub "$i/zz-later/bid-history.md" P1 1
stub "$i/zz-later/audit-log.md" P0 3
stub "$i/zz-later/shared-name.md" P2 9
stub "$i/zz-other/alpha-thing.md" P2 1
printf '# Stub: stale flag\n\n- lane: bug\n- priority: P1\n' > "$i/triage/stale-flag.md"
printf '# Stub: old finding\n\n- lane: chore\n- priority: P2\n' > "$i/triage/_done/old-finding.md"
stub "$i/_done/zz-shipped/_done/csv-import.md" P1 1
cp -R "$main" "$uat"
mkdir -p "$uat/.icm/uat"; printf '# UAT\n' > "$uat/.icm/uat/CONTEXT.md"

pass=0; fail=0; slowest=0; slowest_label=""

# run <prompt> → sets $out (the additionalContext text, or ""), $code (exit status), $ms.
run() {
  local payload raw t0 t1 lines
  payload="$(jq -cn --arg p "$1" '{prompt:$p}')"
  t0="$(date +%s%N)"
  raw="$(printf '%s' "$payload" | bash "$hook" 2>/dev/null)"; code=$?
  t1="$(date +%s%N)"
  ms=$(( (t1 - t0) / 1000000 ))
  out=""
  [ -n "$raw" ] || return 0
  lines="$(printf '%s\n' "$raw" | wc -l)"
  if [ "$lines" -ne 1 ]; then out="<<${lines} lines>>"; return 0; fi
  out="$(printf '%s' "$raw" | jq -r 'if .hookSpecificOutput.hookEventName == "UserPromptSubmit"
    then .hookSpecificOutput.additionalContext // "<<no context>>" else "<<not hook json>>" end' \
    2>/dev/null || printf '<<invalid json>>')"
}

# expect <label> <prompt> <expected substring, or SILENT>
expect() {
  local label="$1" prompt="$2" want="$3" ok=1
  run "$prompt"
  [ "$code" -eq 0 ] || ok=0
  [ "$ms" -lt 100 ] || ok=0
  if [ "$ms" -gt "$slowest" ]; then slowest="$ms"; slowest_label="$label"; fi
  if [ "$want" = "SILENT" ]; then
    [ -z "$out" ] || ok=0
  else
    case "$out" in "[router] "*"$want"*) ;; *) ok=0 ;; esac
  fi
  if [ "$ok" -eq 1 ]; then
    pass=$((pass + 1)); printf 'PASS  %s\n' "$label"
  else
    fail=$((fail + 1))
    printf 'FAIL  %s\n      prompt:   %s\n      expected: %s\n      got:      %s (exit %s, %s ms)\n' \
      "$label" "$prompt" "$want" "${out:-<silent>}" "$code" "$ms"
  fi
}

export CLAUDE_PROJECT_DIR="$main"
L=".icm/intake/CONTEXT.md"

# --- the line ------------------------------------------------------------------------------------
expect "a Route: line has the tail"   "new"                "The user's own prompt overrides it."
expect "a Suggest: line has the tail" "The export button crashes when the list is empty" "A Suggest: line is advisory."

# --- layer 1: new --------------------------------------------------------------------------------
expect "bare new"                     "new"                "Route: $L § The loop, step 1"
expect "bare new, capitalised + dot"  "New."               "Route: $L § The loop, step 1"
expect "new <open stub>"              "new funnel-graph"   "Route: read the stub .icm/intake/zz-epic/funnel-graph.md, then run .icm/scripts/new-run.sh zz-epic/funnel-graph"
expect "new <epic>/<slug>"            "new zz-epic/funnel-graph" "run .icm/scripts/new-run.sh zz-epic/funnel-graph"
expect "new <triage stub> takes its lane" "new stale-flag" "the open triage stub .icm/intake/triage/stale-flag.md. Read .icm/lanes/bug/CONTEXT.md"
expect "new <_done stub> resumes"     "new lead-intake"    "is started. Resume at $L § The loop, step 0, on the branch lead-intake"
expect "new <closed epic stub>"       "new csv-import"     "is in a closed epic: it shipped"
expect "new <slug in two epics>"      "new shared-name"    "two or more stubs carry the slug shared-name: .icm/intake/zz-epic/shared-name.md, .icm/intake/zz-later/shared-name.md"
expect "new <epic>/<slug> of a shared slug" "new zz-later/shared-name" "read the stub .icm/intake/zz-later/shared-name.md"
expect "new <not found> lists 5, P0 then the order" "new nothing-here" \
  "(5 of 8): zz-later/audit-log (P0), triage/stale-flag, zz-later/bid-history, zz-later/shared-name, zz-epic/funnel-graph. Ask which one."
expect "new breakdown is not a slug"  "new breakdown"      "SILENT"
expect "new <plain word> is silent"   "new faster"         "SILENT"

# --- layer 1: build, revise, merge, release ------------------------------------------------------
expect "build <_done stub>"           "build lead-intake"  "resume at $L § The loop, step 0, on the branch lead-intake"
expect "build <open stub>"            "build funnel-graph" "on the branch funnel-graph"
expect "build <_done triage stub>"    "build old-finding"  "on the branch triage/old-finding"
expect "build <closed epic stub>"     "build csv-import"   "it shipped. Change nothing"
expect "build <slug not in tree>"     "build zz-fix-on-branch" "no stub named zz-fix-on-branch in this checkout"
expect "build <plain word> is silent" "build faster"       "SILENT"
expect "build <slug> <text> is not a form" "build lead-intake now" "Suggest: this prompt names existing work (started: .icm/intake/zz-epic/_done/lead-intake.md)"
expect "revise <slug>"                "revise lead-intake" "$L § Revise, with the change after the slug, on the branch lead-intake"
expect "revise <slug> \"<change>\""   "revise lead-intake \"drop the totals row criterion\"" "§ Revise, with the change after the slug"
expect "merge <number>"               "merge 42"           "Route: run .icm/scripts/merge.sh 42 ($L § The loop, step 7)"
expect "merge <slug>"                 "merge lead-intake"  "gh pr view lead-intake --json number, then run .icm/scripts/merge.sh <number>"
expect "merge <triage slug>"          "merge old-finding"  "gh pr view triage/old-finding --json number"
expect "merge <closed epic stub>"     "merge csv-import"   "Merge nothing"
expect "merge <slug not in tree>"     "merge zz-fix-on-branch" "no stub named zz-fix-on-branch in this checkout"
expect "release"                      "release"            "Route: run .icm/scripts/release.sh ($L § After the tick). The merge makes the tag and the changelog"
expect "release <text> is not a form" "release lead-intake" "Suggest: this prompt names existing work"

# --- layer 1: lanes ------------------------------------------------------------------------------
expect "bug <triage stub>"            "bug stale-flag"     "Route: .icm/lanes/bug/CONTEXT.md with the open triage stub .icm/intake/triage/stale-flag.md. Run .icm/scripts/new-run.sh triage/stale-flag"
expect "tweak <triage stub>"          "tweak stale-flag"   "Route: .icm/lanes/tweak/CONTEXT.md with the open triage stub"
expect "chore <_done triage stub> resumes" "chore old-finding" "is started. Resume at $L § The loop, step 0, on the branch triage/old-finding"
expect "bug <epic stub> asks"         "bug funnel-graph"   "is not an open triage stub. Ask: a fresh report, or a mistyped name"
expect "bug <name not found> asks"    "bug fix-login-loop" "no triage stub named fix-login-loop. Ask: a fresh report"
expect "bug \"<report>\" is a fresh report" "bug \"the export button crashes on an empty list\"" "Route: .icm/lanes/bug/CONTEXT.md with a fresh report"
expect "tweak <free text> is a fresh report" "tweak the padding on the invoice header" "Route: .icm/lanes/tweak/CONTEXT.md with a fresh report"
expect "bare lane verb is silent"     "chore"              "SILENT"
expect "hotfix <triage stub>"         "hotfix stale-flag"  "Route: .icm/lanes/hotfix/CONTEXT.md with the open triage stub .icm/intake/triage/stale-flag.md. Run .icm/scripts/new-run.sh triage/stale-flag --ready"
expect "hotfix <text>"                "hotfix checkout returns a 500 for every order" "Route: .icm/lanes/hotfix/CONTEXT.md with a fresh report"
expect "bare hotfix is silent"        "hotfix"             "SILENT"

# --- layer 1: plan, scope, promote ---------------------------------------------------------------
expect "plan <text>"                  "plan Vendors see a funnel graph" "Route: $L § A request with no stub, case 2: cut an epic"
expect "scope <text>"                 "scope Vendors should see a funnel graph on their dashboard" "Route: $L § A request with no stub, case 2: cut an epic"
expect "bare plan is silent"          "plan"               "SILENT"
expect "promote without UAT"          "promote"            "this build has no .icm/uat/CONTEXT.md"
expect "promote status without UAT"   "promote status"     "this build has no .icm/uat/CONTEXT.md"
expect "explicit /command untouched"  "/build lead-intake" "SILENT"

export CLAUDE_PROJECT_DIR="$uat"
expect "release with UAT"             "release"            "This build has UAT: the merge makes the tag and moves nothing"
expect "bare promote with UAT"        "promote"            "promote.sh status, then .icm/scripts/promote.sh run --tag <the tag that status names>"
expect "promote status"               "promote status"     "Route: .icm/uat/CONTEXT.md: run .icm/scripts/promote.sh status."
expect "promote approve <who>"        "promote approve Maria" "promote.sh approve --by \"<the name after 'approve'>\""
expect "promote approve, no name"     "promote approve"    "ask who approved"
expect "promote run <tag>"            "promote run v1.2.0" "promote.sh run --tag <the tag after 'run'>"
expect "promote run, no tag"          "promote run"        "promote.sh status, then .icm/scripts/promote.sh run --tag"
expect "promote <unknown verb>"       "promote ship it"    "promote has three verbs"
export CLAUDE_PROJECT_DIR="$main"

# --- silences ------------------------------------------------------------------------------------
expect "short conversational"         "hi there"           "SILENT"
expect "question opener"              "Why does the invoice page load slowly?" "SILENT"
expect "question opener: did"         "Did the export change in the last release" "SILENT"
expect "one-line question, no work verb" "The totals look odd today, any idea?" "SILENT"
expect "analysis verb"                "Please review the auth middleware for gaps" "SILENT"
expect "audit request"                "Audit the CI config and the tooling for the migration" "SILENT"
expect "webhook payload"              "<github-webhook-activity>{\"action\":\"opened\"}</github-webhook-activity> fix the build" "SILENT"
expect "task notification"            "<task-notification>build lead-intake finished, add the totals</task-notification>" "SILENT"
expect "ci monitor event"             "<ci-monitor-event>check failed on lint, fix the build</ci-monitor-event>" "SILENT"
expect "side sessions event"          "<side-sessions-event>the session added the export page</side-sessions-event>" "SILENT"
skill_body="$(printf -- '---\nname: security-review\ndescription: Perform a security review of the codebase.\n---\n\n# Security review\n\nAdd checks for the following:\n- SQL injection\n- XSS\n- CSRF\n- secrets in logs\n- dependency vulnerabilities\n- authentication bypass\n')"
expect "skill body frontmatter is silent" "$skill_body"    "SILENT"
skill_body_leading_blank="$(printf '\n\n---\nname: pr-conventions\ndescription: x\n---\nAdd, build and implement the change.\n')"
expect "skill body, leading blank lines" "$skill_body_leading_blank" "SILENT"
desk="In legible-consulting/zz-proof, read .icm/intake/CONTEXT.md, then run .icm/scripts/new-run.sh zz-epic/funnel-graph and build the stub .icm/intake/zz-epic/funnel-graph.md as the loop says. Stop at the first gate. Your last message names the pull request and what waits on Jamie."
expect "the desk's start prompt"      "$desk"              "SILENT"
expect "a prompt with new-run.sh"     "Run new-run.sh triage/stale-flag --ready and add the fix" "SILENT"

# --- layer 2: lane classifiers (advisory) --------------------------------------------------------
expect "bug report"                   "The export button crashes when the list is empty" "Suggest: .icm/lanes/bug/CONTEXT.md"
expect "tweak"                        "Fix the typo on the invoice header" "Suggest: .icm/lanes/tweak/CONTEXT.md"
expect "chore"                        "Refactor the lead service to drop the unused helper" "Suggest: .icm/lanes/chore/CONTEXT.md"

# --- layer 3: new content ------------------------------------------------------------------------
expect "new content → the stub first" "Vendors should be able to see a funnel graph of their leads on the dashboard" "Route: $L § A request with no stub: write the stub first"
expect "names an open stub"           "Add a totals row to funnel-graph before we ship it" "names existing work (open: .icm/intake/zz-epic/funnel-graph.md)"
expect "names a triage stub"          "We should add the stale-flag fix to this sprint" "names existing work (triage: .icm/intake/triage/stale-flag.md)"
dump="$(printf 'We need the vendor area reworked:\n- funnel graph\n- lead export\n- bid history\n- SLA badges\n- invoice list\n- CSAT widget\n')"
expect "six-bullet dump → cut an epic" "$dump"             "Route: $L § A request with no stub, case 2: cut an epic with a breakdown"
long="$(printf 'the vendors and the team %.0s' $(seq 1 40))"
expect "800-character dump → cut an epic" "$long"          "case 2: cut an epic with a breakdown"

# --- no intake contract --------------------------------------------------------------------------
export CLAUDE_PROJECT_DIR="$bare"
expect "no intake: new is silent"     "new"                "SILENT"
expect "no intake: work is silent"    "Vendors should be able to see a funnel graph of their leads" "SILENT"
export CLAUDE_PROJECT_DIR="$main"

# --- robustness ----------------------------------------------------------------------------------
for payload in 'not json at all' '{}' '{"prompt":42}' ''; do
  raw="$(printf '%s' "$payload" | bash "$hook" 2>/dev/null)"; code=$?
  if [ "$code" -eq 0 ] && [ -z "$raw" ]; then
    pass=$((pass + 1)); printf 'PASS  malformed input is silent and exits 0: %s\n' "${payload:-<empty>}"
  else
    fail=$((fail + 1)); printf 'FAIL  malformed input %s: exit %s, output %s\n' "${payload:-<empty>}" "$code" "${raw:-<silent>}"
  fi
done

printf '\n%s passed, %s failed. Slowest call: %s ms (%s).\n' "$pass" "$fail" "$slowest" "$slowest_label"
[ "$fail" -eq 0 ]
