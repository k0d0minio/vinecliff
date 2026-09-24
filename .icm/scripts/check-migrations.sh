#!/usr/bin/env bash
# check-migrations.sh — are this branch's migrations still newer than main's, and named right? (TEMPLATE-OWNED)
#
# Timestamped migrations are applied in stamp order, and a database that has already applied
# main's newest one will refuse, skip or misorder a migration stamped BEFORE it. That is exactly
# what a run's migration becomes when it was written on Monday and another run's — written on
# Tuesday — merged first: nothing in either diff is wrong, the two never conflict in git, and
# production breaks on the deploy. Runs are built in parallel (`_shared/stage-preamble.md` →
# Run-scoped isolation; `db-branch.sh` gives each its own database), so this is an ordinary
# Tuesday, not an edge case. Build runs this after it merges `origin/main` before the ready flip
# (`stages/03_build/CONTEXT.md` step 10) and Release runs it again after its final merge
# (`stages/04_release/CONTEXT.md` step 7), which is the last moment the answer can change.
#
# Three naming forms are READ, always:
#   V20260922070000104__add_tokens.sql   Flyway-shaped, a UTC MILLISECOND stamp (17 digits) — the
#                                        form every new migration carries (`migrations.stamp:
#                                        "millis"`, the default): two runs stamping in the same
#                                        second still order deterministically, and the `V…__`
#                                        shape is what Flyway, and the sql runners that copy it,
#                                        parse as a version.
#   20260922070000_add_tokens.sql        the legacy second stamp (14 digits) — still read, still
#                                        ordered, still the form a repo may keep by declaring
#                                        `migrations.stamp: "seconds"` in `.icm/project.json`.
#   1782500000000-add-tokens.ts          an EPOCH-MILLISECOND stamp (13 digits) and a dash — the
#                                        form ts-migrate-mongoose, migrate-mongo and their kin
#                                        write (`migrations.stamp: "epoch"`, decision D34). Its
#                                        extension is the repo's (`migrations.extension`: `sql`
#                                        by default, `ts` for a TypeScript runner); the two SQL
#                                        forms are `.sql` by definition. A MongoDB repo's
#                                        migrations are ordered here exactly like SQL ones.
# Which form THIS BRANCH'S OWN migrations must carry is enforced: a local migration in another
# form is MISNAMED, and `--apply` renames it to the declared form with its stamp preserved (a
# second stamp gains `000`; an epoch stamp is the same millisecond with a different face) and
# its tail — name and extension — kept as it was. Migrations `main` already has are never
# judged and never touched.
#
# What it compares, per migrations folder:
#   main's   — the stamped migrations in <base>'s tree (default origin/main), newest = M
#   local    — the ones in the working tree that <base> does not have: this branch's own
#   stale    — a local migration stamped at or before M
# One stale migration re-stamps EVERY local one, in their existing order, one step apart (a
# millisecond in the `millis` and `epoch` forms, a second in the `seconds` form), starting after
# the latest of {now (UTC), M, the newest local stamp}: re-stamping only the stale ones would move
# them past a sibling they were written to run before. A runner that records applied files by
# name (the MongoDB kind) sees a re-stamped file as a NEW migration and runs it again — its
# migrations are idempotent for exactly this reason (references/tools.md in the skill).
#
# It REPORTS by default. `--apply` renames (`git mv` for a tracked file, `mv` otherwise) and
# commits nothing — the stage commits the renames with a message that says what happened. The
# rename is the operator-visible part of this script, and the one thing to know before using it:
#   a database that ALREADY APPLIED a migration under its old stamp — a persistent preview or
#   staging database — does not know the renamed file is the same migration. Production never saw
#   the old name, which is the point; a preview database that did is reset the way the repo says
#   (`_shared/project-rules.md` → The factory), and a run's own `db-branch.sh` database is simply
#   dropped and re-made. The files it renames are listed so that is a decision, not a surprise.
# Anything else in the repo that mentions an old stamp (a snapshot, a journal, a test) is listed
# too — the script renames files, it does not edit them.
#
# Out of order: parallel runs merge in any order, so `migrations.out_of_order` (default true) says
# the repo's tool must accept a migration stamped before one it has already applied. The script
# prints the tool's own setting for that (`migrations.tool`: flyway → `-outOfOrder=true`; prisma,
# drizzle and mongodb → what their ordering actually does) — it configures nothing; the repo's
# tool config is the repo's.
#
# `--new <name>` prints the file name a new migration should have — the declared form, a fresh
# stamp after everything main and this branch already carry, the name snake_case in the SQL forms
# and kebab-case in the epoch form — and with `--apply` creates it empty in the first migrations
# folder (or `--path`). That is how a stage names a migration: never by reading the clock itself.
#
# Where migrations live: `--path <dir>` (repeatable) · else `.icm/project.json` → `migrations.path`
# (a string or an array; the old top-level `migrations_path` is still read) · else every folder
# named `migrations/` that holds a file in one of the three forms. Other schemes — numbered
# (`0007_x.sql`), one folder per migration — are not this script's: it reports SKIP and the
# repo's own tooling owns the ordering.
#
# No network: it reads <base> as it is in the local clone, so fetch first (Build step 10 and
# Release step 7 both do).
#
# Usage: .icm/scripts/check-migrations.sh [--base <ref>] [--path <dir>]... [--apply]
#        .icm/scripts/check-migrations.sh --new <name> [--path <dir>] [--apply]
# Verdict (stdout, last line):
#   RESULT: OK            exit 0  — every local migration is stamped after main's newest, in the declared form
#   RESULT: SKIP          exit 0  — no stamped migrations here (or none of this branch's own)
#   RESULT: STALE <n>     exit 2  — <n> local migration(s) would be re-stamped; re-run with --apply
#   RESULT: MISNAMED <n>  exit 2  — <n> local migration(s) are in the other form; re-run with --apply
#   RESULT: RESTAMPED <n> exit 0  — --apply renamed <n> file(s) with fresh stamps; review, commit, push
#   RESULT: RENAMED <n>   exit 0  — --apply renamed <n> file(s) into the declared form; review, commit, push
#   RESULT: NAMED <file>  exit 0  — --new: the name to use (nothing created)
#   RESULT: CREATED <file> exit 0 — --new --apply: the empty migration file exists; write it, commit it
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$repo_root"
die() { echo "error: $*" >&2; exit 1; }
command -v jq >/dev/null 2>&1 || die "jq not found"

