#!/usr/bin/env bash
# env.sh — the repo's environment variables across every surface they live on (TEMPLATE-OWNED).
#
# The per-repo generalisation of the estate's `vercel-env.sh` (agency brief §4.8, flag 4): the
# same `.env.example` convention, the same one-way flows, and NO registry — the Vercel projects
# and their paths come from the repo's own deploy block (`.icm/project.json` → deploy.projects),
# the token's NAME from deploy.token_env (else plain VERCEL_TOKEN), GitHub from lib/gh.sh. It runs
# from any harness and never reads a file outside the repo.
#
# The five surfaces a key can need to exist on, and who can read each:
#   Vercel (production/preview/development)   names, targets, kinds via the API — never a value
#   GitHub Actions secrets and variables       names via the REST API
#   the Claude cloud environment panel         nobody — listed as a checklist line, never a gap
#   local .env.local                           presence and whether git ignores it
#   the pipeline's own required_env            .icm/project.json
#
# `.env.example` is the manifest: a `#` line (or lines) DIRECTLY above `KEY=` is that key's note;
# an optional `[targets]` suffix on the block's last comment line scopes it. The three Vercel
# tokens keep their meaning (production, preview, development; none = all three) and two more are
# additive: `[ci]` — the key must exist as a GitHub Actions secret or variable — and `[cloud]` —
# the key must be set in the Claude cloud environment panel. A fourth, `[optional]`, declares an
# override the code reads with a default in hand: documented, required on no surface, so its
# absence from Vercel is never a gap (combine it with targets to say where it goes WHEN set).
# Values NEVER appear in the file. Names the platform sets itself (`NODE_ENV`, `CI`, Vercel's
# system variables — `VERCEL_ENV`, `VERCEL_URL`, `VERCEL_OIDC_TOKEN`, `VERCEL_GIT_*` …) are never
# asked for: the code-reads check skips them, because no manifest can supply them.
#
# Verbs:
#   audit [--changed] [--twice]
#                         names only. Per key and per surface it is scoped to: declared-but-missing
#                         and present-but-undeclared on Vercel (per project, per target), on GitHub,
#                         locally, in required_env; plus every `process.env.X` the tree reads (and
#                         turbo.json globalEnv) that no .env.example declares. `--changed` limits
#                         it to keys this branch added — Build's pre-push check and Release's stop
#                         class 3. A Vercel variable of type `sensitive` is reported as present,
#                         not pullable — never as missing. Read-only in the strong sense: GET only,
#                         the CLI never run, nothing written. Deterministic by construction: every
#                         Vercel list is read to its last page, rows are sorted within their
#                         section, and a surface that could not be READ this run (a rate limit, a
#                         5xx, a timeout — after lib/vercel.sh's retries) is one [UNKNOWN] row with
#                         its own count, never a run of missing-key gaps. `--twice` is the
#                         regression check: the audit runs twice and the two outputs are diffed —
#                         identical → the second run's report, else the diff and RESULT: UNSTABLE.
#                         RESULT: OK | GAPS n | UNKNOWN n (gaps first; unknowns ride in its
#                         parenthesis) | UNSTABLE (--twice only)
#   init                  seeds each project's .env.example with Vercel's key NAMES, `# TODO: note`
#                         placeholders and `[targets]` from Vercel's own scoping. Never overwrites,
#                         reorders or writes a value.  RESULT: SEEDED n | UNCHANGED
#   pull [--target t]     `vercel env pull` per project path into .env.local, the notes from
#                         .env.example interleaved above the keys; refuses BEFORE the pull when
#                         .env.local is not gitignored; restores the .gitignore line the CLI
#                         appends. A sensitive key cannot be read back: it is written as `KEY=`
#                         under its note with one `# sensitive — paste locally` line. Default
#                         target: development (the cloud hydrate hook passes production).
#                         RESULT: PULLED n | REFUSED | SKIP (vercel CLI not found)
#   push-notes [--dry-run] .env.example notes → Vercel comments: the `comment` field and nothing
#                         else; `TODO` placeholders skipped; a note over 500 characters named, never
#                         truncated; idempotent by comparison.  RESULT: PUSHED n | UNCHANGED
#   add KEY [--targets production,preview,development] [--sensitive] [--github secret|variable]
#           [--ci] [--cloud] [--note "<one sentence>"]
#                         creates the variable where the flags say, WITH THE VALUE READ FROM STDIN
#                         ONLY (`printf '%s' "$VALUE" | .icm/scripts/env.sh add KEY …` or `< file`),
#                         never from an argument: `vercel env add KEY <target> [--sensitive]` per
#                         target per project, `gh secret set` / `gh variable set` from the same
#                         stdin, then the key and its note appended to .env.example with the right
#                         suffix. No value on stdin → it prints the exact commands for the human
#                         and RESULT: SKIP (no value on stdin). It never prints the value, never
#                         echoes stdin, and runs with tracing off.  RESULT: ADDED <where> | SKIP
#   doc KEY [--targets …] [--ci] [--cloud] [--optional] [--note "…"]
#                         prints the .env.example block a new key needs and the audit lines it
#                         would clear — the documenting half for a session that must create
#                         nothing. Documenting a variable means its key, its note and the surfaces
#                         it must exist on — never its value.  RESULT: DOC
#
# Rules, all already the estate's: values never in git, never in argv, never printed; .env.example
# is the only committed file and carries keys and prose; a value moves Vercel → .env.local and
# stdin → Vercel/GitHub, never the other way; a plaintext credential found anywhere is a P0 to
# flag, not to commit around.
#
# Usage: .icm/scripts/env.sh <audit|init|pull|push-notes|add|doc> [args]
# Exit:  0 — every verb reports; GAPS is the report's content (D15) · 2 usage · 1 a flow failed
set -uo pipefail
set +x

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$repo_root"
die() { echo "error: $*" >&2; exit 2; }
command -v jq >/dev/null 2>&1 || die "jq not found"

