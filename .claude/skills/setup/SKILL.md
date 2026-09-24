---
name: setup
description: >-
  Set this repo up on the pipeline, or keep it honest — one idempotent house-cleaning command.
  Use for /setup, and for "setup", "set up the pipeline", "is the repo complete", "what is
  missing from .icm", "fill project.json". Runs .icm/scripts/setup.sh, asks only what the report
  left open, writes the project-owned files, re-runs until OK, and stops with the changes on a
  claude/ branch for the operator to merge. Never needs icm-board in view.
---

# /setup — the repo, complete and current, from the pipeline's point of view

Re-run any time, from any harness, in any repo. It does not contain the checks — `.icm/scripts/setup.sh`
does, deterministically — and it does not contain the questions either: the report says what is
open, and this skill asks exactly that, in rounds of at most four, then writes the project-owned
files the answers fill. A maintenance run that changed nothing is a valid outcome and says so.

The argument is: `$ARGUMENTS` — optional; `--template <path|url>` names a template source for
seeding a bare repo (there is **no default source**: a repo the dashboard created already carries
the baseline, and nothing here reaches for `../../_system`). On the operator's machine the source
is icm-board's checkout (`~/Apps/_system/template`); `ICM_TEMPLATE` in the shell names it too.

## Procedure

1. **Run the report.**

   ```bash
   .icm/scripts/setup.sh [--template <path|url>]
   ```

   Read the whole thing. Eleven sections: baseline · formatter exposure · project.json ·
   environment · tickets · raw · runs · knowledge · reporting · workflows · support. `RESULT: OK`
   → say so and stop; there is nothing to ask. `RESULT: GAPS n` → the `[FAIL]` lines are the
   gaps, each with the fix or the question beside it.

2. **Seed what is missing, never overwrite.** For a bare or under-seeded repo, with a template
   source in hand:

   ```bash
   .icm/scripts/setup.sh --fix --template <path|url>
   ```

   `--fix` creates only what is absent (D7 — the same discipline as `icm-check.sh --fix`) and
   writes `.icm/template-version`. A template-owned file that has **diverged** is reported with
   the `icm-sync.sh --apply` command to run from icm-board; never edit a `T` file here — a change
   one is owed is a template change request (`.icm/_shared/template-change.md`: a prompt for
   icm-board, parked as a `found-by: template-change` triage stub, never an edit). Without a
   source the report says `SKIP template (no source)` and every in-repo check still runs.

3. **Ask what the report left open — and only that.** `AskUserQuestion`, rounds of ≤ 4, highest
   leverage first. The questions are the report's `[FAIL]`/`[WARN]` lines for `project.json`
   and `project-rules.md`, in the operator's words, e.g.:
   - "`complexity`: is this a `micro` repo (a one-page site, a script) or `standard`?"
   - "No Slack or email is configured; `github-release` is on for `announce`. Add one? Which
     variables carry it?" (names only — never ask for a value)
   - "`deploy`: which Vercel project(s) does this repo deploy as, on which team, under which
     token *name*? Is `web` the product project and `docs` quiet?"
   - "`health_endpoint`: which URL answers `200` when production is up — one for the repo, or
     one per deploy project when they differ (`https://<production_url>/api/health`, or the
     fail-safe page itself)? `health-check.sh` reads it once after every merge; until it is set
     the read is `SKIP` and nobody is told production is down." Ask it whenever the report
     carries the `health_endpoint empty` line — it is a `[WARN]` for as long as the repo
     deploys somewhere and has no endpoint, so a repo that skipped it is asked again next run.
   - "`required_checks`: which check-run names must be green before a merge?" · "`personas`?"
   - "`migrations`: where do they live, are they reversible, which tool applies them (flyway /
     prisma / drizzle / mongodb / sql), and does that tool accept out-of-order stamps? New ones
     are named `V<17 digits>__<name>.sql` (`stamp: millis`) unless you keep the legacy `seconds`
     form — or, on a MongoDB runner such as ts-migrate-mongoose, `<13 digits>-<name>.ts`
     (`stamp: epoch`, `extension: ts`)."
   - "`database`: does this repo have a database, and where does it live? For a **Neon** project
     (`provider: neon`): the project id (Neon Console → Settings; a Vercel-managed database says
     it under Storage → Open in Neon — an id like `nameless-sea-98952497`, not a secret), the
     NAME of the variable that holds a Neon API key (`NEON_API_KEY` unless you keep another), the
     production branch (`main` unless renamed), and `previews: vercel` when the Vercel
     integration should create a database per preview deployment. With a UAT environment
     declared, also the NAME of the UAT database — `neon.uat_branch` (`uat` by convention; a
     persistent child of production the operator creates) or `mongodb.uat_name`
     (`_shared/promotion.md` → The UAT database). For a **MongoDB** cluster
     (`provider: mongodb`, decision D35) — names only, never a URI: the NAME of the variable
     holding the cluster URI (`url_env`, `MONGODB_URI` unless you keep another), the variable the
     app reads its database name from (`mongodb.name_env`, `MONGODB_DATABASE_NAME`), the names of
     the production and the shared preview databases (`production_name`, `preview_name` — never
     dropped or reset), the repo's own seed and migrate commands (`seed_command`,
     `migrate_command`; the migrate command takes `up [<name>] [--single]` and `down <name>
     [--single]`), the runner's
     collection if not `migrations`, the cluster's caps (`limits` — 100 databases / 500
     collections on a shared Atlas tier, 0 for uncapped; `name_bytes` 38 there, 63 on a
     dedicated M10+ cluster), and `previews: branch` when each
     preview should read its own `preview_<branch>` (the app derives it; one flag on the Preview
     target switches it on). Isolation for a run: `neon` (one Neon branch per run — curl and the
     key, no psql or docker), `database` (one MongoDB database per run, `run_<slug>`, on the
     repo's cluster — node and its installed driver), `schema` (one Postgres schema per run on
     the variable `url_env` names), `container` (one local Postgres per run), or `none` for a
     repo without a database. The ids and names go in `project.json`; the key's and the URI's
     values never do."
   - "`security.audit_command`: an npm/pnpm/yarn lockfile is audited automatically — another
     ecosystem needs its command (pip-audit, cargo audit), or leave it empty."
   - "`support`: `none`, `basic` or `retainer`? Where is the fail-safe page? Which variable
     carries the Sentry DSN?"
   - "`uat`: does this project need a **UAT environment** the client signs batches off on before
     anything reaches production? If yes: the slug of the Vercel **custom environment** it will
     be (`uat` by convention — Pro only, one per project) and the one fixed address they will
     open (the domain attached to that environment) — never a per-batch preview. Production then
     stops following `main`: every merge is Staged and promoted when you publish the Release
     `promote.sh approve` drafts. If no, leave it undeclared: every merge ships, as before."
     Both `target` and `url`, or neither. **Refuse the declaration** when `setup.sh` says the team
     allows no custom environment ("UAT requires a Pro team") — UAT then stays undeclared. There
     is no UAT branch: never write `uat.branch`.
   - "`alert` maps to no channel — the red CI job is the alert. Keep that, and record it?"
   Every question has an escape hatch: "don't know" leaves the stub value and the report line.

