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
  promote.sh                     status: the batch, the release pull request, UAT, the staged production
                                 build, and the dispatch command when a release waits for its promotion
                                 approve --by "<who>": records the client's word on the release pull request
                                 run --tag <tag>: dispatches promote.yml, on Jamie's word
  rollback.sh                    names the previous production deployment, prints the command, runs nothing
  lib/vercel.sh                  the Vercel transport the scripts and the workflows share
.github/workflows/
  promote.yml                    dispatched by promote.sh run with a release tag: migrate production → promote
.env.example                     the variables by name, with the environments each one reaches
```

## The three environments

| Environment | Serves | Database | Moves on |
|---|---|---|---|
| Preview | one pull request, at its Vercel preview URL | the UAT database, or the pull request's own as the database rule says | every push to the branch |
| UAT | `main`, at the UAT address: the Vercel custom environment `uat` | the UAT database | every merge to `main` |
| Production | the last promoted release, at the production domain | production's database | `promote.sh run --tag <tag>`, on Jamie's word |

- **`main` is the only long-lived branch.** Every ticket merges into it (why: one branch leaves
  nothing to sync or to bring back · 2026-10-23).
- **UAT is a Vercel custom environment, not a git branch.** Its slug is `uat`. It tracks `main`
  (branch matcher `equals main`), carries its own variables, and owns the UAT address,
  `https://uat.<the production domain>` by convention. The client bookmarks it once (why: one
  address, always on, always holding the whole batch. A branch needs merges in two directions
  · 2026-10-23).
- **Production does not follow `main`.** The project's "Auto-assign Custom Production Domains"
  is off. Every merge still builds a production deployment, and that deployment stays staged. It
  serves nothing until the promotion (why: the client signs the batch off before anything
  reaches production. A promotion never rebuilds, so production receives the build made from
  the push the client tested · 2026-10-23).
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
`.copier-answers.yml`, the UAT database is the default branch of a second Neon project, the
base. `.icm/database/CONTEXT.md` holds the rest: the base, the preview branches, the
migration at build, the setup and the names. With any other answer, the database is the
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
  uses. The session records it on Jamie's word: `.icm/scripts/promote.sh approve --by "<who>"
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
3. **The promotion.** The workflow reads the production deployment of that commit, built when the
   merge pushed, until it is READY, for fifteen minutes at most. ERROR or CANCELED stops the promotion
   with production untouched. One call promotes it (`POST /v10/projects/<id>/promote/<deployment>`)
   and the workflow reads the project until that deployment is current. A deployment that is current
   already is a no-op, so a failed run can be re-run.
4. **One read.** The workflow fetches each production domain once and prints its status code. No retry,
   no watch. Jamie reads the run.

Three checks must be green before the merge and the dispatch. They are `ci` on `main`'s head,
the UAT deployment of that head READY and the staged production build of it READY. `promote.sh status` prints all three.
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

`.icm/scripts/rollback.sh` names the current production deployment and the previous READY one,
and prints the command that puts the previous one back: `vercel rollback <deployment> --scope
<team>`. It runs nothing. Jamie runs the command. A rollback changes the code, not the database.
Migrations are forward-only, so the previous code must tolerate the schema the batch left. The
fix for a schema that the previous code cannot tolerate goes forward, as a ticket (why: a data
rollback loses the client's rows. A code rollback loses nothing · 2026-10-23).

## Setup, once

Jamie performs these by hand, once, before the first merge that relies on them. `promote.sh
status` marks the ones it can read.

1. Vercel → the project → Settings → Environments: a custom environment with the slug `uat`,
   branch tracking `main`. Attach the domain `uat.<the production domain>` to it and add the
   CNAME at the registrar. A custom environment needs a Pro team.
2. Vercel → Settings → Environments → Production: "Auto-assign Custom Production Domains" off.
3. The database: with `database: neon`, `.icm/database/CONTEXT.md` § Setup, once. With any
   other answer, the build's own setup, with a UAT database apart from production's.
4. GitHub → the repository → Settings → Secrets and variables → Actions. Secrets:
   `VERCEL_TOKEN`, and `DATABASE_URL` (production's direct connection string, read by the
   migration in `promote.yml` only) when `package.json` names `db:migrate`. Variables:
   `VERCEL_TEAM`, and `VERCEL_PROJECT` when the Vercel project's name differs from the
   repository's.
5. The application's own variables on the `uat` environment, from `.env.example`: sandbox keys, never
   live ones.

The names, in one place:

| Name | Holds | Where |
|---|---|---|
| `VERCEL_TOKEN` | a Vercel token for the team | Actions secret · the shell |
| `VERCEL_TEAM` | the Vercel team's slug | Actions variable · the shell |
| `VERCEL_PROJECT` | the Vercel project's name, or the repository's name when unset | Actions variable · the shell |
| `UAT_ENVIRONMENT` | the custom environment's slug, or `uat` when unset | the shell |
| `DATABASE_URL` | production's direct connection string, for the migration in `promote.yml` | Actions secret |

Values never enter git. `.env.example` lists the names the application reads.
