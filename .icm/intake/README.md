# Intake — Vinecliff tickets

Open work items for this repo, one markdown file each: `VINE-NNN-slug.md`.
Finished tickets are `git mv`'d to `_done/` — the folder move is the state change.
This is the estate-wide ticket standard (canonical spec: `_system/contracts/TICKETS.md`
in the Apps estate); this file is a self-contained copy of the contract.

## Contract

Required in every ticket:

- H1: `# VINE-NNN · <title>` — `NNN` zero-padded, never reused.
- A metadata table with a `Priority` row: `P0` (urgent) · `P1` (next) · `P2` (whenever).
- A `## Prompt` section that stands alone when pasted into a fresh Claude session at
  the repo root. It should tell the session to read the ticket file for full context.

Status (a `Status` row in the table):

- `ready` → `today` → `in-progress` → `blocked`. Missing row = `ready`.
- `today` marks tickets picked for the day's worklist.
- Done is not a status — move the file to `_done/`.
- The session doing the work flips `Status` in its PR and moves the ticket to
  `_done/` in the PR that finishes it.

Optional, free-form: `Type`, `Size`, `Depends on`, `Client`, acceptance criteria,
anything else useful.

## Template

```markdown
# VINE-001 · <title>

| | |
|---|---|
| Status | ready |
| Type | task |
| Priority | P1 |
| Size | S |

## Problem
<what and why>

## Acceptance
- [ ] <observable outcome>
- [ ] CI green

## Prompt

<self-contained instruction for a fresh Claude session; reference this
ticket file by path. PRs on a claude/ branch; no local checks — CI is
the source of truth.>
```
