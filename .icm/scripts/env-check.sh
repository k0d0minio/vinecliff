#!/usr/bin/env bash
# env-check.sh — pre-flight environment and dependency check for the pipeline (TEMPLATE-OWNED).
#
# Run it at the start of a session, or whenever a pipeline script dies on something that is not
# the run: it says in one pass whether this machine (or cloud session, or Actions runner) can
# drive the pipeline at all — the binaries the scripts call, a GitHub route (token or `gh`
# login), the project's own required variables (`.icm/project.json` → required_env), the
# folder shape, the executable bits, the locale — and, when the repo declares a deploy block,
# whether the Vercel route works (`lib/vercel.sh --check`); the reporting block's channel
# variables are reported as warnings, never failures (a missing channel is a decision, not a
# broken machine). python3 or sqlite3 is recommended for usage-snapshot.sh's OpenCode reader;
# gitleaks for security-check.sh (its built-in patterns are the fallback); psql or docker when
# the repo declares a run-scoped database (db-branch.sh); a `skills/` folder is optional and,
# when present, its SKILL.md front matter must parse (list-skills.sh --check).
#
# It REPORTS, it does not repair — the estate's standing rule for every check. The one repair it
# knows how to make, the executable bit on `.icm/scripts/*.sh`, is behind `--fix`; without the
# flag a missing bit is a WARN line and nothing changes. `scripts/lib/*.sh` are sourced, not run,
# and are deliberately not executable — they are never counted.
#
# Usage: .icm/scripts/env-check.sh [--fix]
# Verdict (stdout, last line):
#   RESULT: PASS   exit 0  — no critical error (warnings are listed above it)
#   RESULT: FAIL   exit 1  — at least one critical error: a missing binary or a missing folder
set -euo pipefail

FIX=0
for arg in "$@"; do
  case "$arg" in
    --fix) FIX=1 ;;
    -h|--help) sed -n '2,20p' "${BASH_SOURCE[0]}"; exit 0 ;;
    *) echo "unknown argument: $arg (usage: env-check.sh [--fix])" >&2; exit 2 ;;
  esac
done

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$repo_root"

echo "=== ICM Pipeline Pre-Flight Environment Check ==="

ERRORS=0
WARNINGS=0
ok()   { echo "  [OK] $*"; }
info() { echo "  [INFO] $*"; }
warn() { echo "  [WARN] $*"; WARNINGS=$((WARNINGS + 1)); }
fail() { echo "  [FAIL] $*"; ERRORS=$((ERRORS + 1)); }

# 1. Critical binaries — every pipeline script needs bash, git, jq and curl; the sync and the
#    conformance tooling need rsync. rg is recommended (the contracts suggest it for searches)
#    but no script calls it, so its absence is a warning, not a failure.
echo "[1/9] Checking Critical System Tooling..."
for tool in bash git rsync jq curl; do
  if command -v "$tool" >/dev/null 2>&1; then
    ok "Binary found: $tool"
  else
    fail "Missing required binary: $tool"
  fi
done
if command -v rg >/dev/null 2>&1; then
  ok "Binary found: rg (recommended)"
else
  warn "rg (ripgrep) not found in PATH — recommended for searches; no pipeline script needs it"
fi
if command -v python3 >/dev/null 2>&1 || command -v sqlite3 >/dev/null 2>&1; then
  ok "Binary found: $(command -v python3 >/dev/null 2>&1 && echo python3 || echo sqlite3) (recommended — usage-snapshot.sh's OpenCode reader)"
else
  info "neither python3 nor sqlite3 found — usage-snapshot.sh records SKIP under OpenCode; Claude Code needs neither"
fi
if command -v gitleaks >/dev/null 2>&1; then
  ok "Binary found: gitleaks (recommended — security-check.sh's scanner of record)"
else
  warn "gitleaks not found in PATH — security-check.sh runs its built-in patterns only (brew install gitleaks)"
