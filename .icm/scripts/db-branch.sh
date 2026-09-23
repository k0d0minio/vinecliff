#!/usr/bin/env bash
# db-branch.sh — bind a run to its own database: a schema, a container, a Neon branch or a MongoDB database per run (TEMPLATE-OWNED).
#
# Runs are built in parallel, each in its own worktree on its own branch (`_shared/stage-preamble.md`
# → Run-scoped isolation). What that rule does not cover on its own is the database: two runs whose
# migrations both land on the one development database write over each other exactly the way two
# runs in one checkout would. This script gives each run a database of its own, named after the
# slug like everything else the run owns, so a migration applied while building `csv-export` is
# applied to `run_csv_export` and nowhere else.
#
# What "its own" means is the repo's call, in `.icm/project.json` → `database` (lib/project.sh):
#   isolation: none       the default — no isolated database; every verb says SKIP and stops.
#   isolation: schema     one Postgres SCHEMA per run — `run_<slug>` on the database named by the
#                         variable `url_env` (default DATABASE_URL). Needs `psql` and that variable.
#   isolation: container  one local Postgres CONTAINER per run — `icm-db-<slug>` from `image`
#                         (default postgres:16) with database `name` (default app), on a port the
#                         engine picks, bound to 127.0.0.1. Needs `docker` (or `podman`). The
#                         password is generated at `up` and read back from the container at `env`;
#                         it is never written anywhere in the repo.
#   isolation: neon       one Neon BRANCH per run — `run/<slug>`, a copy-on-write child of the
#                         project's production branch (`database.neon.production_branch`) with a
#                         7-day expiry Neon enforces itself, created through lib/neon.sh with the
#                         key `database.neon.api_key_env` names (decision D32). Needs `provider:
#                         neon`, curl and jq — no psql, no docker. The branch's pooled connection
#                         string is read back at `env` and never written anywhere in the repo. A
#                         child of PRODUCTION, never of the UAT branch, so `db-env.sh reset-uat`
#                         is never blocked by a run (uat/CONTEXT.md → The UAT database).
#   isolation: database   one MongoDB DATABASE per run — `run_<slug>` (lib/db-name.mjs normalises
#                         it to MongoDB's rules: `-` → `_`, 63 bytes at most) on the ONE cluster the
#                         variable `url_env` (default MONGODB_URI) points at, beside the repo's
#                         production and shared preview databases (decision D35). Needs `provider:
#                         mongodb`, node and the repo's installed driver (lib/mongo.mjs finds it) —
#                         no new binary. The data is the repo's own: `up` runs
#                         `database.mongodb.migrate_command up`, then `seed_command`, with the name
#                         variable (`mongodb.name_env`, default MONGODB_DATABASE_NAME) set to the
#                         run's database — migrate first, seed second: a seed written against the
#                         head's models (Mongoose's autoIndex builds their indexes) belongs on the
#                         migrated shape. The template never seeds, and nothing is cloned from
#                         production. Before creating it, the cluster's caps are read
#                         (`mongodb.limits` — the shared Atlas tiers cap databases and collections)
#                         and the pipeline's databases counted.
#
# Verbs:
#   status  (default)  what this run is bound to and whether it exists right now.
#   up                 create the schema / start the container (idempotent), and record ONE pointer
#                      line in the run's `run.md` — `- db: schema run_<slug> (via $DATABASE_URL)` —
#                      naming the variable, never its value.
#   env                print the `export` lines a shell evals to work inside the run's database:
#                      `eval "$(.icm/scripts/db-branch.sh <slug> env)"`. ONLY the exports go to
#                      stdout (so the eval is clean); everything else, the verdict included, goes to
#                      stderr. Nothing is written to disk.
#   down               drop the schema (CASCADE) / remove the container / delete the branch / drop
#                      the database, and remove the pointer line. Refuses any name that is not
#                      `run_*` / `icm-db-*` / `run/*` — it only ever drops what `up` made.
#   prove              (isolation: database) the migration proof Build and Release read: on a
#                      freshly re-made, UNSEEDED `run_<slug>` migrated to exactly the base's
#                      migrations, it snapshots the shape (collection list + index specs,
#                      lib/mongo.mjs snapshot) and runs THIS BRANCH'S OWN migrations (the
#                      epoch-form files the base branch does not have, as check-migrations.sh
#                      counts them) up → down → up:
#                        down must bring the shape back to the snapshot before them, and every own
#                        file must export a `down` — only where migrations.reversible is true;
#                        up again must reproduce the shape after them;
#                        and, the runner's records of them forgotten (what a re-stamp does —
#                        check-migrations.sh), up once more must change nothing: the idempotency
#                        a re-stamped migration relies on.
#                      A forward-only repo (reversible false) proves the up and the idempotency.
#                      The seed runs only after a PROVEN, so the run's database is left migrated
#                      and seeded, as `up` leaves it; the proof itself never sees the seed (its
#                      models would build the head's indexes into the "base shape").
#                      The migrate command takes `up [<name>] [--single]` and `down <name>
#                      [--single]`, <name> as the runner records it (the file name after
#                      `<13 digits>-`, without the extension) — ts-migrate-mongoose's, whose runs
#                      follow the STAMP, not the file: `up <name>` applies every pending
#                      migration stamped at or before it, `down <name>` reverts every applied one
#                      stamped at or after it, `--single` exactly the one named. So where one of
#                      the branch's own migrations is stamped before one of the base's
#                      (migrations.out_of_order, a rebase), the base's shape is built one base
#                      migration at a time past that stamp (`up <name> --single`), and the round
#                      trip reverts the branch's own one at a time, newest first (`down <name>
#                      --single`) — never a base migration. In order, neither needs `--single`.
#
# It adopts a run, it never makes one: the slug must already be a live run (`.icm/runs/<slug>/`),
# the way every adopting stage resolves it (`resolve-run.sh`). Nothing here reaches outside the
# repo except the database engine itself. It never runs a migration — the repo's own migration
# tool does that, pointed at the run by `env`. Production is never a target: the variable it reads
# is the development one the repo names.
#
# Usage: .icm/scripts/db-branch.sh <slug> [status|up|env|down|prove] [--base <ref>]   (isolation none|schema|container|neon|database)
# Verdict (stdout, last line — stderr for `env`):
#   RESULT: BOUND      exit 0  — the run's database exists (after `up`, or found by `status`)
#   RESULT: ABSENT     exit 0  — `status`: nothing bound yet (run `up`)
#   RESULT: ENV        exit 0  — `env` printed the exports (on stderr, so `eval` sees only the exports)
#   RESULT: RELEASED   exit 0  — `down` removed the run's database (or found none)
#   RESULT: PROVEN     exit 0  — `prove`: the round trip restored the shape and a second up changed nothing
#   RESULT: UNPROVEN n exit 2  — `prove`: a down missing or not restoring, an up not reproducing or not idempotent
#   RESULT: SKIP       exit 0  — isolation is `none`, or the engine/variable this mode needs is missing
#                               (`prove`: not isolation database, or no migrations of this branch's own)
#   (exit 1: usage, no such run, the engine refused, a seed or migrate command failed)
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$repo_root"
die() { echo "error: $*" >&2; exit 1; }
command -v jq >/dev/null 2>&1 || die "jq not found"