verb="${1:-}"; shift || true
case "$verb" in audit|init|pull|push-notes|add|doc) : ;; *) die "usage: env.sh <audit|init|pull|push-notes|add|doc> [args]" ;; esac

# shellcheck source=lib/project.sh
source "$here/lib/project.sh"
# shellcheck source=lib/vercel.sh
source "$here/lib/vercel.sh"

# --- the manifests: one .env.example per deploy project path (or the root's when undeclared) ------------

declare -a MANIFESTS=()   # "<project-name>|<path>|<example-file>"
if vercel_declared; then
  while IFS= read -r pj; do
    [ -n "$pj" ] || continue
    n="$(printf '%s' "$pj" | jq -r '.name')"; p="$(printf '%s' "$pj" | jq -r '.path // "."')"; p="${p#./}"; p="${p%/}"; [ -n "$p" ] || p="."
    MANIFESTS+=("$n|$p|${p%/.}/.env.example")
  done < <(deploy_projects)
else
  MANIFESTS+=("(root)|.|.env.example")
fi
# Tidy "./.env.example" → ".env.example"
for i in "${!MANIFESTS[@]}"; do MANIFESTS[$i]="${MANIFESTS[$i]//|.\/.env.example/|.env.example}"; MANIFESTS[$i]="${MANIFESTS[$i]//|.\/|.env.example/|.|.env.example}"; done