fi

# 2. A GitHub route — a token in the environment, or a logged-in `gh` CLI (lib/gh.sh takes
#    either, in that order). Neither is a WARN; one is enough.
echo "[2/9] Checking GitHub CLI & Authentication..."
if command -v gh >/dev/null 2>&1; then
  ok "Binary found: gh (GitHub CLI)"
else
  info "GitHub CLI (gh) not found in PATH — the scripts fall back to curl with a token"
fi
if [ -n "${GH_TOKEN:-}" ] || [ -n "${GITHUB_TOKEN:-}" ]; then
  ok "GitHub token present in environment (GITHUB_TOKEN or GH_TOKEN)"
elif command -v gh >/dev/null 2>&1 && env -u GITHUB_TOKEN -u GH_TOKEN gh auth status >/dev/null 2>&1; then
  ok "No token in the environment, but gh is logged in — lib/gh.sh will use the CLI route"
else
  warn "No GitHub route: neither GITHUB_TOKEN/GH_TOKEN set nor a logged-in gh CLI (export a token, or run: gh auth login)"
fi

# 3. The project manifest and the variables it says this repo needs.
echo "[3/9] Checking Project Manifest & Required Environment (.icm/project.json)..."
if [ -f ".icm/project.json" ]; then
  if command -v jq >/dev/null 2>&1 && jq -e . .icm/project.json >/dev/null 2>&1; then
    ok ".icm/project.json parses"
    name="$(jq -r '.name // empty' .icm/project.json)"
    complexity="$(jq -r '.complexity // empty' .icm/project.json)"
    [ -n "$name" ]    && ok "name: $name"    || warn ".icm/project.json has no \"name\""
    case "$complexity" in
      micro|standard) ok "complexity: $complexity" ;;
      "")             info "no \"complexity\" in .icm/project.json — read as \"standard\"" ;;
      *)              warn ".icm/project.json complexity is \"$complexity\" (expected \"micro\" or \"standard\" — read as \"standard\")" ;;
    esac
    stamp="$(jq -r '.migrations.stamp // empty' .icm/project.json)"
    case "$stamp" in
      millis|seconds) ok "migrations.stamp: $stamp" ;;
      epoch)          ok "migrations.stamp: epoch (<13 digits>-<name>.$(jq -r '.migrations.extension // "sql"' .icm/project.json) for this branch's own migrations)" ;;
      "")             info "no \"migrations.stamp\" — read as \"millis\" (V<17 digits>__<name>.sql for this branch's own migrations)" ;;
      *)              warn ".icm/project.json migrations.stamp is \"$stamp\" (expected \"millis\", \"seconds\" or \"epoch\" — read as \"millis\")" ;;
    esac
    iso="$(jq -r '.database.isolation // empty' .icm/project.json)"
    nk="$(jq -r '.database.neon.api_key_env // "NEON_API_KEY"' .icm/project.json)"
    case "$iso" in
      schema)    if command -v psql >/dev/null 2>&1; then ok "database.isolation: schema (psql found)"; else warn "database.isolation is \"schema\" but psql is not in PATH — db-branch.sh will SKIP"; fi ;;
      container) if command -v docker >/dev/null 2>&1 || command -v podman >/dev/null 2>&1; then ok "database.isolation: container (docker/podman found)"; else warn "database.isolation is \"container\" but neither docker nor podman is in PATH — db-branch.sh will SKIP"; fi ;;
      neon)      if [ "$(jq -r '.database.provider // empty' .icm/project.json)" != "neon" ]; then warn "database.isolation is \"neon\" but database.provider is not — set provider: neon and database.neon.project_id (db-branch.sh will SKIP)"
                 elif ! command -v curl >/dev/null 2>&1; then warn "database.isolation is \"neon\" but curl is not in PATH — db-branch.sh will SKIP"
                 elif [ -z "${!nk:-}" ]; then warn "database.isolation is \"neon\" but \$$nk is unset in this environment — db-branch.sh will SKIP (export it; never in git)"
                 else ok "database.isolation: neon (curl found, \$$nk set)"; fi ;;
      none|"")   info "database.isolation: none — db-branch.sh says SKIP; declare neon|schema|container to give each run its own database" ;;
      *)         warn ".icm/project.json database.isolation is \"$iso\" (expected none|schema|container|neon — read as none)" ;;
    esac
    if [ "$(jq -r '.database.provider // empty' .icm/project.json)" = "neon" ]; then
      if [ -z "$(jq -r '.database.neon.project_id // empty' .icm/project.json)" ]; then warn "database.provider is neon but database.neon.project_id is empty — db-env.sh and the cleanup workflow have no project to read"
      elif [ -n "${!nk:-}" ]; then ok "Neon project declared and \$$nk set — db-env.sh status reads it"
      else info "Neon project declared; \$$nk unset here — db-env.sh, db-branch.sh (neon) and setup.sh read nothing until it is exported"; fi
    fi
    REQ_ENVS="$(jq -r '.required_env[]?' .icm/project.json 2>/dev/null || true)"
    if [ -n "$REQ_ENVS" ]; then
      for var in $REQ_ENVS; do
        if [ -n "${!var:-}" ]; then
          ok "Required environment variable set: $var"
        else
          warn "Missing required environment variable: $var"
        fi
      done
    else
      info "No required_env variables declared in .icm/project.json"
    fi
  else
    fail ".icm/project.json is not valid JSON (or jq is missing)"
  fi
