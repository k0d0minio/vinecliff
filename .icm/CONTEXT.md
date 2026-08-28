# .icm — this repo's work layer

- profile: intake

*The map of this folder. The profile line above is read by the estate conformance
tooling (`icm-check.sh`) — `intake` is the default; change it to `pipeline` (and re-run
`icm-check.sh --fix` from the icm-board repo) to receive the run spine. Canonical
contracts: `_system/contracts/TICKETS.md` and `_system/contracts/PIPELINE.md` in the
icm-board estate; `intake/README.md` here is the self-contained micro-copy.*

## Layout

```
.icm/
  CONTEXT.md            ← this file
  project.md            ← what this project is for — written by /project, never by hand
  intake/               ← the work: epics + triage (see intake/README.md)
    <epic-slug>/          breakdown.md + one stub per unit of work + _done/
    triage/               parked one-off bug/tweak/chore stubs
    _done/                completed epics + the legacy archive
  docs/                 ← ad hoc reports, client words, runbooks
```

With `- profile: pipeline`, this folder also carries `stages/`, `lanes/`, `runs/`,
`_shared/` and `scripts/` — each seeded file documents itself, and
`.claude/skills/pipeline/SKILL.md` routes between them.

## The rules that travel with this folder

- **Identity is the path** — a ticket is `<epic-slug>/<feature-slug>`; no numbers.
- **Status is positional** — where a file sits is its state; `git mv` to `_done/` is
  "done". Nothing is deleted; dropped work carries a `> Dropped: <reason, date>` line.
- **Planning lives here** — never a loose `TODO.md` or `BACKLOG.md` at the root.
- **The board reads `main`** — an unpushed stub does not exist.