# parse_example <file> → key \t targets(csv, may include ci/cloud) \t note(flattened, suffix stripped)
parse_example() {
  [ -f "$1" ] || return 0
  awk '
    /^#/ { l=$0; sub(/^#[ \t]?/, "", l); note = (note=="" ? l : note " " l); next }
    /^[ \t]*$/ { note=""; next }
    /^[A-Za-z_][A-Za-z0-9_]*=/ {
      key=$0; sub(/=.*/, "", key); t=""; n=note
      if (match(n, /\[[a-z, ]+\][ \t]*$/)) { t=substr(n, RSTART+1, RLENGTH-2); gsub(/[] \t]/, "", t); n=substr(n, 1, RSTART-1); sub(/[ \t]+$/, "", n) }
      print key "\t" t "\t" n; note=""; next }
    { note="" }' "$1"
}
# vercel_targets_of <targets-csv> → the Vercel targets a key is scoped to (csv), "" when ci/cloud/optional only
vercel_targets_of() {
  local t="$1" out="" x
  [ -n "$t" ] || { printf 'production,preview,development'; return; }
  for x in ${t//,/ }; do case "$x" in production|preview|development) out="${out:+$out,}$x" ;; esac; done
  local non=""; for x in ${t//,/ }; do case "$x" in ci|cloud|optional) non=1 ;; esac; done
  if [ -z "$out" ] && [ -z "$non" ]; then out="production,preview,development"; fi
  printf '%s' "$out"
}
has_token() { local t="$1" x; for x in ${1//,/ }; do [ "$x" = "$2" ] && return 0; done; return 1; }

# --- GitHub names (secrets + variables) — read once, names only ------------------------------------------

gh_names=""; gh_note=""; gh_unknown=0
load_gh_names() {
  [ -z "$gh_names$gh_note" ] || return 0
  # shellcheck source=lib/gh.sh
  if ! source "$here/lib/gh.sh" 2>/dev/null; then gh_note="no origin remote — GitHub surfaces not read"; return 0; fi
  if [ -z "${gh_token:-}" ] && ! (command -v gh >/dev/null 2>&1 && env -u GITHUB_TOKEN -u GH_TOKEN gh auth status >/dev/null 2>&1); then
    gh_note="no GitHub route (GH_TOKEN unset, no gh login) — Actions secrets/variables not read"; return 0
  fi
  local r1 r2
  r1="$(gh_api GET "/repos/${repo}/actions/secrets?per_page=100" 2>/dev/null)" || true
  r2="$(gh_api GET "/repos/${repo}/actions/variables?per_page=100" 2>/dev/null)" || true
  local c1 c2; c1="$(printf '%s' "$r1" | tail -n1)"; c2="$(printf '%s' "$r2" | tail -n1)"
  # Both lists or neither: a variables read that failed would turn every [ci] variable into a gap.
  # 401/403/404 is the token's standing permission (a WARN, the same every run); anything else is
  # this run's weather (UNKNOWN).
  for c in "$c1" "$c2"; do
    [ "$c" = "200" ] && continue
    case "$c" in 401|403|404) gh_note="GET /actions/secrets|variables answered HTTP $c (a token needs Secrets: read and Variables: read, or admin) — GitHub surfaces not read" ;;
      *) gh_note="GitHub Actions secrets/variables could not be read this run (HTTP ${c:-000}) — re-run"; gh_unknown=1 ;; esac
    return 0
  done
  gh_names="$(printf '%s' "$r1" | sed '$d' | jq -r '.secrets[].name')"$'\n'"$(printf '%s' "$r2" | sed '$d' | jq -r '.variables[].name')"
}

# --- the process.env reads in the tree -------------------------------------------------------------------

# Names the platform provides at build and run time — never a manifest's to declare (Node, CI
# runners, Next.js, and Vercel's system environment variables, with their NEXT_PUBLIC_ mirrors).
PLATFORM_NAMES='^(NODE_ENV|CI|VERCEL|NEXT_RUNTIME|NEXT_PHASE|(NEXT_PUBLIC_)?VERCEL_(ENV|TARGET_ENV|URL|BRANCH_URL|PROJECT_PRODUCTION_URL|REGION|DEPLOYMENT_ID|PROJECT_ID|OIDC_TOKEN|SKEW_PROTECTION_ENABLED|AUTOMATION_BYPASS_SECRET|GIT_[A-Z_]+))$'
code_reads() {
  { grep -rhoE 'process\.env\.[A-Z][A-Z0-9_]*' --include='*.ts' --include='*.tsx' --include='*.js' --include='*.mjs' --include='*.cjs' \
      --exclude-dir=node_modules --exclude-dir=.next --exclude-dir=dist --exclude-dir=build --exclude-dir=.git --exclude-dir=.icm --exclude-dir=.turbo . 2>/dev/null \
      | sed 's/^process\.env\.//'
    [ -f turbo.json ] && jq -r '(.globalEnv // [])[]' turbo.json 2>/dev/null
  } | grep -vE "$PLATFORM_NAMES" | sort -u
}

# --- audit ------------------------------------------------------------------------------------------------

cmd_audit() {
  local changed=0 twice=0 gaps=0 warns=0 unknowns=0 buf="" args=()
  while [ $# -gt 0 ]; do case "$1" in --changed) changed=1; args+=("$1"); shift ;; --twice) twice=1; shift ;; *) die "audit: unknown flag $1" ;; esac; done
  if [ "$twice" -eq 1 ]; then
    local a b; a="$(mktemp)"; b="$(mktemp)"
    "$here/env.sh" audit ${args[@]+"${args[@]}"} > "$a" 2>&1; "$here/env.sh" audit ${args[@]+"${args[@]}"} > "$b" 2>&1
    if diff -u --label "audit run 1" --label "audit run 2" "$a" "$b"; then cat "$b"; rm -f "$a" "$b"; exit 0; fi
    rm -f "$a" "$b"; echo "RESULT: UNSTABLE (two audits of the same tree differed — the diff above names the rows that moved)"; exit 0
  fi
  local changed_keys=""
  if [ "$changed" -eq 1 ]; then
    # shellcheck source=lib/changed-files.sh
    source "$here/lib/changed-files.sh"
    local fork; fork="$(fork_point origin/main 2>/dev/null || fork_point main 2>/dev/null || true)"
    if [ -n "$fork" ]; then
      for m in "${MANIFESTS[@]}"; do
        f="${m##*|}"
        changed_keys="$changed_keys"$'\n'"$(git diff "$fork" -- "$f" 2>/dev/null | grep -E '^\+[A-Za-z_][A-Za-z0-9_]*=' | sed -E 's/^\+//; s/=.*//')"
      done
      changed_keys="$changed_keys"$'\n'"$(changed_files "$fork" | grep -E '\.(ts|tsx|js|mjs|cjs)$' | xargs -r grep -hoE 'process\.env\.[A-Z][A-Z0-9_]*' 2>/dev/null | sed 's/^process\.env\.//')"
      changed_keys="$(printf '%s\n' "$changed_keys" | grep -v '^$' | sort -u)"
      echo "=== env audit — keys this branch added since ${fork:0:7} ($(printf '%s\n' "$changed_keys" | grep -c . || true)) ==="
    else
      echo "=== env audit — --changed: no fork point (origin/main not fetched) — auditing everything ==="; changed=0
    fi
  else
    echo "=== env audit — every key, every surface (names only) ==="
  fi
  in_scope() { [ "$changed" -eq 0 ] || printf '%s\n' "$changed_keys" | grep -qx "$1"; }
  # Rows are buffered and printed sorted, section by section, so the report is a function of the
  # tree and the surfaces — never of the order an API happened to answer in.
  gap()     { buf="$buf  [GAP]  $*"$'\n'; gaps=$((gaps+1)); }
  warn()    { buf="$buf  [WARN] $*"$'\n'; warns=$((warns+1)); }
  unknown() { buf="$buf  [UNKNOWN] $*"$'\n'; unknowns=$((unknowns+1)); }
  info()    { buf="$buf  [INFO] $*"$'\n'; }
  ok()      { buf="$buf  [OK]   $*"$'\n'; }
  flush()   { [ -z "$buf" ] || printf '%s' "$buf" | LC_ALL=C sort; buf=""; }
  local gh_unknown_row=0

  local all_declared=""
  for m in "${MANIFESTS[@]}"; do
    IFS='|' read -r name path file <<<"$m"
    flush; echo "--- $name ($file)"
    [ -f "$file" ] || { warn "$file does not exist — nothing declared for $name (env.sh init seeds it)"; continue; }
    git check-ignore -q "$file" 2>/dev/null && warn "$file is gitignored — a manifest git cannot see is not a manifest (add !.env.example under the .env* rule)"
    local rows; rows="$(parse_example "$file")"
    all_declared="$all_declared"$'\n'"$(printf '%s\n' "$rows" | cut -f1)"
    local vercel_rows="" vercel_ok=0
    if [ "$name" != "(root)" ]; then
      if [ -n "$vercel_token" ]; then
        if vercel_rows="$(vercel_env_list "$name" 2>/dev/null)"; then vercel_ok=1
        else unknown "Vercel/$name: env could not be read this run (rate limit, 5xx, or a project ${vercel_token_name} cannot see — env-check.sh names which) — its keys are neither present nor missing; re-run"; fi
      else
        warn "Vercel not read: ${vercel_token_name} unset in this environment"
      fi
    fi
    while IFS=$'\t' read -r key targets note; do
      [ -n "$key" ] || continue
      in_scope "$key" || continue
      local vt; vt="$(vercel_targets_of "$targets")"
      [ -z "$note" ] || [ "$note" = "TODO: note" ] && warn "$key: no note yet (# TODO: note) — one sentence above the key"
      if [ -n "$vt" ] && [ "$vercel_ok" -eq 1 ]; then
        local have; have="$(printf '%s\n' "$vercel_rows" | awk -F'\t' -v k="$key" '$1==k {print $3}' | tr ',' '\n' | grep -v '^$' | sort -u | paste -sd',' -)"
        local kind; kind="$(printf '%s\n' "$vercel_rows" | awk -F'\t' -v k="$key" '$1==k {print $2; exit}')"
        if [ -z "$have" ] && has_token "$targets" optional; then info "$key [optional]: not set on Vercel/$name — the code's default applies"
        elif [ -z "$have" ]; then gap "$key: declared for [$vt], missing on Vercel/$name (add the value in Vercel, or env.sh add $key --targets $vt)"
        else
          local miss=""; for t in ${vt//,/ }; do printf '%s' ",$have," | grep -q ",$t," || miss="${miss:+$miss,}$t"; done
          if [ -n "$miss" ]; then gap "$key: declared for [$vt] but Vercel/$name has it only for [$have] — missing $miss"; else ok "$key on Vercel/$name [$have]$( [ "$kind" = sensitive ] && echo ' — sensitive: present, not pullable')"; fi
        fi
      fi
      if has_token "$targets" ci; then
        load_gh_names
        if [ "$gh_unknown" -eq 1 ]; then [ "$gh_unknown_row" -eq 1 ] || { unknown "$gh_note"; gh_unknown_row=1; }
        elif [ -n "$gh_note" ]; then warn "$key [ci]: $gh_note"
        elif printf '%s\n' "$gh_names" | grep -qx "$key"; then ok "$key [ci] present on GitHub Actions"
        else gap "$key [ci]: not a GitHub Actions secret or variable (printf '%s' \"\$V\" | env.sh add $key --ci --github secret)"; fi
      fi
      has_token "$targets" cloud && info "$key [cloud]: must be set in the Claude cloud environment panel — cannot be read from here (checklist)"
    done <<<"$rows"
    # Present on Vercel, undeclared here.
    if [ "$vercel_ok" -eq 1 ]; then
      while IFS=$'\t' read -r vkey vkind vtargets; do
        [ -n "$vkey" ] || continue
        printf '%s\n' "$rows" | cut -f1 | grep -qx "$vkey" && continue
        in_scope "$vkey" || continue
        gap "$vkey: on Vercel/$name [$vtargets]$( [ "$vkind" = sensitive ] && echo ', sensitive') but undeclared in $file (env.sh init)"
      done <<<"$vercel_rows"
    fi
    # Local file.
    local local_file="${path%/.}/.env.local"; local_file="${local_file#./}"
    if [ -f "$local_file" ]; then
      git check-ignore -q "$local_file" 2>/dev/null && info "$local_file present and ignored" || gap "$local_file present and NOT ignored by git — a value one 'git add' from a commit"
    else info "$local_file absent (env.sh pull writes it)"; fi
  done

  flush; echo "--- the pipeline's own required_env"
  for v in $(project_list '.required_env'); do
    in_scope "$v" || continue
    printf '%s\n' "$all_declared" | grep -qx "$v" && ok "$v declared in a .env.example" || warn "$v (required_env) is not declared in any .env.example — document it there with a [cloud] or [ci] suffix as fits"
  done
  flush; echo "--- what the code reads"
  local reads; reads="$(code_reads)"
  while IFS= read -r k; do
    [ -n "$k" ] || continue
    in_scope "$k" || continue
    printf '%s\n' "$all_declared" | grep -qx "$k" || gap "code reads process.env.$k (or turbo globalEnv) and no .env.example declares it (env.sh doc $k)"
  done <<<"$reads"
  flush
  [ "$changed" -eq 0 ] || echo "(only the keys this branch added were audited; run without --changed for the whole picture)"
  echo "-------------------------------------------------"
  local unk=""; [ "$unknowns" -eq 0 ] || unk=", $unknowns unknown"
  if [ "$gaps" -gt 0 ]; then echo "RESULT: GAPS $gaps ($warns warnings$unk)"
  elif [ "$unknowns" -gt 0 ]; then echo "RESULT: UNKNOWN $unknowns ($warns warnings) — a surface could not be read; not OK until it can"
  else echo "RESULT: OK ($warns warnings)"; fi
  exit 0
}

# --- init -------------------------------------------------------------------------------------------------

append_block() { # <file> <key> <note> <suffix-csv>
  local file="$1" key="$2" note="$3" suffix="$4"
  { [ -s "$file" ] && [ -n "$(tail -c1 "$file")" ] && echo; [ -s "$file" ] && echo; echo "# ${note}${suffix:+  [$suffix]}"; echo "${key}="; } >> "$file"
}
cmd_init() {
  vercel_declared || { echo "deploy not declared in .icm/project.json — init needs the projects Vercel holds"; echo "RESULT: SKIP (no deploy block)"; exit 0; }
  vercel_require "seeding .env.example"
  local seeded=0
  for m in "${MANIFESTS[@]}"; do
    IFS='|' read -r name path file <<<"$m"
    local rows; rows="$(vercel_env_list "$name")" || continue
    [ -f "$file" ] || { : > "$file"; echo "created $file"; }
    git check-ignore -q "$file" 2>/dev/null && echo "  [WARN] $file is gitignored — seeded anyway; add !.env.example to that .gitignore"
    while IFS=$'\t' read -r key kind targets; do
      [ -n "$key" ] || continue
      grep -qE "^${key}=" "$file" && continue
      local suffix=""; local sorted; sorted="$(printf '%s' "$targets" | tr ',' '\n' | grep -E '^(production|preview|development)$' | sort -u | paste -sd',' -)"
      [ "$sorted" = "development,preview,production" ] || [ -z "$sorted" ] || suffix="$sorted"
      append_block "$file" "$key" "TODO: note" "$suffix"
      seeded=$((seeded+1)); echo "  seeded $key → $file${suffix:+ [$suffix]}$( [ "$kind" = sensitive ] && echo ' (sensitive on Vercel)')"
    done <<<"$rows"
  done
  [ "$seeded" -gt 0 ] && echo "RESULT: SEEDED $seeded" || echo "RESULT: UNCHANGED"; exit 0
}

# --- pull -------------------------------------------------------------------------------------------------

cmd_pull() {
  local target="development"
  while [ $# -gt 0 ]; do case "$1" in --target) target="${2:-}"; shift 2 ;; *) die "pull: unknown flag $1" ;; esac; done
  case "$target" in production|preview|development) : ;; *) die "--target must be production|preview|development" ;; esac
  vercel_declared || { echo "deploy not declared in .icm/project.json — nothing to pull"; echo "RESULT: SKIP (no deploy block)"; exit 0; }
  command -v vercel >/dev/null 2>&1 || { echo "vercel CLI not found — install it (npm i -g vercel) to pull; nothing written"; echo "RESULT: SKIP (vercel CLI not found)"; exit 0; }
  vercel_require "pulling values"
  local pulled=0 refused=0 team; team="$(deploy_team)"
  for m in "${MANIFESTS[@]}"; do
    IFS='|' read -r name path file <<<"$m"
    local dir="${path%/.}"; dir="${dir:-.}"; local envlocal="$dir/.env.local"; envlocal="${envlocal#./}"
    if ! git check-ignore -q "$envlocal" 2>/dev/null; then echo "  REFUSED $name: $envlocal is not gitignored — a pulled file would carry live values into a tracked-visible tree; add it to .gitignore first"; refused=$((refused+1)); continue; fi
    local gi="$dir/.gitignore"; local gi_before=""; [ -f "$gi" ] && gi_before="$(cat "$gi")"
    if ! ( cd "$dir" && VERCEL_TOKEN="$vercel_token" vercel env pull .env.local --environment "$target" --yes ${team:+--scope "$team"} >/dev/null 2>&1 ); then
      echo "  FAILED $name: vercel env pull did not write $envlocal (is the directory linked? vercel link --project $name${team:+ --scope $team})"; refused=$((refused+1)); continue
    fi
    # The CLI appends `.env*` to .gitignore unprompted, which hides .env.example — put it back.
    if [ -f "$gi" ] && [ "$(cat "$gi")" != "$gi_before" ]; then printf '%s\n' "$gi_before" > "$gi"; echo "  restored $gi (the CLI had appended to it)"; fi
    # Interleave the notes; write sensitive keys as empty under their note.
    local rows; rows="$(parse_example "$file")"; local kinds; kinds="$(vercel_env_list "$name" 2>/dev/null || true)"
    local tmp; tmp="$(mktemp)"; chmod 600 "$tmp"
    {
      echo "# Written by .icm/scripts/env.sh pull ($target) — regenerated on every pull; keep local-only overrides in .env.development.local."
      echo "# Sensitive variables never come down from Vercel: they appear below as KEY= — paste the value locally."
      echo
      while IFS= read -r line; do
        case "$line" in
          [A-Za-z_]*=*) k="${line%%=*}"; n="$(printf '%s\n' "$rows" | awk -F'\t' -v k="$k" '$1==k {print $3 ($2==""?"":"  ["$2"]"); exit}')"; [ -z "$n" ] || echo "# $n"; printf '%s\n' "$line"; echo ;;
          "#"*) : ;;   # the CLI's own banner is replaced by ours
          *) printf '%s\n' "$line" ;;
        esac
      done < "$envlocal"
      while IFS=$'\t' read -r vkey vkind _; do
        [ "$vkind" = "sensitive" ] || continue
        grep -qE "^${vkey}=" "$envlocal" && continue
        n="$(printf '%s\n' "$rows" | awk -F'\t' -v k="$vkey" '$1==k {print $3; exit}')"; [ -z "$n" ] || echo "# $n"
        echo "# sensitive — paste locally"; echo "${vkey}="; echo
      done <<<"$kinds"
    } > "$tmp"
    mv "$tmp" "$envlocal"; pulled=$((pulled+1)); echo "  pulled  $name → $envlocal ($target, notes interleaved)"
  done
  if [ "$refused" -gt 0 ] && [ "$pulled" -eq 0 ]; then echo "RESULT: REFUSED"; exit 1; fi
  echo "RESULT: PULLED $pulled$( [ "$refused" -gt 0 ] && echo " (refused $refused)")"; exit 0
}

