# Routes of this repo

Language: en

These routes are in addition to `.icm/_system/ROUTER.md`. They belong to this repo.

## The markdown backlog of before 2026-11-18

Before the BAXTER blueprint, a ticket of this repo was a markdown stub: `.icm/intake/<epic>/<slug>.md`
with a `breakdown.md` for each epic, and `.icm/intake/triage/<slug>.md`. A finished stub is in a
`_done/` folder. On 2026-11-18 the repo had 9 open stubs in the epic `go-live` and no open
triage stub. A stub can name a path of the pipeline of before (`.icm/scripts/`, `.icm/uat/`):
that path is not in the repo now.

A ticket is now a Linear key of the team `JAM`. A stub is not a ticket.

1. To work on a stub, the operator asks BAXTER for its Linear ticket. BAXTER makes it from the
   stub: the title, the sections, and the path of the stub.
2. Start the work with the Linear key, as the router says.
3. In the pull request of that ticket, move the stub into its `_done/` folder.
4. Do not start a run from a stub path: the blueprint of this repo refuses it.

`.icm/intake/README.md` has the order of the epics.

## The setup acts

The setup stubs of `.icm/intake/setup/` left on 2026-11-18, each with open boxes. The setup
acts are now the files of `.icm/setup/`.

## The database

`.icm/local/database.md` has the rule for the database of today: `db-migrate.yml` migrates
production, and a preview build migrates at build. `.icm/local/vercel-build.sh` is that build
step. The two files leave when the repo answers `database: postgres` to the blueprint.
