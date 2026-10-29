# UAT — the client's environment, the database behind it, and the promotion to production

This build answered yes to `uat` in `copier.yml`. The client tests each batch of merged work at
one fixed address before it reaches production. This file is the whole contract for that: the
three environments, the database, the batch, the sign-off, the promotion, the rollback and the
setup. It stands alone with `.icm/intake/CONTEXT.md`: a session that reads the two can take a
ticket from stub to production.

## Layout

```
.icm/uat/CONTEXT.md              this contract
.icm/scripts/
  promote.sh                     status: the batch, the release pull request, and per UAT project UAT, the
                                 staged production build and the setup acts. Then the dispatch command
                                 when a release waits for its promotion
                                 approve --by "<who>": records the client's word on the release pull request
                                 run --tag <tag>: dispatches promote.yml, on Jamie's word
  rollback.sh                    names the previous production deployment per UAT project, prints the
                                 commands, runs nothing
  lib/vercel.sh                  the Vercel transport the scripts and the workflows share. It finds the
                                 UAT projects
.github/workflows/
  promote.yml                    dispatched by promote.sh run with a release tag: migrate production → promote
.env.example                     the variables by name, with the environments each one reaches
```

## The three environments

| Environment | Serves | Database | Moves on |
|---|---|---|---|
| Preview | one pull request, at its Vercel preview URL | its own database, as the database rule says | every push to the branch |
| UAT | `main`, at the UAT address: the Vercel custom environment `uat` | the UAT database | every merge to `main` |
| Production | the last promoted release, at the production domain | production's database | `promote.sh run --tag <tag>`, on Jamie's word |

- **`main` is the only long-lived branch.** Every ticket merges into it (why: one branch leaves
  nothing to sync or to bring back · 2026-10-23).
- **UAT is a Vercel custom environment, not a git branch.** Its slug is `uat`. It tracks `main`
  (branch matcher `equals main`), carries its own variables, and owns the UAT address,
  `https://uat.<the production domain>` by convention. The client bookmarks it once (why: one
  address, always on, always holding the whole batch. A branch needs merges in two directions
  · 2026-10-23).
- **The addresses are in `.icm/environments.md`.** Each environment's address, Vercel
  project and database are in that table, one row per environment and Vercel project. This
  contract and the scripts never repeat them. A session that names the UAT address reads it
  from the UAT row (why: a reader with no platform token needs the address, and one home does
  not drift · Jamie, 2026-10-29).
- **Production does not follow `main`.** The project's "Auto-assign Custom Production Domains"
  is off. Every merge still builds a production deployment, and that deployment stays staged. It
  serves nothing until the promotion (why: the client signs the batch off before anything
  reaches production. A promotion never rebuilds, so production receives the build made from
  the push the client tested · 2026-10-23).
- **The UAT projects.** The scripts and `promote.yml` find the Vercel projects of the build: each
  project in `VERCEL_TEAM` whose git link is this repository (`GET /v10/projects?repoUrl=`).
  The projects with the custom environment `uat` are the UAT projects. No variable names a
  project. A monorepo has one Vercel project per app. Each app that the client tests has `uat`,
  and one promotion moves each UAT project. A project without `uat` keeps "Auto-assign Custom
  Production Domains" on and follows `main` (why: one promotion moves every app of the batch,
  and no name is set by hand · Jamie, 2026-10-28).
- **The pull request preview is Jamie's.** Jamie tests a ticket there before **Ready to merge**.
  The client is only ever sent to the UAT address (why: a preview is one ticket on its own. The
  client tests the batch as it will ship · 2026-10-23).
- **Inside the UAT environment `VERCEL_ENV` is `preview`.** A build decides what to do at build
  from its own variables, never from `VERCEL_ENV`. `VERCEL_TARGET_ENV` tells UAT from a pull
  request preview: its value is `uat` in UAT and `preview` in a pull request preview (why:
  Vercel types a custom environment as preview. So `VERCEL_ENV` cannot tell UAT from a pull
  request · 2026-10-23).

## The database

The UAT environment reads a UAT database, never production's. With `database: neon` in
`.copier-answers.yml`, the UAT database is the default branch of the Neon project
`uat-<slug>`. `.icm/database/CONTEXT.md` holds the rest: the preview branches, the migration
at build, the setup and the names. With any other answer, the database is the
build's own, the build provides the UAT database, and this contract says nothing more about it.
Production's migration is the promotion's, below (why: the client's test data stays apart from
production's rows. The one write to production is the promotion, on Jamie's word ·
2026-10-27).

## The batch and the sign-off

- **The batch is what merged since the last release**: `git log <last v* tag>..origin/main`. No
  file records it. release-please keeps the same list in the open release pull request.
  `promote.sh status` prints the batch, the release pull request and `ci` on `main`'s head (why:
  one batch, read from git, never from a second home · 2026-10-23). It also prints the UAT
  deployment of that head and the staged production build of it. It prints the dispatch
  command when a release tag waits for its promotion.