# shellcheck source=lib/project.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/project.sh"

# The base is the branch this run merges into: origin/main, the one long-lived branch (D39).
# --base overrides.
base=""; apply=0; paths=(); new_name=""
while [ $# -gt 0 ]; do
  case "$1" in
    --base)    base="${2:-}"; [ -n "$base" ] || die "--base needs a ref"; shift 2 ;;
    --path)    [ -n "${2:-}" ] || die "--path needs a directory"; paths+=("${2%/}"); shift 2 ;;
    --apply)   apply=1; shift ;;
    --new)     new_name="${2:-}"; [ -n "$new_name" ] || die "--new needs a name"; shift 2 ;;
    -h|--help) sed -n '2,72p' "${BASH_SOURCE[0]}"; exit 0 ;;
    *)         die "unknown argument: $1 (usage: check-migrations.sh [--base <ref>] [--path <dir>]... [--apply] | --new <name> [--path <dir>] [--apply])" ;;
  esac
done

git rev-parse --is-inside-work-tree >/dev/null 2>&1 || die "not a git repository"
[ -n "$base" ] || base="origin/main"
git rev-parse --verify --quiet "${base}^{commit}" >/dev/null \
  || die "base ref '$base' does not resolve — run 'git fetch origin' first, or pass --base <ref>"

