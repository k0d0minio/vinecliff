---
name: ticket-craft
description: Cut, move and flag tickets the estate way — the .icm/intake/ contract. Use whenever creating a ticket, finishing one, planning work, or ending a session with work left over in any estate repo.
---

# Ticket craft — the estate contract, portable

Canonical spec: `_system/contracts/TICKETS.md` in the icm-board repo; this repo's
`.icm/intake/README.md` is its micro-copy. This skill is the working knowledge.

## Cutting a ticket

- One markdown file per unit of work: `.icm/intake/<PREFIX>-NNN-slug.md`. The prefix is
  in `.icm/intake/README.md`; `NNN` = highest number across `intake/` **and** `_done/`,
  plus 1 — numbers are never reused, even for dropped tickets.
- Required: H1 `# <ID> · <title>` · a `Priority` row (`P0` urgent · `P1` next · `P2`
  whenever) · a `## Prompt` section.
- **The Prompt is the entire pick-up contract.** It must stand alone pasted into a fresh
  Claude session at the repo root — the board's "Copy prompt" sends *only* that section.
  Write it cold, and have it tell the session to read the ticket file for the rest.
- Optional, free-form: `Type`, `Size`, `Status`, `Depends on`, `Sources`, `Client`,
  acceptance checkboxes. The board displays what it finds.

## Status and done

- Vocabulary: `ready` → `today` → `in-progress` → `blocked`. Missing row = `ready`.
- `today` is the pick-up flag — **at most 3 across the whole estate**, flipped by `/day`.
- **Done is a folder, not a field**: `git mv` the file to `.icm/intake/_done/` in the PR
  that finishes the work. Abandoned work goes there too, with a
  `> Dropped: <reason, date>` line prepended. Never delete; never reuse a number.

## The standing rules

- Any plan, backlog or task list becomes tickets here — **never a loose `TODO.md` or
  `BACKLOG.md`**. Cutting what's left is part of ending any session.
- The board reads `main` via the GitHub API — a ticket exists once pushed.
- The session that picks a ticket up flips `Status` in its PR and moves the file to
  `_done/` in the PR that finishes it.