else
  warn ".icm/project.json not found — the scripts run on defaults; seed it with icm-check.sh --fix"
fi

# 4. The folder shape the pipeline promises. No profile line is read — every repo carries the one
#    pipeline, and `complexity` (step 3) is the only weight.
echo "[4/9] Checking Local ICM Directory Integrity..."
if [ -d ".icm" ]; then
  ok "Local .icm directory present"
  for sub in stages lanes _shared scripts; do
    if [ -d ".icm/$sub" ]; then
      ok "Subdirectory present: .icm/$sub"
    else
      fail "Missing expected subdirectory: .icm/$sub"
    fi
  done
  for sub in raw raw/_processed processed; do
    if [ -d ".icm/$sub" ]; then
      ok "Subdirectory present: .icm/$sub"
    else
      info "No .icm/$sub yet — process-raw.sh creates it on first use"
    fi
  done
  if [ -d ".icm/skills" ]; then
    if [ -x ".icm/scripts/list-skills.sh" ]; then
      if sk="$(bash .icm/scripts/list-skills.sh --check 2>/dev/null)"; then
        ok "Capability skills: $(printf '%s' "$sk" | tail -1 | sed 's/^RESULT: OK //') skill(s) parse (.icm/skills/)"
      else
        warn "A .icm/skills/*/SKILL.md does not parse — run: .icm/scripts/list-skills.sh --check"
      fi
    else
      ok "Subdirectory present: .icm/skills (list-skills.sh not executable — see step 5)"
    fi
  else
    info "No .icm/skills yet — optional; icm-sync.sh / setup.sh --fix seed the three template skills"
  fi
  if [ -d ".icm/_shared/run-pack" ]; then
    ok "Run-pack templates present: .icm/_shared/run-pack (run-pack.sh seeds every run's seven files)"
  else
    warn "No .icm/_shared/run-pack/ — run-pack.sh cannot seed a run's canonical files; icm-sync.sh --apply, or setup.sh --fix"
  fi
else
  fail "Current directory lacks an .icm folder"
fi

