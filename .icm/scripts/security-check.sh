#!/usr/bin/env bash
# security-check.sh — the zero-trust gate before a commit or a push: no secret, no known-high dependency (TEMPLATE-OWNED).
#
# The estate's standing rule is "no secrets in git, ever" (`.claude/skills/pr-conventions/SKILL.md`),
# and a rule a human has to remember is a rule that fails on a Friday. This is the deterministic
# half of it: a scan of exactly what is about to leave the machine, run by Build before each commit
# and by every lane before its push, and wired by a repo as its git pre-commit hook where it has one
# (`_shared/project-rules.md` → The factory). It trusts nothing it did not read: not the file name,
# not the author, not the branch.
#
# Two checks, in order:
#   1. Secrets — `gitleaks` over the staged changes (`gitleaks protect --staged --redact`; on a
#      gitleaks that has the newer verbs, `gitleaks git --staged`), or over the branch's commits
#      since its fork point (`--branch`), or the whole tree (`--all`). When gitleaks is not
#      installed the gate does NOT go quiet: a built-in scan of the same change set runs instead,
#      over the highest-signal shapes (cloud and API keys, tokens, private-key blocks, a database
#      URL carrying a password, a JWT, a quoted `secret = "…"`), and says on its own line that it is
#      the fallback. A staged `.env*` file that is not an example is a finding by itself. `--strict`
#      turns "gitleaks absent" into a failure.
#   2. Dependencies — `npm|pnpm|yarn audit` at the high level, or the repo's own
#      `.icm/project.json` → `security.audit_command` for another ecosystem. It hits the network,
#      so on the staged scope it runs only when the change set touches a manifest or lockfile —
#      the moment a dependency can change; `--branch` and `--all` always run it; `--audit` and
#      `--no-audit` override. An audit that could not run (offline, no registry) is a WARN, never a
#      block — except under `--strict`.
#
# Every finding is REDACTED before it is printed or written: the rule, the file and the line, the
# first four characters of the match and nothing more. On a finding the gate writes the redacted
# trace to the run's own error log — `.icm/runs/<slug>/03_build/output/error.log`, or
# `lane/output/error.log` for a lane run — as one entry in error.log's shape (a dated `## ` header
# naming `security-check.sh` and the rule ids, then the findings; the `- resolved:` line is the
# session's to add once the gate passes), so `retrospective.sh` reads it like any other error the
# run fixed and lists it as unresolved until then —
# and exits 1, which is what aborts a pre-commit hook. It
# never edits a file, never unstages anything, never rotates a key: the secret is removed by the
# person who staged it, and rotated by the operator through the provider (the `security-audit` skill
# says how). `--no-verify` is not an answer the pipeline accepts.
#
# The run: `<slug>` as the first argument, else the current branch `claude/<slug>` when that run is
# live, else the live run whose `run.md` records this branch. Without one the trace is printed only.
#
# Usage: .icm/scripts/security-check.sh [<slug>] [--staged|--branch|--all] [--base <ref>]
#                                        [--audit|--no-audit] [--strict]
# Verdict (stdout, last line):
#   RESULT: OK            exit 0  — nothing found (a `[WARN]` above it names a check that could not run)
#   RESULT: SKIP          exit 0  — nothing staged (--staged) or no changed files (--branch)
#   RESULT: BLOCKED <n>   exit 1  — <n> finding(s); the redacted trace is above and in error.log
#   RESULT: FAIL          exit 1  — --strict, and a check could not run
set -uo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$repo_root"
die() { echo "error: $*" >&2; exit 1; }
command -v git >/dev/null 2>&1 || die "git not found"
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || die "not a git repository"

# shellcheck source=lib/project.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/project.sh"

slug=""; scope="staged"; base="origin/main"; audit="auto"; strict=0
while [ $# -gt 0 ]; do
  case "$1" in
    --staged)   scope="staged"; shift ;;
    --branch)   scope="branch"; shift ;;
    --all)      scope="all"; shift ;;
    --base)     base="${2:-}"; [ -n "$base" ] || die "--base needs a ref"; shift 2 ;;
    --audit)    audit="yes"; shift ;;
    --no-audit) audit="no"; shift ;;
    --strict)   strict=1; shift ;;
    -h|--help)  sed -n '2,45p' "${BASH_SOURCE[0]}"; exit 0 ;;
    --*)        die "unknown flag: $1" ;;
    *)          [ -z "$slug" ] && slug="$1" || die "unexpected argument: $1"; shift ;;
  esac