# shellcheck source=lib/project.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/project.sh"

slug=""; verb="status"; base=""
while [ $# -gt 0 ]; do
  case "$1" in
    status|up|env|down|prove) verb="$1"; shift ;;
    --base) base="${2:-}"; [ -n "$base" ] || die "--base needs a ref"; shift 2 ;;
    -h|--help) sed -n '2,99p' "${BASH_SOURCE[0]}"; exit 0 ;;
    --*) die "unknown flag: $1" ;;
    *) [ -z "$slug" ] && slug="$1" || die "unexpected argument: $1"; shift ;;
  esac
done
[ -n "$slug" ] || die "usage: db-branch.sh <slug> [status|up|env|down|prove] [--base <ref>]"
printf '%s' "$slug" | grep -Eq '^[a-z0-9][a-z0-9-]*$' || die "slug '$slug' is not kebab-case"
[ -d ".icm/runs/$slug" ] || die "no live run .icm/runs/$slug/ — db-branch adopts a run, it never creates one (resolve-run.sh $slug first)"
run_md=".icm/runs/$slug/run.md"

# `env` keeps stdout for the exports alone; every other line of every verb goes through here.
say() { if [ "$verb" = "env" ]; then echo "$*" >&2; else echo "$*"; fi; }
verdict() { say "RESULT: $1"; exit "${2:-0}"; }