# All three forms. A `V` + 14 digits (Flyway with a second stamp) is read as the millis form's
# family; the epoch form is read with the repo's declared extension only, so a `template.ts` or a
# test beside the migrations is never mistaken for one.
form="$(migrations_stamp)"          # millis | seconds | epoch — the form this branch's own must carry
ext="$(migrations_extension)"       # the epoch form's file type (sql by default; ts for a TypeScript runner)
ext_re="$(printf '%s' "$ext" | sed 's/[][\.*^$]/\\&/g')"
stamped="^((V[0-9]{14}([0-9]{3})?__|[0-9]{14}_)[^/]+\.sql|[0-9]{13}-[^/]+\.${ext_re})$"
tool="$(migrations_tool)"
ooo="$(migrations_out_of_order)"

# --- stamp arithmetic: 17 digits ↔ epoch milliseconds, GNU date first, BSD date second -------------
to_epoch() { # YYYYMMDDHHMMSS → epoch seconds
  local t="$1"
  date -u -d "${t:0:4}-${t:4:2}-${t:6:2} ${t:8:2}:${t:10:2}:${t:12:2}" +%s 2>/dev/null \
    || date -u -j -f '%Y%m%d%H%M%S' "$t" +%s 2>/dev/null \
    || die "cannot read '$t' as a UTC timestamp — is it a real date?"
}
to_stamp() { # epoch seconds → YYYYMMDDHHMMSS
  date -u -d "@$1" +%Y%m%d%H%M%S 2>/dev/null || date -u -r "$1" +%Y%m%d%H%M%S
}
stamp_of() { # file name → 17-digit stamp (a second stamp gains 000; an epoch stamp is converted)
  local d
  if printf '%s' "$1" | grep -Eq '^[0-9]{13}-'; then ms_to_stamp "${1:0:13}"; return; fi
  d="${1#V}"; d="${d%%_*}"
  [ "${#d}" -eq 14 ] && d="${d}000"
  printf '%s' "$d"
}
tail_of() { # file name → <name>.<ext> after the stamp and its separator, whichever form
  printf '%s' "$1" | sed -E 's/^[0-9]{13}-//; t; s/^V?[0-9]+_{1,2}//'
}
mention_key() { # file name → the stamp text a snapshot, journal or test would quote
  if printf '%s' "$1" | grep -Eq '^[0-9]{13}-'; then printf '%s' "${1:0:13}"; else stamp_of "$1" | cut -c1-14; fi
}
stamp_to_ms() { local s="$1"; echo $(( $(to_epoch "${s:0:14}") * 1000 + 10#${s:14:3} )); }
ms_to_stamp() { printf '%s%03d' "$(to_stamp $(( $1 / 1000 )))" $(( $1 % 1000 )); }
now_ms() {
  if [ -n "${EPOCHREALTIME:-}" ]; then local s="${EPOCHREALTIME%.*}" f="${EPOCHREALTIME#*.}"; echo $(( s * 1000 + 10#${f:0:3} ))
  else echo $(( $(date -u +%s) * 1000 )); fi
}
form_name() { # <17-digit stamp> <tail> → the file name in the declared form
  case "$form" in
    millis)  printf 'V%s__%s' "$1" "$2" ;;
    seconds) printf '%s_%s' "${1:0:14}" "$2" ;;
    epoch)   printf '%s-%s' "$(stamp_to_ms "$1")" "$2" ;;
  esac
}
in_form() { # file name → 0 when it is in the declared form
  case "$form" in
    millis)  printf '%s' "$1" | grep -Eq '^V[0-9]{17}__' ;;
    seconds) printf '%s' "$1" | grep -Eq '^[0-9]{14}_' ;;
    epoch)   printf '%s' "$1" | grep -Eq '^[0-9]{13}-' ;;
  esac
}
step_ms() { case "$form" in seconds) echo 1000 ;; *) echo 1 ;; esac; }
# The first stamp after <ms>, on the form's grid (a second form lands on a whole second).
next_after() { local ms="$1" step; step="$(step_ms)"; echo $(( (ms / step + 1) * step )); }

# --- where the migrations live ------------------------------------------------------------------------
if [ "${#paths[@]}" -eq 0 ]; then
  mapfile -t paths < <(migrations_paths | sed 's:/*$::' | grep -v '^$' || true)
