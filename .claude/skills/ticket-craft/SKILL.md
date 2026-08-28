---
name: ticket-craft
description: Cut, move and plan work the estate way — epics, stubs and triage in .icm/intake/. Use whenever creating a ticket, finishing one, planning work, or ending a session with work left over in any estate repo.
---

# Ticket craft — the estate contract, portable

Canonical spec: `_system/contracts/TICKETS.md` in the icm-board repo; this repo's
`.icm/intake/README.md` is its micro-copy. This skill is the working knowledge.

## The shape

Tickets are **stubs** and never live alone:

- **Related work is an epic** — `.icm/intake/<epic-slug>/`: a `breakdown.md` (what was
  understood + `## Build order`) and one stub per unit of work. Every stub carries
  `- feature-slug:` (matching its filename), `- sequence: <n> of <m>` (contiguous
  `1..m`), and `- depends-on:` (`none`, or in-epic slugs sequenced earlier). A
  single-stub epic is fine.
- **One-off findings are triage stubs** — `.icm/intake/triage/<slug>.md` with
  `- lane: bug | tweak | chore` and `- found-by:`. Park it in a minute and move on —
  never widen the current PR to absorb it.
- **Identity is the path** (`<epic>/<slug>`) — no ticket numbers. H1 is
  `# Stub: <title>`.
- Optional dash-lines: `- priority: P0|P1|P2` (P0 urgent · P1 next · P2 whenever),
  `- size:`, `- blocked: <reason>` (external blockage — remove the line when it lifts),
  `- sources:` (cite the evidence).

**The `## Prompt` is the pick-up contract.** It must stand alone pasted into a fresh
Claude session at the repo root — the board's "Copy prompt" sends _only_ that section.
Write it cold, and have it tell the session to read the stub file for the rest.
(Repos running the `/pipeline` spine may omit it — `/pipeline new` does the picking up.)

## Status is positional

- **Open** = the stub sits in a live epic or triage. **Next** = lowest unmet sequence.
- **Done is a folder move, never a field**: `git mv` the stub to its epic's (or
  triage's) `_done/` in the PR that finishes the work. Abandoned work moves there too,
  with a `> Dropped: <reason, date>` line prepended. Never delete; never reuse a slug
  within an epic.
- **A completed epic archives whole**: every stub in `_done/` →
  `git mv intake/<epic>/ intake/_done/<epic>/`.
- **Today** lives in one file — icm-board's `.icm/today.md`, written by `/day`, at most
  10 entries estate-wide. Ticket files never carry a today flag.

## The standing rules

- Any plan, backlog or task list becomes stubs here — **never a loose `TODO.md` or
  `BACKLOG.md`**. Cutting what's left is part of ending any session.
- The board reads `main` via the GitHub API — a stub exists once pushed.
- Legacy flat `PREFIX-NNN` tickets (pre-2026-08-28) are left as they are — migrating a
  repo is `/project`'s judgment work, not a side effect of another task.
