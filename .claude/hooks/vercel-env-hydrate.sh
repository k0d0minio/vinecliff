#!/usr/bin/env bash
# vercel-env-hydrate.sh — canonical estate hook (icm-board _system/template/claude/hooks/).
#
# The cloud half of the estate's Vercel env system (epic vercel-env-system). On Jamie's
# machine `_system/scripts/vercel-env.sh pull` writes each app's `.env.local` from
# Vercel; a Claude cloud session has neither that script nor `projects/`, and starts with
# no environment at all. This hook is that flow, reduced to one repo and run at session
# start: link this directory to its Vercel project, pull the values, and interleave the
# notes its own committed `.env.example` already carries.
#
# It is inert unless a session hands it a token. The per-repo cloud environment panel
# sets one variable — plain `VERCEL_TOKEN`, team-scoped, pasted once and never touched
# again — and everything else is worked out here, so changing a variable in Vercel is
# enough for the next cloud session to have it. Nothing else about the panel is
# configuration this repo has to remember.
#
# Deliberately keyed on plain `VERCEL_TOKEN` and nothing else. Jamie's machine exports
# the per-team names (`VERCEL_TOKEN_KODOMINIO` and its siblings, see the registry's
# `teams` block), so a local session leaves this hook asleep and the richer `.env.local`
# that `vercel-env.sh pull` wrote is never overwritten by the thinner one here.
# `VERCEL_ENV_HYDRATE=0` switches it off outright.
#
# What it will not do:
#
#   * create a Vercel project. `vercel link --yes` creates whatever name it is handed
#     (verified in the CLI's own source, 54.18.6: `inputProject` returns the *name* when
#     no project matches), and the estate is already retiring eight orphans. So the
#     project is never guessed from the directory name — it is read back from Vercel by
#     this repo's git remote, `GET /v9/projects?repoUrl=…`, which is the same lookup the
#     CLI's own cross-team search uses. No match means no link and no session noise.
#   * write a credential anywhere git can see it. `.env.local` that its repo does not
#     ignore is refused before the pull, not cleaned up after it.
#   * leave the working tree dirty. `vercel env pull` appends `.env*` to the `.gitignore`
#     of the directory it runs in, unprompted — ten files across seven repos the first
#     time the estate flow ran — and `.env*` hides the `.env.example` this system reads.
#     The file is held across both CLI calls and put back.
#   * block a session. Every failure path prints at most one line and exits 0: no token,
#     no remote, no project, no network, no CLI. A session that cannot reach Vercel is a
#     session that carries on.
#
# It pulls `production` by default. That is Jamie's call (2026-09-08) and it follows how
# the estate is actually configured: almost nothing runs locally, and **every one of the
# 464 keys documented across the kodominio estate is targeted at production** — only six
# repos scope anything to `development` at all, so a development pull would hand most
# sessions an empty file. `VERCEL_ENV_TARGET=preview|development` overrides it per panel.
# This is deliberately *not* what `vercel-env.sh pull` writes locally, which is still
# `development`: the local file serves a machine that rarely runs the apps, the cloud file
# serves the session that does.
#
# Two things follow from pulling production, both worth knowing rather than guarding
# against here. A cloud session's `.env.local` holds live production configuration, so
# whatever that session runs talks to production — which is the point, and is why the file
# is refused unless the repo ignores it. And it holds rather less than the manifest lists:
# Vercel never reads a `type: sensitive` variable back, and 248 of those 464 keys are
# sensitive — every `*_SECRET`, every Neon-injected `POSTGRES_*` alias, `RESEND_API_KEY`,
# `AUTH_SECRET`. The keys that would hurt most stay in Vercel, by Vercel's design and not
# by anything this hook does. An empty or partial result is reported as the ordinary thing
# it is, with the reason, rather than looking like a broken hook. The panel checklist
# (`.icm/docs/2026-09-08-vercel-cloud-panel-checklist.md` in icm-board) carries the
# per-repo reading.
#
# A monorepo whose remote maps to several Vercel projects cannot be resolved from the
# remote alone; the hook names the candidates and hydrates nothing until the panel sets
# `VERCEL_PROJECT` to one of them.
#
# Invoked by `session-start.sh`, not by `settings.json`: the estate's settings files are
# 16-of-25 divergent and hand-owned, while `session-start.sh` is byte-identical in every
# repo that has it and already registered everywhere. Riding the registration it has is
# one canonical file to fan out instead of two dozen policy edits.
#
# Panel variables, all optional except the first:
#   VERCEL_TOKEN         team-scoped token. Absent -> the hook does nothing at all.
#   VERCEL_PROJECT       project name, when the remote maps to more than one.
#   VERCEL_ENV_TARGET    production (default) | preview | development.
#   VERCEL_ENV_HYDRATE   0 to disable.
#   VERCEL_ENV_MAX_AGE   seconds before a re-hydrate; default 3600, 0 to always pull.