fi
if [ "${#paths[@]}" -eq 0 ]; then
  # Auto-detect: folders named migrations/ holding a file in one of the three forms — here, or on <base>.
  mapfile -t paths < <(
    {
      git ls-files --cached --others --exclude-standard
      git ls-tree -r --name-only "$base"
    } | grep -E "(^|/)migrations/((V[0-9]{14}([0-9]{3})?__|[0-9]{14}_)[^/]+\.sql|[0-9]{13}-[^/]+\.${ext_re})$" | sed -E 's:/[^/]+$::' | sort -u
  )
fi

# --- the tool's own out-of-order setting, phrased for the tool -----------------------------------------
ooo_note() {
  case "$tool" in
    flyway)  echo "flyway: outOfOrder=$ooo — pass -outOfOrder=$ooo, or flyway.outOfOrder=$ooo in flyway.conf (migrations.out_of_order)" ;;
    prisma)  echo "prisma: pending migrations apply in folder order and an earlier-stamped one merged later is still applied; a checksum mismatch, not an order, is what it refuses (migrations.out_of_order: $ooo is a statement, not a switch)" ;;
    drizzle) echo "drizzle: meta/_journal.json orders by idx — two runs that both generated a migration conflict in the journal, resolved by regenerating on the merged tree, never by hand-editing idx (migrations.out_of_order: $ooo)" ;;
    mongodb) echo "mongodb: applied by the repo's runner (ts-migrate-mongoose / migrate-mongo shape) — applied files are recorded by NAME in a collection and every unrecorded file is applied in stamp order, an older stamp included (migrations.out_of_order: $ooo is a statement, not a switch); a re-stamped file is a NEW name to it — its old record is an orphan the runner prunes and the migration runs again, so every migration must be idempotent" ;;
    *)       echo "sql: applied in stamp order by the repo's own runner (migrations.out_of_order: $ooo — the runner must accept a stamp older than one already applied)" ;;
  esac
}

# --- --new: name (and optionally create) the next migration ----------------------------------------------
if [ -n "$new_name" ]; then
  # The name's own separator follows the form: snake_case beside a SQL stamp, kebab-case beside
  # an epoch one (what the MongoDB runners write). The extension is the form's.
  if [ "$form" = "epoch" ]; then
    tail="$(printf '%s' "$new_name" | tr '[:upper:] _' '[:lower:]--' | sed -E 's/[^a-z0-9-]+/-/g; s/^-+|-+$//g' | sed -E "s/\.${ext_re}\$//")"
    [ -n "$tail" ] || die "'$new_name' leaves no usable name after sanitising"
    tail="$tail.$ext"
  else
    tail="$(printf '%s' "$new_name" | tr '[:upper:] -' '[:lower:]__' | sed -E 's/[^a-z0-9_]+/_/g; s/^_+|_+$//g; s/\.sql$//')"
    [ -n "$tail" ] || die "'$new_name' leaves no usable name after sanitising"
    tail="$tail.sql"
  fi
  dir="${paths[0]:-}"
  [ -n "$dir" ] || die "no migrations folder known — pass --path <dir>, or set migrations.path in .icm/project.json"
  latest="$(now_ms)"
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    ms="$(stamp_to_ms "$(stamp_of "$f")")"; [ "$ms" -le "$latest" ] || latest="$ms"
  done < <( { git ls-tree -r --name-only "$base" -- "$dir/" 2>/dev/null | sed -E 's:^.*/::'; [ -d "$dir" ] && find "$dir" -maxdepth 1 -type f -printf '%f\n'; } | grep -E "$stamped" || true)
  name="$(form_name "$(ms_to_stamp "$(next_after "$latest")")" "$tail")"
  echo "$dir/"
  echo "  form: $form ($tool)"
  echo "  $(ooo_note)"
  if [ "$apply" -eq 1 ]; then
    mkdir -p "$dir"
    [ -e "$dir/$name" ] && die "$dir/$name already exists"
    # An empty file with a two-line comment in the file type's own syntax; the migration's
    # shape (up/down, the runner's imports) is the repo's — its template, its skill.
    case "$name" in
      *.sql) printf -- '-- %s\n-- created by check-migrations.sh --new on %s (UTC)\n\n' "$tail" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$dir/$name" ;;
      *)     printf -- '// %s\n// created by check-migrations.sh --new on %s (UTC)\n\n' "$tail" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$dir/$name" ;;
    esac
    echo "  created  $dir/$name  (empty — write the migration, then commit it with the code)"
    echo "RESULT: CREATED $dir/$name"
  else
    echo "  next migration: $dir/$name   (re-run with --apply to create it)"
    echo "RESULT: NAMED $dir/$name"
  fi
  exit 0