isolation="$(database_isolation)"
url_env="$(database_url_env)"
image="$(database_image)"
dbname="$(database_name)"

schema="run_$(printf '%s' "$slug" | tr '-' '_')"
schema="${schema:0:63}"                                 # a Postgres identifier is at most 63 bytes
container="icm-db-$slug"
neon_branch_name="run/$slug"
pointer_schema="- db: schema $schema (via \$$url_env)"
pointer_container="- db: container $container ($image, database $dbname)"
pointer_neon="- db: neon $neon_branch_name (via \$$url_env)"

record_pointer() { # <line>
  [ -f "$run_md" ] || return 0
  grep -qxF -- "$1" "$run_md" || printf '%s\n' "$1" >> "$run_md"
}
remove_pointer() {
  [ -f "$run_md" ] || return 0
  if grep -q '^- db: ' "$run_md"; then
    tmp="$(mktemp)"; grep -v '^- db: ' "$run_md" > "$tmp" || true; cat "$tmp" > "$run_md"; rm -f "$tmp"
  fi
}

say "run:        $slug"
say "isolation:  $isolation  (.icm/project.json → database.isolation)"
if [ "$verb" = prove ] && [ "$isolation" != database ]; then
  say "prove is the MongoDB round trip (isolation: database) — on this engine the migration is exercised by the repo's own tool inside the run's database"
  verdict SKIP
fi