# 5. Executable bits on the scripts a stage invokes. lib/ is sourced and excluded on purpose.
echo "[5/9] Checking Script Execution Permissions..."
if [ -d ".icm/scripts" ]; then
  NON_EXEC="$( { find .icm/scripts -maxdepth 1 -name '*.sh' ! -executable 2>/dev/null; find .icm/skills -mindepth 3 -maxdepth 3 -path '*/scripts/*.sh' ! -executable 2>/dev/null; } | sort || true)"
  if [ -n "$NON_EXEC" ]; then
    n="$(printf '%s\n' "$NON_EXEC" | wc -l | tr -d ' ')"
    if [ "$FIX" -eq 1 ]; then
      # shellcheck disable=SC2086
      chmod +x $NON_EXEC
      ok "$n script(s) in .icm/scripts (or a skill's scripts/) lacked +x — fixed (--fix): $(printf '%s' "$NON_EXEC" | tr '\n' ' ')"
    else
      warn "$n script(s) in .icm/scripts (or a skill's scripts/) lack +x (re-run with --fix to set it): $(printf '%s' "$NON_EXEC" | tr '\n' ' ')"
    fi
  else
    ok "All scripts in .icm/scripts (and the skills' scripts/) possess executable permissions"
  fi
fi

# 6. The deploy block, and whether the Vercel route works. Absent is a fact, not a fault.
echo "[6/9] Checking Deploy Block & Vercel Route (.icm/project.json → deploy)..."
if [ -f ".icm/project.json" ] && jq -e '(.deploy.projects // []) | length > 0' .icm/project.json >/dev/null 2>&1; then
  n_pj="$(jq -r '.deploy.projects | length' .icm/project.json)"
  tok_var="$(jq -r '.deploy.token_env // "VERCEL_TOKEN"' .icm/project.json)"
  ok "deploy declared: $n_pj project(s) on $(jq -r '.deploy.platform // "vercel"' .icm/project.json)${tok_var:+ (token: $tok_var)}"
  if [ -n "${!tok_var:-}" ] || [ -n "${VERCEL_TOKEN:-}" ]; then
    if out="$(bash .icm/scripts/lib/vercel.sh --check 2>/dev/null)"; then
      ok "Vercel route: $(printf '%s' "$out" | grep -m1 'GET ' || echo OK)"
    else
      fail "Vercel route: the token named by deploy.token_env cannot list the team's projects — deploy names a team this token does not reach"
    fi
  else
    warn "deploy declared but $tok_var (and VERCEL_TOKEN) unset — deploy-status.sh, env.sh audit and rollback.sh will stop; set it in this environment or the cloud panel"
  fi
else
  info "deploy not declared in .icm/project.json — deploy-status.sh writes 'not declared'; setup.sh asks for the block"
fi

# 7. The reporting block — which kinds map to which channels, and whether their variables are
#    set here. A channel with no variable is a WARN: report.sh prints SKIPPED and exits 0.
echo "[7/9] Checking Reporting Channels (.icm/project.json → reporting)..."
if [ -f ".icm/project.json" ]; then
  for kind in announce alert economics; do
    chans="$(jq -r "(.reporting[\"$kind\"] // (if \"$kind\" == \"announce\" and (.reporting == null) then [\"github-release\"] else [] end)) | join(\" \")" .icm/project.json 2>/dev/null)"
    if [ -z "$chans" ]; then
      info "reporting.$kind → none$([ "$kind" = alert ] && echo ' (a red CI job and Vercel'"'"'s own email are the alert)')"
      continue
    fi
    ok "reporting.$kind → $chans"
    for ch in $chans; do
      case "$ch" in
        github-release) : ;;  # the GitHub route above is its whole requirement
        slack|email)
          for var in $(jq -r ".reporting.channels[\"$ch\"] // {} | to_entries[] | select(.key | endswith(\"_env\")) | .value" .icm/project.json); do
            [ -n "${!var:-}" ] && ok "$ch: $var set" || warn "$ch: $var unset here — report.sh will print SKIPPED $ch (fix: .icm/scripts/env.sh add $var --ci)"
          done ;;
        *) warn "reporting.$kind names an unknown channel '$ch' (implemented: github-release, slack, email)" ;;
      esac
    done
  done
  af="$(jq -r '.reporting.announce_from // "session"' .icm/project.json)"
  if [ "$af" = "ci" ] && [ ! -f ".github/workflows/release.yaml" ] && [ ! -f ".github/workflows/release.yml" ]; then
    warn "reporting.announce_from is 'ci' but no .github/workflows/release.yaml exists — nothing will announce (seed the reference workflow, or set announce_from to session)"
  fi