fi

if [ "${#paths[@]}" -eq 0 ]; then
  echo "no stamped migrations (V<17 digits>__<name>.sql, <14 digits>_<name>.sql or <13 digits>-<name>.$ext) in this repo — nothing to order"
  echo "RESULT: SKIP"; exit 0
fi
echo "form: $form ($tool) · $(ooo_note)"

total_stale=0; total_misnamed=0; total_local=0; renamed=0; restamped=0; dirs_seen=0

for dir in "${paths[@]}"; do
  mapfile -t on_main < <(git ls-tree -r --name-only "$base" -- "$dir/" 2>/dev/null \
    | sed -E 's:^.*/::' | grep -E "$stamped" || true)
  here_files=()
  if [ -d "$dir" ]; then
    mapfile -t here_files < <(find "$dir" -maxdepth 1 -type f -printf '%f\n' 2>/dev/null | grep -E "$stamped" || true)
  fi
  [ "${#on_main[@]}" -gt 0 ] || [ "${#here_files[@]}" -gt 0 ] || continue
  dirs_seen=$((dirs_seen + 1))

  # local = in the working tree, not on <base> — ordered by STAMP, not by file name (the two forms
  # do not sort together by name).
  by_stamp() { for f in "$@"; do printf '%s\t%s\n' "$(stamp_of "$f")" "$f"; done | sort | cut -f2; }
  mapfile -t locals < <(comm -23 <(printf '%s\n' "${here_files[@]}" | sort) <(printf '%s\n' "${on_main[@]}" | sort) | grep . || true)
  [ "${#locals[@]}" -eq 0 ] || mapfile -t locals < <(by_stamp "${locals[@]}")
  unmerged="$(comm -13 <(printf '%s\n' "${here_files[@]}" | sort) <(printf '%s\n' "${on_main[@]}" | sort) | grep -c . || true)"

  newest_main=""
  if [ "${#on_main[@]}" -gt 0 ]; then
    mapfile -t on_main_sorted < <(by_stamp "${on_main[@]}")
    newest_main="$(stamp_of "${on_main_sorted[-1]}")"
  fi

  echo "$dir/"
  echo "  on $base: ${#on_main[@]} migration(s)${newest_main:+, newest $newest_main}"
  echo "  this branch's own: ${#locals[@]}"
  [ "$unmerged" -eq 0 ] || echo "  note: $base has $unmerged migration(s) this tree lacks — merge $base in first (Build step 10 / Release step 7a)"

  [ "${#locals[@]}" -gt 0 ] || continue
  total_local=$((total_local + ${#locals[@]}))

  stale=(); misnamed=()
  for f in "${locals[@]}"; do
    if [ -n "$newest_main" ] && [ ! "$(stamp_of "$f")" \> "$newest_main" ]; then stale+=("$f"); fi
    in_form "$f" || misnamed+=("$f")
  done
  for f in "${misnamed[@]}"; do echo "  MISNAMED  $f   (this branch's own must be the $form form)"; done
  for f in "${stale[@]}";    do echo "  STALE     $f   (stamped at or before $newest_main)"; done

  if [ "${#stale[@]}" -eq 0 ] && [ "${#misnamed[@]}" -eq 0 ]; then
    echo "  ok — every local migration is stamped after $base's newest, in the $form form"
    continue
  fi

  rename_one() { # <old> <new>
    if git ls-files --error-unmatch -- "$dir/$1" >/dev/null 2>&1; then git mv -- "$dir/$1" "$dir/$2"; else mv -- "$dir/$1" "$dir/$2"; fi
    echo "  renamed  $1 → $2"
    mentions="$(git grep -l -F -e "$(mention_key "$1")" -- . ":(exclude)$dir/$1" ":(exclude)$dir/$2" 2>/dev/null | head -5 || true)"
    [ -z "$mentions" ] || printf '    also mentions the old stamp: %s\n' "$(printf '%s' "$mentions" | tr '\n' ' ')"
  }

  # Converting a millisecond stamp to the seconds form truncates it: two locals in the same second
  # would land on one stamp and lose their order. That is a re-stamp, not a rename.
  if [ "${#stale[@]}" -eq 0 ] && [ "$form" = "seconds" ]; then
    dup="$(for f in "${locals[@]}"; do stamp_of "$f" | cut -c1-14; done | sort | uniq -d | head -1)"
    if [ -n "$dup" ]; then
      echo "  note: two of this branch's migrations share the second $dup once converted — re-stamping all of them"
      stale=("${locals[@]}")
    fi
  fi

  if [ "${#stale[@]}" -gt 0 ]; then
    # Re-stamp ALL locals, in stamp order, from one step after the latest stamp anything already has.
    total_stale=$((total_stale + ${#locals[@]}))
    latest="$(now_ms)"
    [ -z "$newest_main" ] || { m="$(stamp_to_ms "$newest_main")"; [ "$m" -le "$latest" ] || latest="$m"; }
    m="$(stamp_to_ms "$(stamp_of "${locals[-1]}")")"; [ "$m" -le "$latest" ] || latest="$m"
    next="$(next_after "$latest")"
    for f in "${locals[@]}"; do
      new="$(form_name "$(ms_to_stamp "$next")" "$(tail_of "$f")")"
      while [ -e "$dir/$new" ]; do next="$(next_after "$next")"; new="$(form_name "$(ms_to_stamp "$next")" "$(tail_of "$f")")"; done
      if [ "$apply" -eq 1 ]; then rename_one "$f" "$new"; restamped=$((restamped + 1)); else echo "  would rename  $f → $new"; fi
      next="$(next_after "$next")"
    done
  else
    # Only the form is wrong: keep every stamp, change the shape.
    total_misnamed=$((total_misnamed + ${#misnamed[@]}))
    for f in "${misnamed[@]}"; do
      new="$(form_name "$(stamp_of "$f")" "$(tail_of "$f")")"
      [ -e "$dir/$new" ] && die "$dir/$new already exists — resolve by hand"
      if [ "$apply" -eq 1 ]; then rename_one "$f" "$new"; renamed=$((renamed + 1)); else echo "  would rename  $f → $new"; fi
    done
  fi
done

echo "-------------------------------------------------"
if [ "$dirs_seen" -eq 0 ] || [ "$total_local" -eq 0 ]; then
  echo "no stamped migrations of this branch's own — nothing to order"
  echo "RESULT: SKIP"; exit 0
fi
if [ "$total_stale" -eq 0 ] && [ "$total_misnamed" -eq 0 ]; then
  echo "RESULT: OK"; exit 0
fi
if [ "$apply" -eq 1 ]; then
  echo "renamed, not committed — review 'git status', commit the renames on this branch, push, and"
  echo "reset any database that applied the old names (a run's own: db-branch.sh <slug> down, then up)"
  if [ "$restamped" -gt 0 ]; then echo "RESULT: RESTAMPED $restamped"; else echo "RESULT: RENAMED $renamed"; fi
  exit 0
fi
if [ "$total_stale" -gt 0 ]; then
  echo "main has advanced past this branch's migrations — re-run with --apply to re-stamp them"
  echo "RESULT: STALE $total_stale"; exit 2
fi
echo "this branch's migrations are not in the declared $form form — re-run with --apply to rename them"
echo "RESULT: MISNAMED $total_misnamed"; exit 2