done

# --- the run, for the error log --------------------------------------------------------------------
branch="$(git symbolic-ref --short HEAD 2>/dev/null || true)"
if [ -z "$slug" ] && [ -n "$branch" ]; then
  cand="${branch#claude/}"
  if [ -d ".icm/runs/$cand" ]; then slug="$cand"
  else
    for rm in .icm/runs/*/run.md; do
      [ -f "$rm" ] || continue
      if grep -Eq "^- branch:[[:space:]]*${branch}([[:space:]]|$)" "$rm"; then slug="$(basename "$(dirname "$rm")")"; break; fi
    done
  fi
fi
log=""
if [ -n "$slug" ] && [ -d ".icm/runs/$slug" ]; then
  if [ -d ".icm/runs/$slug/lane" ]; then log=".icm/runs/$slug/lane/output/error.log"; else log=".icm/runs/$slug/03_build/output/error.log"; fi
fi

findings=()       # redacted lines
warnings=()
finding() { findings+=("$1"); echo "  [FOUND] $1"; }
warn()    { warnings+=("$1"); echo "  [WARN] $1"; }
ok()      { echo "  [OK] $*"; }

echo "=== security-check: scope=$scope${slug:+ run=$slug}${branch:+ branch=$branch} ==="

# --- the change set --------------------------------------------------------------------------------
# paths: the files in scope (for the .env rule and the audit trigger); added lines: file<TAB>line<TAB>text
added_lines() {
  awk '
    /^\+\+\+ / { f = substr($0, 5); sub(/^b\//, "", f); next }
    /^@@ /     { split($0, a, " "); split(a[3], b, ","); n = substr(b[1], 2) + 0; next }
    /^\+/ && !/^\+\+\+/ { printf "%s\t%d\t%s\n", f, n, substr($0, 2); n++; next }
    /^-/       { next }
    /^ /       { n++ }
  '
}
case "$scope" in
  staged)
    mapfile -t paths < <(git diff --cached --name-only --diff-filter=ACMR)
    if [ "${#paths[@]}" -eq 0 ]; then echo "nothing staged — nothing to check"; echo "RESULT: SKIP"; exit 0; fi
    lines="$(git diff --cached -U0 --no-color --diff-filter=ACMR | added_lines)" ;;
  branch)
    # shellcheck source=lib/changed-files.sh
    source "$(dirname "${BASH_SOURCE[0]}")/lib/changed-files.sh"
    fork="$(fork_point "$base")" || exit 1
    mapfile -t paths < <(changed_files "$fork")
    if [ "${#paths[@]}" -eq 0 ]; then echo "no changed files since the fork point off $base"; echo "RESULT: SKIP"; exit 0; fi
    lines="$( git diff -U0 --no-color --diff-filter=ACMR "$fork" | added_lines
              git ls-files --others --exclude-standard | while IFS= read -r f; do [ -f "$f" ] && awk -v f="$f" '{ printf "%s\t%d\t%s\n", f, NR, $0 }' "$f"; done )" ;;
  all)
    mapfile -t paths < <(git ls-files)
    lines="" ;;
esac
echo "[1/2] Secrets — $( [ "$scope" = all ] && echo "every tracked file" || echo "${#paths[@]} file(s) in scope")"

# Rule 0: a real .env file in the change set. Examples are the manifest and are fine.
for p in "${paths[@]}"; do
  case "$(basename "$p")" in
    .env.example|.env.sample|.env.template|.env.dist|.env.local.example) ;;
    .env|.env.*) finding "env-file-in-git  $p  (a .env file is never committed — env vars only; \`git rm --cached $p\` and add it to .gitignore)" ;;
  esac
done

# --- gitleaks, or the built-in fallback ----------------------------------------------------------------
gitleaks_ran=0
if command -v gitleaks >/dev/null 2>&1; then
  report="$(mktemp)"; trap 'rm -f "$report"' EXIT
  newer=0; gitleaks git --help >/dev/null 2>&1 && newer=1
  case "$scope" in
    staged) if [ "$newer" -eq 1 ]; then gl=(gitleaks git --staged); else gl=(gitleaks protect --staged); fi ;;
    branch) if [ "$newer" -eq 1 ]; then gl=(gitleaks git --log-opts="$fork..HEAD"); else gl=(gitleaks detect --log-opts="$fork..HEAD"); fi ;;
    all)    if [ "$newer" -eq 1 ]; then gl=(gitleaks dir .); else gl=(gitleaks detect --no-git); fi ;;
  esac
  "${gl[@]}" --redact --verbose --no-banner --exit-code 9 --report-format json --report-path "$report" >/dev/null 2>&1
  rc=$?
  if [ "$rc" -eq 0 ] || [ "$rc" -eq 9 ]; then
    gitleaks_ran=1
    if [ -s "$report" ] && command -v jq >/dev/null 2>&1; then
      while IFS=$'\t' read -r rule file line fp; do
        [ -n "$rule" ] || continue
        finding "gitleaks:$rule  $file:$line  (fingerprint $fp)"
      done < <(jq -r '.[] | [.RuleID, .File, (.StartLine|tostring), (.Fingerprint // "")] | @tsv' "$report" 2>/dev/null)
    elif [ "$rc" -eq 9 ]; then
      finding "gitleaks reported leaks but the report could not be read (jq missing?) — run: ${gl[*]} --redact"
    fi
    ok "gitleaks ran (${gl[*]})"
  else
    warn "gitleaks exited $rc without a verdict — falling back to the built-in patterns (run it by hand: ${gl[*]} --redact --verbose)"
  fi
else
  warn "gitleaks not installed — built-in patterns only (brew install gitleaks · https://github.com/gitleaks/gitleaks); --strict would fail here"
fi

if [ "$gitleaks_ran" -eq 0 ]; then
  # The fallback: the shapes that are unambiguous. Each is a POSIX ERE; the last is case-insensitive.
  # `allow` drops the obvious placeholders so an .env.example line is not a finding — judged on the
  # MATCH and a short tail after it (the host of a database URL), never on the whole line: a real
  # key on a line that also says "example" is still a key.
  allow='(example|placeholder|xxxx|<your|changeme|change-me|dummy|process\.env|os\.environ|\$\{|env\(|redacted|user:pass|password@|localhost|127\.0\.0\.1)'
  rules=(
    "aws-access-key|(A3T[A-Z0-9]|AKIA|ASIA|AGPA|AIDA|AROA|AIPA|ANPA|ANVA)[A-Z0-9]{16}"
    "github-token|gh[pousr]_[A-Za-z0-9]{36,}"
    "github-fine-grained-token|github_pat_[A-Za-z0-9_]{22,}"
    "slack-token|xox[baprs]-[A-Za-z0-9-]{10,}"
    "slack-webhook|hooks\.slack\.com/services/T[A-Za-z0-9]+/B[A-Za-z0-9]+/[A-Za-z0-9]+"
    "stripe-live-key|(sk|rk)_live_[A-Za-z0-9]{16,}"
    "openai-key|sk-(proj-)?[A-Za-z0-9_-]{32,}"
    "anthropic-key|sk-ant-[A-Za-z0-9_-]{20,}"
    "resend-key|re_[A-Za-z0-9]{24,}"
    "sendgrid-key|SG\.[A-Za-z0-9_-]{16,}\.[A-Za-z0-9_-]{16,}"
    "google-api-key|AIza[0-9A-Za-z_-]{35}"
    "private-key-block|-----BEGIN (RSA |EC |DSA |OPENSSH |PGP )?PRIVATE KEY"
    "database-url-with-password|(postgres(ql)?|mysql|mongodb(\+srv)?|redis|amqp)://[^:/@[:space:]'\"]+:[^@[:space:]'\"]{4,}@"
    "jwt|eyJ[A-Za-z0-9_-]{10,}\.eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}"
    "generic-secret-assignment|(api[_-]?key|secret|token|passw(or)?d|client[_-]?secret)[A-Za-z0-9_]*[[:space:]]*[:=][[:space:]]*['\"][A-Za-z0-9_/+=.-]{16,}['\"]"
  )
  skip_file='(^|/)(pnpm-lock\.yaml|package-lock\.json|yarn\.lock|bun\.lockb?|.*\.min\.js|.*\.map|.*\.(png|jpe?g|gif|webp|svg|ico|pdf|woff2?|ttf))$|^\.icm/runs/[^/]+/.*/error\.log$'
  scan() { # stdin: file<TAB>line<TAB>text
    awk -F'\t' -v allow="$allow" -v skip="$skip_file" -v rulestr="$(printf '%s\n' "${rules[@]}")" '
      BEGIN { n = split(rulestr, R, "\n"); for (i = 1; i <= n; i++) { p = index(R[i], "|"); name[i] = substr(R[i], 1, p - 1); re[i] = substr(R[i], p + 1) } }
      {
        if ($1 ~ skip) next
        text = $3
        for (i = 1; i <= n; i++) {
          hay = (name[i] == "generic-secret-assignment") ? tolower(text) : text
          if (match(hay, re[i])) {
            window = tolower(substr(text, RSTART, RLENGTH + 32))
            if (window ~ allow) continue
            printf "%s\t%s:%s\t%s…[redacted]\n", name[i], $1, $2, substr(text, RSTART, 4)
            break
          }
        }
      }'
  }
  if [ "$scope" = "all" ]; then
    hits="$(git ls-files -z | xargs -0 -r awk 'BEGIN{OFS="\t"} { print FILENAME, FNR, $0 }' 2>/dev/null | scan)"
  else
    hits="$(printf '%s\n' "$lines" | scan)"
  fi
  if [ -n "$hits" ]; then
    while IFS=$'\t' read -r name where masked; do
      [ -n "$name" ] || continue
      finding "$name  $where  $masked"
    done <<<"$hits"
  fi
  ok "built-in patterns ran (${#rules[@]} rules — the fallback, not gitleaks' full set)"