set -uo pipefail

[[ "${VERCEL_ENV_HYDRATE:-1}" == "0" ]] && exit 0

TOKEN="${VERCEL_TOKEN:-}"
[[ -n "$TOKEN" ]] || exit 0

ROOT="${CLAUDE_PROJECT_DIR:-$PWD}"
TARGET="${VERCEL_ENV_TARGET:-production}"
WANT="${VERCEL_PROJECT:-}"
MAX_AGE="${VERCEL_ENV_MAX_AGE:-3600}"
[[ "$MAX_AGE" =~ ^[0-9]+$ ]] || MAX_AGE=3600

say() { printf 'Vercel env: %s\n' "$*"; }

for dep in vercel curl jq git awk; do
  command -v "$dep" >/dev/null 2>&1 || {
    say "\$VERCEL_TOKEN is set but $dep is not installed — nothing hydrated."
    exit 0
  }
done

git -C "$ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1 || exit 0

# The token never reaches argv or a temp file: curl reads its own config from stdin, and
# printf is a builtin. Same idiom as _system/scripts/vercel-env.sh.
api() {
  printf 'url = "%s"\nheader = "Authorization: Bearer %s"\n' "$1" "$TOKEN" \
    | curl -sS --config - --max-time 20 2>/dev/null
}

# Which repo Vercel knows this as. Both remote shapes git hands out normalise to the
# https form the API indexes projects by.
remote=$(git -C "$ROOT" remote get-url origin 2>/dev/null) || remote=""
if [[ -z "$remote" ]]; then
  say "no \`origin\` remote here, so there is no way to ask Vercel which project this is."
  exit 0
fi
repo_url="${remote%.git}"
case "$repo_url" in
  ssh://git@*) repo_url="https://${repo_url#ssh://git@}" ;;
  git@*:*)     host="${repo_url#git@}"; repo_url="https://${host/://}" ;;
esac
repo_label="${repo_url#https://}"

encoded=$(jq -rn --arg u "$repo_url" '$u | @uri')
projects_json=$(api "https://api.vercel.com/v9/projects?repoUrl=$encoded&limit=100")
if ! jq -e '.projects' >/dev/null 2>&1 <<<"${projects_json:-}"; then
  why=$(jq -r '.error.message // empty' <<<"${projects_json:-}" 2>/dev/null)
  say "could not ask Vercel about $repo_label — ${why:-no answer from the API}. Nothing hydrated."
  exit 0
fi