# --- push-notes ---------------------------------------------------------------------------------------------

cmd_push_notes() {
  local dry=0; while [ $# -gt 0 ]; do case "$1" in --dry-run) dry=1; shift ;; *) die "push-notes: unknown flag $1" ;; esac; done
  vercel_declared || { echo "deploy not declared — nothing to push"; echo "RESULT: SKIP (no deploy block)"; exit 0; }
  vercel_require "pushing notes"
  local pushed=0 over=0
  for m in "${MANIFESTS[@]}"; do
    IFS='|' read -r name path file <<<"$m"
    [ -f "$file" ] || continue
    local id; id="$(vercel_project_id "$name")"; [ -n "$id" ] || continue
    local envs; envs="$(vercel_get_all "/v9/projects/${id}/env" envs "" '{id, key, comment: (.comment // "")}' 2>/dev/null)" || { echo "  [WARN] $name: could not list env"; continue; }
    envs="$(printf '%s' "$envs" | jq -c '.[]')"
    while IFS=$'\t' read -r key targets note; do
      [ -n "$key" ] && [ -n "$note" ] && [ "$note" != "TODO: note" ] || continue
      if [ "${#note}" -gt 500 ]; then echo "  [WARN] $key: note is ${#note} characters (Vercel caps at 500) — shorten it in $file; not pushed"; over=$((over+1)); continue; fi
      while IFS= read -r e; do
        [ -n "$e" ] || continue
        local eid; eid="$(printf '%s' "$e" | jq -r .id)"; local cur; cur="$(printf '%s' "$e" | jq -r .comment)"
        [ "$cur" = "$note" ] && continue
        if [ "$dry" -eq 1 ]; then echo "  would push $key ($name): \"$note\""; pushed=$((pushed+1)); continue; fi
        local body; body="$(jq -n --arg c "$note" '{comment: $c}')"
        local r; r="$(printf 'url = "%s/v10/projects/%s/env/%s%s"\nheader = "Authorization: Bearer %s"\nheader = "Content-Type: application/json"\nrequest = "PATCH"\ndata = @-\nwrite-out = "\\n%%{http_code}"\nsilent\n' "$VERCEL_API" "$id" "$eid" "${vercel_team:+?teamId=$vercel_team}" "$vercel_token" | curl --config - --data-binary "$body" 2>/dev/null)"
        [ "$(printf '%s' "$r" | tail -n1)" = "200" ] && { echo "  pushed $key ($name)"; pushed=$((pushed+1)); } || echo "  [WARN] $key ($name): PATCH answered HTTP $(printf '%s' "$r" | tail -n1)"
      done < <(printf '%s\n' "$envs" | jq -c --arg k "$key" 'select(.key == $k)')
    done < <(parse_example "$file")
  done
  [ "$pushed" -gt 0 ] && echo "RESULT: $( [ "$dry" -eq 1 ] && echo DRY-RUN || echo PUSHED) $pushed$( [ "$over" -gt 0 ] && echo " ($over over the cap)")" || echo "RESULT: UNCHANGED"; exit 0
}

# --- add / doc ---------------------------------------------------------------------------------------------

parse_key_flags() { # sets key targets sensitive gh_kind ci cloud optional note
  key=""; targets=""; sensitive=0; gh_kind=""; ci=0; cloud=0; optional=0; note=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --targets)   targets="${2:-}"; shift 2 ;;
      --sensitive) sensitive=1; shift ;;
      --github)    gh_kind="${2:-}"; ci=1; shift 2 ;;
      --ci)        ci=1; shift ;;
      --cloud)     cloud=1; shift ;;
      --optional)  optional=1; shift ;;
      --note)      note="${2:-}"; shift 2 ;;
      --*)         die "$verb: unknown flag $1" ;;
      *)           [ -z "$key" ] && key="$1" || die "$verb: unexpected argument $1"; shift ;;
    esac
  done
  [ -n "$key" ] || die "usage: env.sh $verb KEY [--targets production,preview,development] [--sensitive] [--github secret|variable] [--ci] [--cloud] [--optional] [--note \"…\"]"
  [[ "$key" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || die "not a variable name: $key"
  case "$gh_kind" in ""|secret|variable) : ;; *) die "--github must be secret|variable" ;; esac
  [ "$ci" -eq 0 ] || [ -n "$gh_kind" ] || gh_kind="secret"
  for t in ${targets//,/ }; do case "$t" in production|preview|development) : ;; *) die "--targets: unknown target $t" ;; esac; done
}
suffix_for() { # targets ci cloud [optional] → csv suffix or ""
  local s="$1"; [ "$2" -eq 1 ] && s="${s:+$s,}ci"; [ "$3" -eq 1 ] && s="${s:+$s,}cloud"; [ "${4:-0}" -eq 1 ] && s="${s:+$s,}optional"; printf '%s' "$s"
}
example_block() { # key note suffix
  echo "# ${2:-TODO: note}${3:+  [$3]}"; echo "${1}="
}
cmd_doc() {
  parse_key_flags "$@"
  local suffix; suffix="$(suffix_for "$targets" "$ci" "$cloud" "$optional")"
  echo "=== .env.example block for $key (append to ${MANIFESTS[0]##*|}; a monorepo appends it to the app's own) ==="
  echo; example_block "$key" "$note" "$suffix"; echo
  echo "=== the audit lines this clears, once the value exists where the suffix says ==="
  local vt; vt="$(vercel_targets_of "$suffix")"
  [ -z "$vt" ] || echo "  Vercel: $key on [$vt] for every project in deploy.projects — dashboard, or: printf '%s' \"\$V\" | .icm/scripts/env.sh add $key --targets $vt"
  [ "$ci" -eq 0 ]    || echo "  GitHub Actions: $key as a ${gh_kind:-secret} — printf '%s' \"\$V\" | .icm/scripts/env.sh add $key --ci --github ${gh_kind:-secret}"
  [ "$optional" -eq 0 ] || echo "  optional: absent everywhere is fine — the code's default applies; the targets (if any) say where it goes when set"
  [ "$cloud" -eq 0 ] || echo "  Claude cloud panel: set $key in the environment's variables (claude.ai/code → the environment) — by hand, nothing can write it"
  echo "  code: process.env.$key is declared once the block above is committed"
  echo "The value stays with the human — nothing here asks for it."
  echo "RESULT: DOC"; exit 0
}
cmd_add() {
  parse_key_flags "$@"
  local suffix; suffix="$(suffix_for "$targets" "$ci" "$cloud")"
  local vt; vt="$(vercel_targets_of "$suffix")"
  [ -n "$targets" ] || [ "$ci" -eq 1 ] || [ "$cloud" -eq 1 ] || targets="production,preview,development"
  [ -n "$targets" ] && vt="$targets"
  local value=""
  if [ ! -t 0 ]; then IFS= read -r -d '' value || true; fi
  value="${value%$'\n'}"
  local team; team="$(deploy_team)"
  if [ -z "$value" ]; then
    echo "No value on stdin — nothing created. The exact commands, for a human with the value:"
    for m in "${MANIFESTS[@]}"; do IFS='|' read -r name path _ <<<"$m"; [ "$name" = "(root)" ] && continue
      for t in ${vt//,/ }; do echo "  (cd ${path:-.} && printf '%s' \"\$VALUE\" | vercel env add $key $t${sensitive:+ --sensitive}${team:+ --scope $team})"; done; done
    [ "$ci" -eq 0 ] || echo "  printf '%s' \"\$VALUE\" | gh ${gh_kind} set $key"
    [ "$cloud" -eq 0 ] || echo "  set $key in the Claude cloud environment panel by hand"
    echo "  then append to .env.example:"; example_block "$key" "$note" "$suffix" | sed 's/^/    /'
    echo "RESULT: SKIP (no value on stdin)"; exit 0
  fi
  local added=()
  if [ -n "$vt" ] && vercel_declared; then
    command -v vercel >/dev/null 2>&1 || die "vercel CLI not found — it is the only writer of Vercel variables here"
    vercel_require "creating $key"
    for m in "${MANIFESTS[@]}"; do IFS='|' read -r name path _ <<<"$m"
      for t in ${vt//,/ }; do
        if ( cd "${path:-.}" && printf '%s' "$value" | VERCEL_TOKEN="$vercel_token" vercel env add "$key" "$t" $( [ "$sensitive" -eq 1 ] && echo --sensitive ) ${team:+--scope "$team"} --yes >/dev/null 2>&1 ); then added+=("vercel/$name/$t")
        else echo "  [WARN] vercel env add $key $t failed for $name (already exists? not linked?) — nothing echoed"; fi
      done
    done
  fi
  if [ "$ci" -eq 1 ]; then
    command -v gh >/dev/null 2>&1 || die "gh CLI not found — it is the only writer of Actions secrets/variables here"
    if printf '%s' "$value" | gh "$gh_kind" set "$key" >/dev/null 2>&1; then added+=("github/$gh_kind"); else echo "  [WARN] gh $gh_kind set $key failed"; fi
  fi
  [ "$cloud" -eq 0 ] || echo "  [checklist] set $key in the Claude cloud environment panel by hand — nothing can write it"
  for m in "${MANIFESTS[@]}"; do f="${m##*|}"; [ -f "$f" ] || : > "$f"; grep -qE "^${key}=" "$f" || { append_block "$f" "$key" "${note:-TODO: note}" "$suffix"; echo "  documented $key in $f"; }; done
  unset value
  [ "${#added[@]}" -gt 0 ] && echo "RESULT: ADDED $(printf '%s ' "${added[@]}" | sed 's/ $//')" || echo "RESULT: SKIP (nothing created — see the warnings)"; exit 0
}

case "$verb" in
  audit)      cmd_audit "$@" ;;
  init)       cmd_init "$@" ;;
  pull)       cmd_pull "$@" ;;
  push-notes) cmd_push_notes "$@" ;;
  add)        cmd_add "$@" ;;
  doc)        cmd_doc "$@" ;;
esac