fi

# --- 2. dependencies -----------------------------------------------------------------------------------
echo "[2/2] Dependencies — high and critical advisories"
manifest_re='(^|/)(package\.json|pnpm-lock\.yaml|package-lock\.json|yarn\.lock|bun\.lockb?|requirements[^/]*\.txt|poetry\.lock|Pipfile\.lock|Cargo\.lock|go\.sum|Gemfile\.lock|composer\.lock)$'
run_audit="no"
case "$audit" in
  yes) run_audit="yes" ;;
  no)  run_audit="no" ;;
  auto)
    if [ "$scope" != "staged" ]; then run_audit="yes"
    else for p in "${paths[@]}"; do if printf '%s' "$p" | grep -Eq "$manifest_re"; then run_audit="yes"; break; fi; done; fi ;;
esac
if [ "$run_audit" = "no" ]; then
  echo "  [INFO] audit skipped — no manifest or lockfile in the change set (--audit forces it; --branch and --all always audit)"
else
  cmd=""; kind=""
  override="$(security_audit_command)"
  if [ -n "$override" ]; then cmd="$override"; kind="project.json → security.audit_command"
  elif [ -f pnpm-lock.yaml ] && command -v pnpm >/dev/null 2>&1; then cmd="pnpm audit --audit-level=high --json"; kind="pnpm"
  elif [ -f package-lock.json ] && command -v npm >/dev/null 2>&1; then cmd="npm audit --audit-level=high --json"; kind="npm"
  elif [ -f yarn.lock ] && command -v yarn >/dev/null 2>&1; then
    if yarn --version 2>/dev/null | grep -q '^1\.'; then cmd="yarn audit --level high --json"; kind="yarn-classic"; else cmd="yarn npm audit --severity high --json"; kind="yarn-berry"; fi
  fi
  if [ -z "$cmd" ]; then
    echo "  [INFO] no lockfile the gate knows (pnpm/npm/yarn) and no security.audit_command — audit skipped"
  else
    out="$(bash -c "$cmd" 2>&1)"; rc=$?
    case "$kind" in
      pnpm|npm)
        hi="$(printf '%s' "$out" | jq -r '(.metadata.vulnerabilities.high // 0) + (.metadata.vulnerabilities.critical // 0)' 2>/dev/null || echo "")"
        if [ -n "$hi" ]; then
          if [ "$hi" -gt 0 ]; then finding "dependency-audit  $kind reports $hi high/critical advisor(y|ies) — run: ${cmd% --json}"
          else ok "$kind audit: no high/critical advisories"; fi
        elif [ "$rc" -eq 0 ]; then ok "$kind audit: clean"
        else warn "$kind audit could not run (exit $rc — offline, or no registry?): $(printf '%s' "$out" | tail -1 | cut -c1-120)"; fi ;;
      yarn-classic)
        if [ $((rc & 24)) -ne 0 ]; then finding "dependency-audit  yarn reports high/critical advisories — run: yarn audit --level high"
        elif [ "$rc" -eq 0 ] || [ "$rc" -lt 8 ]; then ok "yarn audit: no high/critical advisories"
        else warn "yarn audit could not run (exit $rc)"; fi ;;
      yarn-berry)
        if [ "$rc" -eq 0 ]; then ok "yarn npm audit: no high/critical advisories"
        elif [ "$rc" -eq 1 ]; then finding "dependency-audit  yarn npm audit reports high/critical advisories — run: yarn npm audit --severity high"
        else warn "yarn npm audit could not run (exit $rc)"; fi ;;
      *)
        if [ "$rc" -eq 0 ]; then ok "audit ($cmd): clean"
        else finding "dependency-audit  '$cmd' exited $rc — $(printf '%s' "$out" | tail -1 | cut -c1-120)"; fi ;;
    esac
  fi
