# .icm — this repo's work layer

*The map of this folder. Every estate repo carries the one pipeline (`icm-check.sh --fix`
from the icm-board repo seeds what is missing); how much of it a repo leans on is the
`complexity` key in `.icm/project.json` — `standard`, or `micro` for a repo too small to
hold a knowledge map. There is no profile line to declare. Canonical
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

This folder also carries the pipeline — `project.json`, `stages/`, `lanes/`, `runs/`
(every live run with its seven canonical files: project, plan, tasks, decisions, status,
handoff, FAILURE — `scripts/run-pack.sh`), `_shared/`, `scripts/`, `skills/` (three-tier
capability skills a stage loads on a trigger — `skills/README.md`), `raw/` + `processed/`
for material a client sends, `output/` for the reports the scripts compile
(`client-status.sh` → `client-status-latest.md`, the client's view) — each seeded file
documents itself (a client UAT environment, where `/setup` declares one, is
`_shared/promotion.md`), and
`.claude/skills/pipeline/SKILL.md` routes between them.

## The rules that travel with this folder

- **Identity is the path** — a ticket is `<epic-slug>/<feature-slug>`; no numbers.
- **Status is positional** — where a file sits is its state; `git mv` to `_done/` is
  "done". Nothing is deleted; dropped work carries a `> Dropped: <reason, date>` line.
- **Planning lives here** — never a loose `TODO.md` or `BACKLOG.md` at the root.
- **The board reads `main`** — an unpushed stub does not exist.
- **The pipeline is changed at its source** — a file `MANIFEST` marks `T`, or a canonical
  `.claude/` asset, is icm-board's: a request to change one is a template change request
  (`_shared/template-change.md` — a prompt for icm-board, parked as a triage stub), never an
  edit here; the sync brings the change back.