4. **Write the project-owned files** from the answers — `.icm/project.json` (valid JSON;
   `jq -e .` before saving; the health endpoint goes to top-level `health_endpoint` — a string,
   or an array — or to `deploy.projects[].health_endpoint` when each project has its own, and
   `project-rules.md` → The factory names it), `_shared/project-rules.md` (every section a sentence or "none" — `## Learned rules` stays as
   seeded; `retrospective.sh` fills it at Release),
   `_shared/knowledge-map.md` where the repo has a docs tree, `scripts/format.sh` / `lint.sh` on
   the repo's own tools or left as `SKIP` stubs, `runs/README.md`. Nothing else: `T` files are
   the template's, code is the pipeline's. **When a UAT environment was declared**, also run
   `.icm/scripts/promote.sh init`: it prints the acts only the operator can perform — the custom
   environment and its domain, Auto-assign Custom Production Domains off, the UAT database and
   its variables, the environment deploying `main` — and seed the reference
   `.github/workflows/release.yaml` (it is the promotion) and, where production is migrated from
   CI, the reference `db-migrate.yml` shape (`workflow_call`; `uat-deploy.yaml` only where
   Vercel refuses branch tracking). Record who signs off and how under
   `_shared/project-rules.md` → People and gates, and the acts still owed there. Never touch
   Vercel from here (`.icm/_shared/promotion.md`). **When a Neon project was declared**, also run
   `.icm/scripts/db-env.sh init`: it prints the database's one-time acts — the API key and where
   it lives (the shell, and this repository's Actions secrets through `env.sh add … --ci --github
   secret`), the integration's Preview-branching toggle, the migrate step in the build, protecting
   the production branch — and, with `previews: vercel`, `setup.sh --fix --template <path>` seeds
   the reference `.github/workflows/neon-cleanup.yaml`. Record the topology and the acts still
   owed under `_shared/project-rules.md` → The factory → The environments' databases. Never
   create a Neon branch, flip the toggle or set a build command from here: `db-env.sh` reads and
   lists, and its two writes (`reset-uat`, `prune`) run only on `--apply` from the operator.
   **When a MongoDB cluster was declared**, run `.icm/scripts/db-env.sh init` the same way: it
   lists the database user's rights, the caps, and — with `previews: branch` — Vercel's system
   variables, the app's one connection line (`.icm/scripts/lib/db-name.mjs`), the preview-migrate
   workflow and the smoke check waiting on it, the reference `mongodb-cleanup.yaml`
   (`setup.sh --fix --template <path>` seeds it), and last the flag
   `MONGODB_PREVIEW_PER_BRANCH=1` on the Preview target. The app change is a chore run in the
   repo, not an edit from here; the flag is the operator's to set, and unsetting it is the revert.

5. **Re-run `setup.sh` until `RESULT: OK`** or until every remaining line is a named decision
   the operator took (recorded in `project-rules.md`). `setup.sh --report` must print the same
   bytes twice in a row before you stop.

6. **Stop with the changes on a `claude/` branch.** Commit the project-owned files (stage paths
   explicitly), push, open the PR with `create_pull_request` (`base: main`, ready — nothing to
   preview), body: the report's last `RESULT:` line and the decisions taken. A bare repo's first
   run is one PR; a maintenance run that changed nothing opens nothing and says so. Never merge;
   never subscribe to the PR (`.icm/_shared/github.md` → PR events). Report per
   `.icm/_shared/output.md` — `setup <RESULT line> · CI <verdict> · <PR URL>` (no PR → `no
   changes`), then `Operator:`: merge the PR, and every act still owed that `project-rules.md`
   records (the `promote.sh init` / `db-env.sh init` lines above, a Vercel toggle, a token) —
   one item each, actionable from the line alone.

## What this replaces, and what it does not touch

`/project`'s old § 1c ("declare the profile, guard the formatter, seed, sync, read the repo for
the P files") is this command. `/project` keeps intent, analysis and tickets, with one
precondition: `/setup` reports `OK` or names its gaps in the run. The estate walk (`/icm-check`
in icm-board) runs each repo's `setup.sh --report` where the script exists — one implementation,
two callers. The formatter guard (section 2) is reported with the exact lines to add and never
written by a script (D17/D19).