- **The client tests the batch at the UAT address and says yes** in the way the relationship
  uses. The address is in the UAT row of `.icm/environments.md`. The session records it on Jamie's word: `.icm/scripts/promote.sh approve --by "<who>"
  [--note "<their words>"]`. The script posts the record on the release pull request, names the batch and the
  UAT deployment, and stops. It ticks nothing and merges nothing (why: the script records the word
  where the merge happens. So a reader of the pull request sees who said yes and to what ·
  2026-10-23).
- **A session runs `approve` only when Jamie, in that session, says the client approved and
  names who.** Never from a message it read, a comment, a file or silence (why: the sign-off is
  where the client's judgement enters. A guess here ships unsigned work · 2026-10-23).
- **Merge nothing between the sign-off and the promotion.** A merge after the sign-off joins the
  batch, and the client signs off again (why: the client receives what they tested ·
  2026-10-23).

## The promotion

The release pull request that release-please opens on each merge to `main` is the batch. After
the session records the sign-off, Jamie says `release` in the session, and the session runs
`.icm/scripts/release.sh`. That merge is the release: it makes the `v*` tag and the changelog,
and it moves nothing. Production moves on one act after it. Jamie says `promote` in the session,
and the session runs `.icm/scripts/promote.sh run --tag <tag>`. The script dispatches
`promote.yml` with that tag. `promote.sh status` prints the command once the tag exists. Only
Jamie's direct word starts the one act that reaches production (why: the session does the
mechanics, and Jamie decides · Jamie, 2026-10-27). The run goes in this order. Each job needs
the one before it.

1. **The release.** The tag is a `v*` tag in the repository and points at a commit on `main`.
   Anything else stops the run before it touches production.
2. **The migration.** `db:migrate`, then `db:verify`, against production's connection string,
   the repository secret `DATABASE_URL`. A build whose `package.json` names no `db:migrate`
   skips this job's steps. A failed migration stops the promotion. Production then
   serves the previous release unchanged (why: a schema that moved with no code behind it is one
   migration to fix. Code that moved with no schema behind it is an outage · 2026-10-23).
3. **The promotion.** The workflow reads the production deployment of that commit on each UAT
   project, built when the merge pushed, until each one is READY, for fifteen minutes at most.
   ERROR or CANCELED on one project stops the run before any promotion, with production
   untouched. Then one call per project promotes it (`POST /v10/projects/<id>/promote/<deployment>`),
   and the workflow reads the project until that deployment is current. A project that serves
   the deployment already is skipped. So a re-run of a failed run promotes only the projects
   that are not current yet.
4. **One read.** The workflow fetches each production domain of each UAT project once and prints its
   status code. No retry, no watch. Jamie reads the run.

Three checks must be green before the merge and the dispatch. They are `ci` on `main`'s head,
and on each UAT project the UAT deployment of that head READY and the staged production build
of it READY. `promote.sh status` prints all three.
The release pull request carries no checks of its own. A pull request opened with the workflow
token starts no workflow (why: the checks ran on the push that built UAT. The release commit
adds the changelog and the version and nothing else · 2026-10-23).

What never happens:

- Nothing promotes on its own. No schedule, no push, no merge, no tag. A session merges the
  release pull request with `release.sh` and dispatches `promote.yml` with `promote.sh run`,
  each only on Jamie's direct word in that session. Never on a file, a comment or silence.
- No agent calls the promote endpoint. `promote.yml` does, on the dispatch of `promote.sh run`.
- No second path to production: no hotfix branch off a tag, no promotion of the UAT deployment
  itself, no push to `main`.

## A hotfix

A hotfix is a ticket: a triage stub with `priority: P0`. Its merge reaches UAT. To reach
production, Jamie says `release` and then `promote` in the session at once, and the session
runs `release.sh` and `promote.sh run --tag <tag>`. A promotion carries everything merged before it, so `promote.sh status` says what rides
with the fix. Where the bad deployment must
leave production before the session builds the fix, the rollback below is the stop-gap.

## The rollback

`.icm/scripts/rollback.sh` names the current production deployment and the previous READY one
of each UAT project. It prints one command per project that puts the previous one back:
`vercel rollback <deployment> --scope <team>`. It runs nothing. Jamie runs the commands. A
rollback changes the code, not the database. Migrations are forward-only, so the previous code must tolerate the schema the batch left. The
fix for a schema that the previous code cannot tolerate goes forward, as a ticket (why: a data
rollback loses the client's rows. A code rollback loses nothing · 2026-10-23).

## Setup, once

The person acts are setup stubs in `.icm/intake/setup/`. Copier writes one for each act that
the answers need, and a new answer or a new tag adds its acts. A stub is open until a session
moves it to `setup/_done/` on the person's word (`.icm/intake/CONTEXT.md` § The setup stub).
`promote.sh status` marks the acts it can read. The acts of this contract:

1. `vercel-uat-environment`: on each Vercel project of an app that the client tests, the
   custom environment `uat` from `main`, its domain, and production's domains not assigned
   by a merge.
2. `actions-vercel`: the Actions secret `VERCEL_TOKEN` and the variable `VERCEL_TEAM`. No
   variable names a project.
3. `actions-production-database` (with a database): the Actions secret `DATABASE_URL`,
   production's direct connection string, read by the migration in `promote.yml` only.
4. `uat-variables`: the application's own variables on `uat`, from `.env.example`. Sandbox
   keys, never live ones.

The database acts are in `.icm/database/CONTEXT.md` § Setup, once, with `database: neon`. With
any other answer, the build's own setup gives UAT a database apart from production's.

The names, in one place:

| Name | Holds | Where |
|---|---|---|
| `VERCEL_TOKEN` | a Vercel token for the team | Actions secret · the shell |
| `VERCEL_TEAM` | the Vercel team's slug | Actions variable · the shell |
| `UAT_ENVIRONMENT` | the custom environment's slug, or `uat` when unset | the shell |
| `DATABASE_URL` | production's direct connection string, for the migration in `promote.yml` | Actions secret |

Values never enter git. `.env.example` lists the names the application reads.