fi

# 8. A UTF-8 locale — the contracts and the decision regexes carry non-ASCII punctuation.
echo "[8/9] Checking System Locale & Encoding..."
if [[ "${LC_ALL:-${LC_CTYPE:-${LANG:-}}}" =~ UTF-8|utf8|UTF8 ]]; then
  ok "UTF-8 locale in effect (${LC_ALL:-${LC_CTYPE:-$LANG}})"
else
  warn "No UTF-8 locale in effect (LANG='${LANG:-unset}') — any UTF-8 locale is fine, e.g. C.UTF-8"
fi

# 9. The dependency audit's tool and the health endpoint — optional, reported, never required.
#    security-check.sh (its scanner, gitleaks, is step 1's business) audits with the tool the
#    lockfile implies, or with `security.audit_command` for another ecosystem; health-check.sh
#    pings with curl (step 1) whatever endpoint the manifest declares.
echo "[9/9] Checking the Dependency Audit Tool & Health Endpoint (security-check.sh, health-check.sh)..."
lock_seen=0
audit_tool() { # <lockfile> <tool> <how it is checked> <install hint>
  [ -f "$1" ] || return 0
  lock_seen=1
  if eval "$3" >/dev/null 2>&1; then ok "$1 present and $2 available — security-check.sh audits with it"
  else warn "$1 present but $2 not available — security-check.sh's audit cannot run here ($4)"; fi
}
audit_tool pnpm-lock.yaml    pnpm 'command -v pnpm' "the repo's package manager"
audit_tool package-lock.json npm  'command -v npm'  "the repo's package manager"
audit_tool yarn.lock         yarn 'command -v yarn' "the repo's package manager"
if [ -f ".icm/project.json" ]; then
  ac="$(jq -r '.security.audit_command // empty' .icm/project.json 2>/dev/null || true)"
  if [ -n "$ac" ]; then
    lock_seen=1; ac_tool="${ac%% *}"
    if command -v "$ac_tool" >/dev/null 2>&1; then ok "security.audit_command: $ac — $ac_tool available"
    else warn "security.audit_command names $ac_tool, not on PATH — security-check.sh's audit cannot run here"; fi
  fi
fi
[ "$lock_seen" -eq 1 ] || info "no npm/pnpm/yarn lockfile at the repo root and no security.audit_command — security-check.sh has no dependency audit to run here"
if [ -f ".icm/project.json" ]; then
  n_he="$(jq -r '[ (.health_endpoint // empty | if type == "array" then .[] else . end), ((.deploy.projects // [])[]? | .health_endpoint // empty) ] | map(select(. != "")) | unique | length' .icm/project.json 2>/dev/null || echo 0)"
  if [ "${n_he:-0}" -gt 0 ]; then ok "health_endpoint: $n_he declared — health-check.sh reads them after the merge"
  else info "no health_endpoint in .icm/project.json — health-check.sh reports SKIP after the merge (setup.sh asks for it)"; fi
fi

echo "-------------------------------------------------"
if [ "$ERRORS" -eq 0 ]; then
  echo "=== Environment Check PASSED ($WARNINGS warnings) ==="
  echo "RESULT: PASS"
  exit 0
else
  echo "=== Environment Check FAILED ($ERRORS critical errors, $WARNINGS warnings) ==="
  echo "RESULT: FAIL"
  exit 1
fi
