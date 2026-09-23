# Runs — one folder per unit of work in flight

`runs/<slug>/` is a run's working home: `run.md` (the pointer index — lane, stub,
branch, PR, and a `- db:` line when `db-branch.sh` bound a database), `usage.md` (one
`- usage:` line per stage start and end, appended by `usage-snapshot.sh`, never edited), the
**canonical file pack** (below) plus each stage's `output/`. Spine runs carry
`02_define/output/spec.md` and `03_build/output/notes.md` (Release appends its
`## Release` record there); lane runs carry `lane/output/notes.md` instead — and, where
something failed on the way, an `error.log` beside it (each error and its fix;
`retrospective.sh` reads it at Release, and the archive keeps it so later runs can count what
recurs). A **front**
run — Scope — carries `01_scope/_source/story.md` and `01_scope/output/scope.md`, and
opens no PR of its own.

```md
# Run: <slug>

- lane: feature            # or front | bug | tweak | chore | hotfix | handover
- stub: intake/<epic>/<slug>.md   # when spun from one
- branch: claude/<slug>    # recorded, not enforced — written by new-run.sh
- pr: #456                 # the ONE PR — written by new-run.sh (a front has none)
- db: schema run_<slug> (via $DATABASE_URL)   # written by db-branch.sh up, removed by down
```

**The canonical file pack** — seven plain-text files at the root of every live run, seeded by
`new-run.sh` (through `.icm/scripts/run-pack.sh --init`) and by Scope for a front, so a
session on any machine can resume from what the last one left, not from memory:

| file | one job | who writes it |
|---|---|---|
| `project.md` | the context card — pointers to stub, scope, spec; touches; constraints | seeded; Define fills the gaps |
| `plan.md` | the execution plan in passes, one layer each | Define (the advisor); Build rewrites when reality disagrees |
| `tasks.md` | the queue with a definition of done per item (`- [ ]`, human checkboxes) | seeded from the spec's criteria; Build ticks |
| `decisions.md` | the `D-n` ids the run rests on, and any it made itself | seeded from the scope; any stage that decides |
| `status.md` | phase · step · ci · blocked · updated — read first on a resume | every stage, at start, stop and every flag flip |
| `handoff.md` | next steps and blockers for the next session — rewritten at every stop | every stage, last thing before it stops |
| `FAILURE.md` | what the run learned that no tool logged — a wrong assumption, a STOP, a rewritten plan — and its learned rules (a tool's error is an `error.log` entry, `retrospective.sh`'s) | the stage that learned it; `close-out.sh` copies the rules into `_shared/project-rules.md` (`run-pack.sh --sync-rules`) |

`run-pack.sh <slug> --check` says whether a run has all seven. The `03_build/output/error.log`
(a lane: `lane/output/error.log`) is where `security-check.sh` writes its redacted trace when it
blocks a commit — read it, never commit around it.

**A run only ever writes inside its own folder, on its own branch** — that is what lets several
runs be in flight at once: each stage's working artifacts land under `runs/<slug>/<stage>/`, the
run is bound to `claude/<slug>`, and no two live runs share a working tree
(`.icm/_shared/stage-preamble.md` → Run-scoped isolation). A run's database is its own too
(`db-branch.sh`), where the repo declares one.

**Live folders hold only live work.** The session that merges a run moves it to
`runs/_done/<slug>/` — `.icm/scripts/close-out.sh <slug>`, run on the branch as the last
commit before the merge, so the squash publishes it (`stages/04_release/CONTEXT.md`). A
merged run still sitting here is the alarm that the close-out was missed. Runs are
tracked in git and ride the run's PR, so any device can resume them
(`.icm/_shared/stage-preamble.md`).