fi

# --- the verdict, and the trace ------------------------------------------------------------------------
echo "-------------------------------------------------"
n="${#findings[@]}"
if [ "$n" -gt 0 ]; then
  head="$(git rev-parse --short HEAD 2>/dev/null || echo none)"
  if [ -n "$log" ]; then
    mkdir -p "$(dirname "$log")"
    # The entry takes error.log's one shape (stages/03_build/CONTEXT.md → Outputs; retrospective.sh
    # reads it): a dated header naming the source and the error CLASS — here the rule ids, so the
    # collector's signature is "security-check.sh — <rule>" and not a file name — then the
    # redacted findings verbatim. No `- resolved:` line is written here: the collector reads one as
    # a fix that landed, and only the session knows when it has. It adds the line (and a `- rule:`
    # line only when the leak was a constraint of this repo) once the gate passes.
    rules_hit="$(printf '%s\n' "${findings[@]}" | awk '{ sub(/:.*$/, "", $1); print $1 }' | sort -u | paste -sd', ' -)"
    {
      echo "## $(date -u +%Y-%m-%dT%H:%M:%SZ) security-check.sh — $rules_hit"
      echo "scope=$scope head=$head branch=${branch:-?} — BLOCKED $n (redacted trace; the secret itself is never written)"
      printf -- '%s\n' "${findings[@]}"
      echo "(unresolved until the session adds a \`- resolved:\` line: remove the secret from the change, have the operator rotate it, re-run the gate, then write what was wrong and what is true now)"
      echo
    } >> "$log"
    echo "trace (redacted) appended to $log — add its \`- resolved:\` line once the gate passes"
  else
    echo "no live run resolved for this branch — trace printed only (pass <slug> to log it)"
  fi
  echo "aborted: remove the secret from the change (never --no-verify), have the operator rotate it, then re-run"
  echo "RESULT: BLOCKED $n"; exit 1
fi
if [ "$strict" -eq 1 ] && [ "${#warnings[@]}" -gt 0 ]; then
  echo "--strict: ${#warnings[@]} check(s) could not run — install what is missing, or drop --strict"
  echo "RESULT: FAIL"; exit 1
fi
echo "RESULT: OK"; exit 0
