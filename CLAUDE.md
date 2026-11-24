# Vine Cliff Vineyards — app

The Vine Cliff Vineyards website and request-to-book platform. The work pipeline is the
BAXTER blueprint (`.icm/_system/`, version in `.icm/_system/VERSION`, answers in
`.icm/.copier-answers.yml`). One Next.js app on Vercel, with Drizzle on Neon Postgres. This
file is identity and routing only. The rules live once, in the files it points at.

## Routing

@.icm/_system/ROUTER.md

The router has the commands, the stages and the lanes. A ticket is a Linear key of the team
`JAM`. The files below belong to this repo.

| You are asked to | Go to |
|---|---|
| understand the app, its stack and its data | `README.md` |
| read the brand | `.icm/docs/brand.md` |
| read the backlog of before 2026-11-18 | `.icm/intake/README.md`, and `.icm/local/ROUTES.md` for the markdown stubs |
| add or change an environment variable | `.env.example`, the one list of names. Values never enter git |
| read where the build runs | `.icm/environments.md`, the one home of the addresses |
| read the UAT batch, record the client's sign-off, promote, roll back | `.icm/_system/features/uat.md`, then `.icm/_system/scripts/promote.sh` |
| change the database, or read which database a build migrates | `.icm/local/database.md`, then `.icm/local/vercel-build.sh` |
| do a setup act in Vercel, GitHub or the database provider | `.icm/setup/`: one file for each act. A person ticks its boxes |
| change what CI checks or how a release is cut | the blueprint. `ci.yml`, `promote.yml` and `icm.yml` come from it. `db-migrate.yml` belongs to this repo |

## Release

`ci.yml` runs the checks on each push to `main` and on each pull request that is ready. Its
job `release` keeps the release-please pull request open on `main`, and that pull request is
the batch. A merge to `main` reaches UAT. Production moves on a promotion, as
`.icm/_system/features/uat.md` says. The database model of the blueprint is not adopted
(`.icm/local/database.md`): `db-migrate.yml` migrates production at each push to `main`, and
a preview build migrates its database. The workflow `promote` does not migrate. The setup acts of `.icm/setup/` are not done on
2026-11-18: until a person does them, the repo has no UAT environment, and a merge to `main`
deploys production as before.

## Rules

- Client-facing text in `en-US`. Code, commits and notes in English.
- Technical text (pull request bodies, commits, questions) in Simplified Technical English:
  short active sentences, one instruction each, no semicolons. A question for Jamie is numbered
  and carries a default answer.
- CI is truth: never run build, lint, typecheck, test, format or dev locally. Push, then read
  the `ci` run. `.claude/hooks/block-local-checks.sh` blocks the commands.
- Secrets never in git: names only, in `.env.example`. Values in GitHub or Vercel settings.
  Flag any plaintext credential found.
- One ticket is one run, one branch and one pull request.
- `main` changes by pull request. Gates are human checkboxes: read them, never tick them.
  Jamie ticks Ready to merge. The Release stage merges.
- A ticket's merge reaches the UAT environment, where the client tests the batch. Production
  moves only on Jamie's word, after the client's sign-off (`.icm/_system/features/uat.md`).
- Linear: a session in this repo reads its ticket and makes its own ticket acts in Linear
  (a comment, a new issue in Triage, a relation) with the BAXTER Linear tool
  (`.icm/_system/rules/ticket.md`, `.icm/_system/features/linear-writes.md`).