case "$isolation" in
  none)
    say "no isolated database is declared for this repo — migrations run against the shared development database, or not at all in a session"
    say "(declare database.isolation as \"neon\", \"schema\", \"container\" or \"database\" in .icm/project.json to bind one per run)"
    verdict SKIP ;;

  neon)
    # shellcheck source=lib/neon.sh
    source "$(dirname "${BASH_SOURCE[0]}")/lib/neon.sh"
    say "branch:     $neon_branch_name  in Neon project ${neon_project:-<undeclared>} (a child of $(neon_production_branch), 7-day expiry)"
    neon_declared || { say "database.provider is not neon, or database.neon.project_id is empty — /setup declares it"; verdict SKIP; }
    command -v curl >/dev/null 2>&1 || { say "curl not found — the neon engine needs it"; verdict SKIP; }
    [ -n "$neon_key" ] || { say "\$$neon_key_name is unset in this environment — nothing can be read or created (export it; never in git)"; verdict SKIP; }
    neon_load_branches || die "could not read Neon project $neon_project via \$$neon_key_name — .icm/scripts/lib/neon.sh --check says why"
    bid="$(neon_branch_id "$neon_branch_name")"
    case "$verb" in
      status)
        if [ -n "$bid" ]; then say "state:      present ($bid)"; verdict BOUND; else say "state:      absent — run: .icm/scripts/db-branch.sh $slug up"; verdict ABSENT; fi ;;
      up)
        if [ -z "$bid" ]; then
          parent="$(neon_branch_id "$(neon_production_branch)")"
          [ -n "$parent" ] || parent="$(neon_default_branch_id)"
          [ -n "$parent" ] || die "no branch named $(neon_production_branch) in Neon project $neon_project (database.neon.production_branch)"
          bid="$(neon_create_branch "$neon_branch_name" "$parent" "$(neon_now_plus_days 7)")"
          [ -n "$bid" ] || die "Neon answered the create without a branch id"
          neon_wait_ready "$bid" 90 || say "note: $neon_branch_name is still starting — the exports from \`env\` are correct; the first connection may wait a moment"
        fi
        record_pointer "$pointer_neon"
        say "state:      present ($bid) — a copy of $(neon_production_branch) as of now, expiring in 7 days unless \`down\` comes first"
        say "next:       eval \"\$(.icm/scripts/db-branch.sh $slug env)\"   then run the repo's migrations inside it"
        verdict BOUND ;;
      env)
        [ -n "$bid" ] || { say "$neon_branch_name does not exist yet — run \`up\` first"; verdict SKIP; }
        url="$(neon_connection_uri "$bid")"
        [ -n "$url" ] || die "Neon answered without a connection string for $neon_branch_name"
        printf 'export ICM_DB_NEON_BRANCH=%q\n' "$neon_branch_name"
        printf 'export %s=%q\n' "$url_env" "$url"
        printf 'export ICM_DB_URL_PRISMA=%q\n' "$url"
        verdict ENV ;;
      down)
        if [ -n "$bid" ]; then neon_delete_branch "$bid" "$neon_branch_name"; say "state:      deleted ($bid)"; else say "state:      absent"; fi
        remove_pointer
        verdict RELEASED ;;
    esac ;;

  database)
    here_lib="$(dirname "${BASH_SOURCE[0]}")/lib"
    [ "$(database_provider)" = mongodb ] || { say "database.isolation is database but database.provider is not mongodb — /setup declares it"; verdict SKIP; }
    command -v node >/dev/null 2>&1 || { say "node not found — the database engine runs lib/mongo.mjs with the repo's own driver"; verdict SKIP; }
    [ -n "${!url_env:-}" ] || { say "\$$url_env is unset in this environment — the cluster URI (env.sh pull, or export it; never in git)"; verdict SKIP; }
    name_env="$(mongo_name_env)"; seed_cmd="$(mongo_seed_command)"; migrate_cmd="$(mongo_migrate_command)"
    db="$(node "$here_lib/db-name.mjs" run "$slug")" || die "could not derive the run's database name"
    say "database:   $db  on the cluster \$$url_env names (the app reads its name from \$$name_env)"
    mongo() { node "$here_lib/mongo.mjs" "$@"; }
    # Seed and migrate output is the repo's; a connection string in it never reaches the transcript.
    redact() { sed -E 's#mongodb(\+srv)?://[^[:space:]"]*#mongodb://<redacted>#g'; }
    in_db() { # <command...> — the repo's own command, pointed at the run's database
      ( export "$name_env=$db"; set -o pipefail; bash -c "$*" 2>&1 | redact >&2 ) || die "failed in $db: $*"
    }
    present() { local l; l="$(mongo list)" || die "could not list the cluster's databases (lib/mongo.mjs check says why)"; printf '%s' "$l" | jq -e --arg n "$db" 'any(.[]; .name == $n)' >/dev/null; }
    pointer_database="- db: database $db (via \$$url_env, \$$name_env)"
    need_commands() { [ -n "$seed_cmd" ] && [ -n "$migrate_cmd" ] || die "database.mongodb.seed_command and migrate_command must both be declared (/setup asks)"; }
    check_caps() { # before a database is created: the cluster's caps, and how many are the pipeline's
      if ! present; then
        dbs="$(mongo list)" || die "could not list the cluster's databases"
        nd="$(printf '%s' "$dbs" | jq 'length')"; nc="$(printf '%s' "$dbs" | jq '[.[].collections] | add // 0')"
        np="$(printf '%s' "$dbs" | jq --arg a "$(mongo_preview_name)" --arg b "$(mongo_production_name)" '[.[] | select((.name | test("^(run|preview)_")) and .name != $a and .name != $b)] | length')"
        like="$(printf '%s' "$dbs" | jq --arg a "$(mongo_preview_name)" --arg b "$(mongo_production_name)" '[.[] | select(.name == $a or .name == $b) | .collections] | max // 0')"
        ld="$(mongo_limit_databases)"; lc="$(mongo_limit_collections)"
        say "cluster:    $nd database(s) (cap ${ld/#0/none}) · $nc collection(s) (cap ${lc/#0/none}) · $np pipeline database(s) (run_* and preview_*) · a new one adds ~$like"
        [ "$ld" -eq 0 ] || [ $((nd + 1)) -le "$ld" ] || die "creating $db would pass the cluster's database cap ($ld) — db-env.sh prune --apply first, or raise database.mongodb.limits"
        [ "$lc" -eq 0 ] || [ $((nc + like)) -le "$lc" ] || die "creating $db (~$like collections) would pass the cluster's collection cap ($lc) — db-env.sh prune --apply first, or raise database.mongodb.limits"
      fi
    }
    case "$verb" in
      status)
        if present; then say "state:      present"; verdict BOUND; else say "state:      absent — run: .icm/scripts/db-branch.sh $slug up"; verdict ABSENT; fi ;;
      up)
        need_commands; check_caps
        in_db "$migrate_cmd up"
        in_db "$seed_cmd"
        record_pointer "$pointer_database"
        say "state:      present — migrated up, then seeded by the repo's seed command"
        say "next:       eval \"\$(.icm/scripts/db-branch.sh $slug env)\"   then work inside it"
        verdict BOUND ;;
      env)
        present || say "note: $db does not exist yet — run \`up\` first; the export below is still correct"
        printf 'export %s=%q\n' "$name_env" "$db"
        verdict ENV ;;
      down)
        case "$db" in run_*) ;; *) die "refusing to drop '$db' — only a run_* database made by up" ;; esac
        if present; then mongo drop "$db" >/dev/null || die "could not drop $db"; say "state:      dropped"; else say "state:      absent"; fi
        remove_pointer
        verdict RELEASED ;;
      prove)
        [ "$(migrations_stamp)" = epoch ] || say "note: migrations.stamp is $(migrations_stamp) — the proof reads the epoch form (<13 digits>-<name>.$(migrations_extension)) a MongoDB runner writes"
        [ -n "$base" ] || base="origin/$(pipeline_base_branch)"
        git rev-parse --verify --quiet "${base}^{commit}" >/dev/null || die "base ref '$base' does not resolve — git fetch origin first, or pass --base <ref>"
        ext="$(migrations_extension)"; re="^[0-9]{13}-.+\.${ext//./\\.}$"
        own=(); on_base_all=()
        while IFS= read -r dir; do
          [ -n "$dir" ] || continue; dir="${dir%/}"
          on_base="$(git ls-tree -r --name-only "$base" -- "$dir/" 2>/dev/null | sed -E 's:^.*/::' | grep -E "$re" | sort || true)"
          here_now="$( [ -d "$dir" ] && find "$dir" -maxdepth 1 -type f -printf '%f\n' | grep -E "$re" | sort || true)"
          while IFS= read -r f; do [ -n "$f" ] && own+=("$dir/$f"); done < <(comm -13 <(printf '%s\n' "$on_base") <(printf '%s\n' "$here_now") | grep . || true)
          while IFS= read -r f; do [ -n "$f" ] && on_base_all+=("$f"); done < <(printf '%s\n' "$on_base" | grep . || true)
        done < <(migrations_paths)
        [ "${#own[@]}" -gt 0 ] || { say "no migrations of this branch's own against $base (migrations.path, the epoch form) — nothing to prove"; verdict SKIP; }
        mapfile -t own < <(for f in "${own[@]}"; do printf '%s\t%s\n' "$(basename "$f")" "$f"; done | sort | cut -f2)
        rname() { local b; b="$(basename "$1")"; b="${b#*-}"; printf '%s' "${b%.*}"; }  # the runner's name
        stamp_of() { local b; b="$(basename "$1")"; printf '%s' "${b:0:13}"; }            # the runner's createdAt
        first="$(rname "${own[0]}")"; own_oldest="$(stamp_of "${own[0]}")"
        # The runner orders by stamp. The base's migrations stamped before this branch's oldest go up
        # in one `up <newest of them>`; any stamped at or after it (a rebase over newer base work) go
        # up one at a time, since a bulk `up` would take this branch's own with them.
        base_bulk=""; interleaved=()
        while IFS= read -r f; do
          [ -n "$f" ] || continue
          if [ "$(stamp_of "$f")" \< "$own_oldest" ]; then base_bulk="$f"; else interleaved+=("$f"); fi
        done < <(printf '%s\n' "${on_base_all[@]}" | grep . | sort -u || true)
        base_newest="$base_bulk"; [ "${#interleaved[@]}" -eq 0 ] || base_newest="${interleaved[${#interleaved[@]}-1]}"
        reversible="$(migrations_reversible)"
        say "base:       $base (newest there: ${base_newest:-none})"
        say "own:        ${#own[@]} migration(s): $(for f in "${own[@]}"; do basename "$f"; done | paste -sd' ' -)"
        if [ "${#interleaved[@]}" -gt 0 ]; then
          say "order:      ${#interleaved[@]} of the base's migration(s) stamped at or after this branch's oldest ($(basename "${own[0]}")) — the runner follows the stamp, so the base shape goes up one at a time past it and the round trip reverts this branch's own one at a time (--single)"
        fi
        say "reversible: $reversible (migrations.reversible)"
        fails=()
        if [ "$reversible" = true ]; then
          for f in "${own[@]}"; do
            grep -Eq '(export[^;]*[^a-z_]down[^a-z_]|export default[^;]*[^a-z_]down[^a-z_]|exports\.down|down[[:space:]]*[:=(])' "$f" || fails+=("$(basename "$f"): no down export — reversible: true means every migration carries one")
          done
        fi
        # A fresh run database at exactly the base's shape: dropped (only run_*), migrated through the
        # base's migrations and none of this branch's, and not seeded — the seed's models would build
        # the head's indexes into it.
        if present; then mongo drop "$db" >/dev/null || die "could not drop $db to start the proof clean"; fi
        remove_pointer
        need_commands; check_caps
        [ -z "$base_bulk" ] || in_db "$migrate_cmd up $(rname "$base_bulk")"
        for f in "${interleaved[@]}"; do in_db "$migrate_cmd up $(rname "$f") --single"; done
        record_pointer "$pointer_database"
        down_own() { # this branch's own migrations, and only those, reverted
          if [ "${#interleaved[@]}" -eq 0 ]; then
            ( export "$name_env=$db"; bash -c "$migrate_cmd down $first" 2>&1 | redact >&2 )
          else
            local i
            for (( i=${#own[@]}-1; i>=0; i-- )); do
              ( export "$name_env=$db"; bash -c "$migrate_cmd down $(rname "${own[$i]}") --single" 2>&1 | redact >&2 ) || return 1
            done
          fi
        }
        snap() { mongo snapshot "$db" || die "could not snapshot $db"; }
        diff_of() { diff <(printf '%s' "$1" | jq -S .) <(printf '%s' "$2" | jq -S .) | head -20 | sed 's/^/            /' >&2 || true; }
        s0="$(snap)";                 say "step:       base shape — $(printf '%s' "$s0" | jq 'length') collection(s)"
        in_db "$migrate_cmd up";      s1="$(snap)"; say "step:       up    — $(printf '%s' "$s1" | jq 'length') collection(s)"
        if [ "$reversible" = true ] && [ "${#fails[@]}" -eq 0 ]; then
          if down_own; then
            s2="$(snap)"; say "step:       down  — back to before $first"
            [ "$s2" = "$s0" ] || { fails+=("down does not restore the shape before this branch's migrations (collections or indexes differ)"); diff_of "$s0" "$s2"; }
            in_db "$migrate_cmd up";  s3="$(snap)"; say "step:       up    — again"
            [ "$s3" = "$s1" ] || { fails+=("up after down does not reproduce the shape of the first up"); diff_of "$s1" "$s3"; }
          else
            fails+=("reverting this branch's own migrations failed (\`$migrate_cmd down …\`) — a down is missing or throws")
            in_db "$migrate_cmd up"; s3="$(snap)"
          fi
        else
          s3="$s1"
          [ "$reversible" = true ] || say "step:       down  — not exercised (forward-only repo)"
        fi
        # What a re-stamp does: the runner no longer knows these files, and applies them again.
        names=(); for f in "${own[@]}"; do names+=("$(rname "$f")" "$(basename "$f")"); done
        mongo forget "$db" "$(mongo_migrations_collection)" "${names[@]}" >&2 || die "could not forget the runner's records in $db.$(mongo_migrations_collection)"
        if ( export "$name_env=$db"; bash -c "$migrate_cmd up" 2>&1 | redact >&2 ); then
          s4="$(snap)"; say "step:       up    — re-applied as a re-stamp would"
          [ "$s4" = "$s3" ] || { fails+=("up is not idempotent — re-applying this branch's migrations changed the shape"); diff_of "$s3" "$s4"; }
        else
          fails+=("re-applying this branch's migrations failed — not idempotent, and a re-stamp (check-migrations.sh --apply) would break the deploy")
        fi
        if [ "${#fails[@]}" -gt 0 ]; then
          printf '  UNPROVEN  %s\n' "${fails[@]}"
          say "the run's database is left as the last step left it — db-branch.sh $slug down, then up, before trusting it"
          verdict "UNPROVEN ${#fails[@]}" 2
        fi
        in_db "$seed_cmd"
        say "state:      $db fully migrated, then seeded, as \`up\` leaves it"
        verdict PROVEN ;;
    esac ;;

  schema)
    say "schema:     $schema  on the database named by \$$url_env"
    command -v psql >/dev/null 2>&1 || { say "psql not found — schema isolation needs the Postgres client (brew install libpq / apt install postgresql-client)"; verdict SKIP; }
    url="${!url_env:-}"
    [ -n "$url" ] || { say "\$$url_env is unset in this environment — nothing to bind to (env.sh pull, or export it)"; verdict SKIP; }
    psql_q() { psql "$url" -X -q -v ON_ERROR_STOP=1 -At "$@"; }
    exists() { [ "$(psql_q -c "SELECT 1 FROM information_schema.schemata WHERE schema_name = '$schema'" 2>/dev/null || true)" = "1" ]; }
    case "$verb" in
      status)
        if exists; then say "state:      present"; verdict BOUND; else say "state:      absent — run: .icm/scripts/db-branch.sh $slug up"; verdict ABSENT; fi ;;
      up)
        psql_q -c "CREATE SCHEMA IF NOT EXISTS \"$schema\"" >/dev/null || die "could not create schema $schema (is \$$url_env a Postgres URL this role may create schemas on?)"
        record_pointer "$pointer_schema"
        say "state:      present (created if it was not)"
        say "next:       eval \"\$(.icm/scripts/db-branch.sh $slug env)\"   then run the repo's migrations inside it"
        verdict BOUND ;;
      env)
        exists || say "note: schema $schema does not exist yet — run \`up\` first; the exports below are still correct"
        sep='?'; case "$url" in *\?*) sep='&' ;; esac
        # libpq (psql, node-postgres, Drizzle over pg) honour `options`; Prisma reads `schema=`.
        printf 'export ICM_DB_SCHEMA=%q\n' "$schema"
        printf 'export PGOPTIONS=%q\n' "-c search_path=$schema"
        printf 'export %s=%q\n' "$url_env" "${url}${sep}options=-c%20search_path%3D${schema}"
        printf 'export ICM_DB_URL_PRISMA=%q\n' "${url}${sep}schema=${schema}"
        verdict ENV ;;
      down)
        case "$schema" in run_*) ;; *) die "refusing to drop '$schema' — only a run_* schema made by up" ;; esac
        psql_q -c "DROP SCHEMA IF EXISTS \"$schema\" CASCADE" >/dev/null || die "could not drop schema $schema"
        remove_pointer
        say "state:      dropped"
        verdict RELEASED ;;
    esac ;;

  container)
    engine=""
    for e in docker podman; do command -v "$e" >/dev/null 2>&1 && { engine="$e"; break; }; done
    say "container:  $container  ($image, database $dbname)"
    [ -n "$engine" ] || { say "neither docker nor podman found — container isolation needs one"; verdict SKIP; }
    running() { [ "$("$engine" inspect -f '{{.State.Running}}' "$container" 2>/dev/null || echo false)" = "true" ]; }
    present() { "$engine" inspect "$container" >/dev/null 2>&1; }
    port_of() { "$engine" port "$container" 5432/tcp 2>/dev/null | head -1 | sed -E 's/.*:([0-9]+)$/\1/'; }
    pw_of()   { "$engine" inspect -f '{{range .Config.Env}}{{println .}}{{end}}' "$container" 2>/dev/null | sed -n 's/^POSTGRES_PASSWORD=//p' | head -1; }
    case "$verb" in
      status)
        if running; then say "state:      running on 127.0.0.1:$(port_of)"; verdict BOUND
        elif present; then say "state:      present but stopped — run: $engine start $container (or \`down\` then \`up\`)"; verdict ABSENT
        else say "state:      absent — run: .icm/scripts/db-branch.sh $slug up"; verdict ABSENT; fi ;;
      up)
        if present && ! running; then "$engine" start "$container" >/dev/null || die "could not start $container"; fi
        if ! present; then
          pw="$(head -c 24 /dev/urandom | od -An -tx1 | tr -d ' \n')"
          "$engine" run -d --name "$container" --label "icm.run=$slug" \
            -e POSTGRES_PASSWORD="$pw" -e POSTGRES_DB="$dbname" -p 127.0.0.1::5432 "$image" >/dev/null \
            || die "could not start $container from $image"
        fi
        i=0
        until "$engine" exec "$container" pg_isready -U postgres >/dev/null 2>&1; do
          i=$((i + 1)); [ "$i" -le 30 ] || die "$container did not become ready in 30s ($engine logs $container)"
          sleep 1
        done
        record_pointer "$pointer_container"
        say "state:      running on 127.0.0.1:$(port_of)"
        say "next:       eval \"\$(.icm/scripts/db-branch.sh $slug env)\"   then run the repo's migrations inside it"
        verdict BOUND ;;
      env)
        running || { say "$container is not running — run \`up\` first"; verdict SKIP; }
        url="postgres://postgres:$(pw_of)@127.0.0.1:$(port_of)/$dbname"
        printf 'export ICM_DB_CONTAINER=%q\n' "$container"
        printf 'export %s=%q\n' "$url_env" "$url"
        printf 'export ICM_DB_URL_PRISMA=%q\n' "$url"
        verdict ENV ;;
      down)
        case "$container" in icm-db-*) ;; *) die "refusing to remove '$container'" ;; esac
        if present; then "$engine" rm -f "$container" >/dev/null || die "could not remove $container"; say "state:      removed"; else say "state:      absent"; fi
        remove_pointer
        verdict RELEASED ;;
    esac ;;
esac
