# Migration tools — ordering, out-of-order, and where the setting lives

`check-migrations.sh` enforces the stamp on the SQL files `migrations.path` names and prints
one line for the declared `migrations.tool`. What each tool actually does with order:

| tool | orders by | a migration stamped before one already applied | the setting |
|---|---|---|---|
| **flyway** | the `V<version>__` prefix, parsed numerically | refused by default (`Detected resolved migration not applied to database`) | `flyway.outOfOrder=true` in `flyway.conf`, or `-outOfOrder=true` on the command line — `migrations.out_of_order: true` says the repo runs with it |
| **prisma** | the migration folder name, lexicographic | applied — `prisma migrate deploy` applies every pending migration in folder order and does not refuse an older stamp; what it refuses is a **checksum** change to an applied migration | none — never edit an applied migration; the `V…__` stamp rule applies to raw SQL folders, not to prisma's own `migrations/<timestamp>_<name>/migration.sql` |
| **drizzle** | `meta/_journal.json` (`idx`, `when`), not the file name | the journal is the order; two branches that both ran `drizzle-kit generate` conflict in the journal | none — resolve a journal conflict by regenerating on the merged tree (`drizzle-kit generate` after the merge), never by editing `idx` by hand |
| **sql** (a plain runner, `psql -f` in a loop, a custom script) | file name, lexicographic | whatever the runner does — most apply anything not yet recorded | the runner must record applied files by name and apply the rest, in name order; `migrations.out_of_order: true` is the statement that it does |
| **mongodb** (ts-migrate-mongoose, migrate-mongo and their kin) | the `<epoch ms>-` prefix of the file name, numerically | applied — the runner records applied files by NAME in a collection and applies every unrecorded file in stamp order, an older stamp included (`migrations.out_of_order: true` is a statement, not a switch) | none for order. The one thing to know: a **re-stamped file is a new name** to the runner — its old record is an orphan (a runner that prunes drops it; one that does not, refuses to start) and the migration **runs again**. Every migration must therefore be idempotent, which is the same rule a shared preview database already imposes. **The round trip proves it** (D35): with `database.isolation: database`, `db-branch.sh <slug> prove` runs this branch's own migrations up → down → up on the run's database and compares the collection list and every index spec — a `down` that is missing or leaves an index behind fails where `migrations.reversible: true`, and one more `up` after the runner's records are forgotten (a re-stamp, replayed) must change nothing. The migrate command takes `up [<name>]` and `down <name>`, the name as the runner records it |

## The stamp, and why milliseconds

Two runs stamped in the same second sort by name, and name order is arbitrary. A UTC
millisecond stamp — 17 digits — makes the order the order they were written in, across
machines, without a counter anybody has to coordinate. `check-migrations.sh --new` reads the
clock once, after the newest stamp `main` and the branch already carry, so a stamp is never
behind one that exists.

The legacy second form (`20260922070000_add_tokens.sql`) is still read and ordered; a repo
keeps it by declaring `"stamp": "seconds"` in `.icm/project.json` → `migrations`. The
**epoch form** (`1782500000000-add-tokens.ts`: 13 digits of epoch milliseconds, a dash, a
kebab-case name, the repo's extension) is the same millisecond with a different face — what
the MongoDB runners write; a repo declares `"stamp": "epoch"` and `"extension": "ts"` (D34).
Mixed forms in one folder are ordered by stamp value, not by file name — which is why the
script sorts them itself, converting every form to one 17-digit UTC stamp first.