mapfile -t matches < <(
  jq -r --arg want "$WANT" '
    .projects
    | map(select($want == "" or .name == $want))
    | .[] | [.name, (.rootDirectory // "." | if . == "" then "." else . end), .accountId]
    | @tsv' <<<"$projects_json"
)

if (( ${#matches[@]} == 0 )); then
  if [[ -n "$WANT" ]]; then
    say "\$VERCEL_PROJECT is '$WANT', which is not one of the projects connected to $repo_label."
  else
    say "no Vercel project is connected to $repo_label — nothing to hydrate."
  fi
  exit 0
fi

if (( ${#matches[@]} > 1 )); then
  # A monorepo. Guessing which app a session is "in" from a repo-root cwd would be
  # inventing an answer; the panel says which, once.
  names=$(printf '%s\n' "${matches[@]}" | cut -f1 | paste -sd,); names="${names//,/, }"
  say "$repo_label maps to several Vercel projects ($names) — set \$VERCEL_PROJECT in this repo's cloud environment panel to pick one. Nothing hydrated."
  exit 0
fi

IFS=$'\t' read -r project rootdir account <<<"${matches[0]}"

dir="$ROOT"
prefix=""
if [[ "$rootdir" != "." && -n "$rootdir" ]]; then
  rootdir="${rootdir#./}"; rootdir="${rootdir%/}"
  dir="$ROOT/$rootdir"
  prefix="$rootdir/"
fi
if [[ ! -d "$dir" ]]; then
  say "$project has root directory '$rootdir', which does not exist in this checkout. Nothing hydrated."
  exit 0
fi

envfile="$dir/.env.local"

# A session that resumes or compacts re-runs this hook. Values that were pulled minutes
# ago are the same values, and a fresh round trip to Vercel at every resume buys nothing.
if (( MAX_AGE > 0 )) && [[ -f "$envfile" ]] && grep -q '^# Generated by .claude/hooks/vercel-env-hydrate.sh' "$envfile" 2>/dev/null; then
  age=$(( $(date +%s) - $(stat -c %Y "$envfile" 2>/dev/null || echo 0) ))
  if (( age >= 0 && age < MAX_AGE )); then
    say "${prefix}.env.local was hydrated $(( age / 60 ))m ago from $project ($TARGET) — left alone."
    exit 0
  fi
fi

# The link file carries only ids, so an unignored one is untidy rather than unsafe — but
# a cloud session is a tree someone commits from, so it is said once, at the end.
# `check-ignore` is asked about a file inside `.vercel/` rather than the directory itself,
# which a `dir/`-style rule cannot match before the directory exists.
vercel_dir_warning=""
if ! git -C "$ROOT" check-ignore -q "${prefix}.vercel/project.json" 2>/dev/null; then
  vercel_dir_warning=" (${prefix}.vercel is not gitignored here — ids only, but it does not belong in the tree)"
fi

# Refuse before the write, not after it: this file ends up holding every value the app
# has, and `git add -A` does not ask. Repairing the .gitignore of a client repo is that
# repo's business, so this names the fix and stops.
if ! git -C "$ROOT" check-ignore -q "${prefix}.env.local" 2>/dev/null; then
  say "${prefix}.env.local is not gitignored in this repo, and hydrating it would leave live values in the working tree. Add it to .gitignore (with \`!.env.example\` under any \`.env*\` rule) and start a new session."
  exit 0
fi

# `--scope` wants the team slug; the project only gave us its account id.
slug=""
teams_json=$(api "https://api.vercel.com/v2/teams?limit=100")
if jq -e '.teams' >/dev/null 2>&1 <<<"${teams_json:-}"; then
  slug=$(jq -r --arg id "$account" '.teams[]? | select(.id == $id) | .slug' <<<"$teams_json" | head -1)
fi
scope_args=()
[[ -n "$slug" ]] && scope_args=(--scope "$slug")
where="${slug:+$slug/}$project"

# `vercel env pull` appends `.env*` to the .gitignore of the directory it runs in,
# unprompted. `.env*` swallows the `.env.example` this system treats as the manifest, and
# in a cloud session it also leaves a modified file in a tree someone is about to commit
# from. Held here across both CLI calls and put back.
gitignore="$dir/.gitignore"
gi_existed=0; gi_before=""
[[ -f "$gitignore" ]] && { gi_existed=1; gi_before=$(cat "$gitignore"); }
restore_gitignore() {
  if (( gi_existed )); then
    [[ "$(cat "$gitignore" 2>/dev/null)" == "$gi_before" ]] || printf '%s\n' "$gi_before" > "$gitignore"
  elif [[ -f "$gitignore" ]]; then
    rm -f "$gitignore"
  fi
}

linked=""
[[ -f "$dir/.vercel/project.json" ]] && \
  linked=$(jq -r '.projectName // empty' "$dir/.vercel/project.json" 2>/dev/null)

if [[ "$linked" != "$project" ]]; then
  ( cd "$dir" && VERCEL_TOKEN="$TOKEN" vercel link --yes --project "$project" \
      "${scope_args[@]}" </dev/null ) >/dev/null 2>&1
  restore_gitignore
  # Trust, then check: the CLI has been seen to report success and write no link at all
  # (a `.vercel/repo.json` above the directory does it), and `vercel env pull` would then
  # have nothing to read.
  linked=""
  [[ -f "$dir/.vercel/project.json" ]] && \
    linked=$(jq -r '.projectName // empty' "$dir/.vercel/project.json" 2>/dev/null)
  if [[ "$linked" != "$project" ]]; then
    say "could not link this directory to $where — \`vercel link\` wrote no usable .vercel/project.json. Nothing hydrated."
    exit 0
  fi
fi

if ! ( cd "$dir" && VERCEL_TOKEN="$TOKEN" vercel env pull .env.local \
         --environment "$TARGET" --yes "${scope_args[@]}" </dev/null ) >/dev/null 2>&1; then
  restore_gitignore
  say "\`vercel env pull\` failed against $where ($TARGET). Nothing hydrated."
  exit 0
fi
restore_gitignore

if [[ ! -f "$envfile" ]]; then
  say "\`vercel env pull\` reported success against $where but wrote no .env.local."
  exit 0
fi

# The interleave: the manifest's own `#` lines, moved to where the value is. A reduced
# sibling of the one in `_system/scripts/vercel-env.sh pull` — same convention, same
# refusals, without the per-estate counting that flow reports on. It only ever inserts
# lines: anything it does not recognise as `KEY=` passes through exactly as it came,
# because guessing wrong about a value is worse than leaving it plain.
exfile="$dir/.env.example"
[[ -f "$exfile" ]] || exfile=/dev/null

OIDC_NOTE='# Short-lived token the Vercel CLI writes for local OIDC auth against this project.
# Not a project variable, not part of the manifest, and replaced by the next pull.'

ANNOTATE='
FILENAME == exfile {
  line = $0
  sub(/\r$/, "", line)
  if (line ~ /^[[:space:]]*#/) {
    sub(/^[[:space:]]+/, "", line)
    block = (block == "" ? line : block "\n" line)
    next
  }
  if (line ~ /^[[:space:]]*$/) { block = ""; next }
  if (match(line, /^[[:space:]]*(export[[:space:]]+)?[A-Za-z_][A-Za-z0-9_]*[[:space:]]*=/)) {
    k = line
    sub(/^[[:space:]]*/, "", k)
    sub(/^export[[:space:]]+/, "", k)
    sub(/[[:space:]]*=.*$/, "", k)
    # A commented-out assignment is prose about nothing; it is not the note for the key
    # below it, however much the convention says the line above a key is its note.
    if (block ~ /^#[[:space:]]*[A-Za-z_][A-Za-z0-9_]*[[:space:]]*=/) block = ""
    if (block != "") note[k] = block
    block = ""
    next
  }
  block = ""
  next
}
{
  if (!seenkey && $0 ~ /^[[:space:]]*(#|$)/) next
  if (match($0, /^[A-Za-z_][A-Za-z0-9_]*=/)) {
    seenkey = 1
    k = substr($0, 1, RLENGTH - 1)
    n = ""
    if (k == "VERCEL_OIDC_TOKEN") {
      n = oidc
    } else {
      keys++
      if (k in note) {
        n = note[k]
        if (n ~ /^#[[:space:]]*TODO:[[:space:]]*note/) todo++; else noted++
      } else {
        undocumented++
      }
    }
    print ""
    if (n != "") print n
    print $0
    next
  }
  print $0
}
END { printf "\001COUNTS\t%d\t%d\t%d\t%d\n", keys+0, noted+0, todo+0, undocumented+0 }
'

if ! body=$(awk -v exfile="$exfile" -v oidc="$OIDC_NOTE" "$ANNOTATE" "$exfile" "$envfile"); then
  say "hydrated ${prefix}.env.local from $where ($TARGET), but the annotation pass failed — the file is Vercel's, unannotated."
  exit 0
fi
counts="${body##*$'\n'}"
if [[ "$counts" != $'\001COUNTS'* ]]; then
  say "hydrated ${prefix}.env.local from $where ($TARGET), but the annotation pass produced nothing recognisable — left the pulled file as it came."
  exit 0
fi
# A pull that came down with nothing in it leaves the summary line as the whole of awk's
# output, and stripping "everything after the last newline" from a string with no newline
# in it strips nothing at all. Say so explicitly rather than writing the sentinel into
# the file.
if [[ "$body" == *$'\n'* ]]; then body="${body%$'\n'*}"; else body=""; fi
IFS=$'\t' read -r _ n_keys n_noted n_todo n_undoc <<<"$counts"

manifest="this app's .env.example"
[[ "$exfile" == /dev/null ]] && manifest="a .env.example this app does not have"

# Written in place so the permissions the CLI chose are the permissions it keeps, and
# held whole in a variable rather than staged through a second file — a temp file full of
# live values, even one deleted a moment later, is a window this hook does not need.
if ! { cat <<EOF
# Generated by .claude/hooks/vercel-env-hydrate.sh at session start — do not edit.
#
# The values are Vercel's, pulled from $where, $TARGET environment. The notes above each
# key come from $manifest, which is the manifest: a note that is
# wrong or missing gets fixed there, never here.
#
# The whole file is rewritten on every hydrate, so nothing survives in it. Local-only
# overrides belong in .env.development.local, which this hook never touches.
#
# Two absences here are normal rather than broken: a variable Vercel marks sensitive is
# write-only and never comes down at all, and a variable scoped to another environment is
# not part of a $TARGET pull. \`# TODO: note\` means the manifest has not explained that
# key yet; a key with no note at all is one Vercel has and the manifest does not mention.
EOF
     printf '%s\n' "$body"; } > "$envfile"; then
  say "hydrated ${prefix}.env.local from $where ($TARGET) but could not write the annotated file."
  exit 0
fi

if (( n_keys == 0 )); then
  say "${prefix}.env.local hydrated from $where, and $TARGET holds no variables there — an empty file is the honest answer, not a failure. Add $TARGET values in Vercel, or set \$VERCEL_ENV_TARGET in this repo's panel.$vercel_dir_warning"
else
  detail="$n_noted documented"
  (( n_todo > 0 ))  && detail+=", $n_todo still \`# TODO: note\`"
  (( n_undoc > 0 )) && detail+=", $n_undoc not in the manifest"
  say "${prefix}.env.local hydrated from $where ($TARGET) — $n_keys keys, $detail.$vercel_dir_warning"
fi
exit 0
