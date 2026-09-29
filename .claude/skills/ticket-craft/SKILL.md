---
name: ticket-craft
description: Cut, move and plan work the estate way — epics, stubs and triage in .icm/intake/. Use whenever creating a ticket, finishing one, planning work, or ending a session with work left over in any estate repo.
---

# Ticket craft — the estate contract, portable

Canonical spec: `_system/contracts/TICKETS.md` in the icm-board repo; this repo's
`.icm/intake/README.md` is its micro-copy. This skill is the working knowledge.

## The shape

Tickets are **stubs** and never live alone:

- **Related work is a scope** — `.icm/intake/<scope-slug>/` (the Scope stage's word;
  "epic" in older prose means the same folder): a `breakdown.md` (`- scope-slug:`, what was
  understood + `## Build order`) and one stub per unit of work. Every stub carries
  `- feature-slug:` (matching its filename), `- sequence: <n> of <m>` (contiguous
  `1..m`), and `- depends-on:` (`none`, or in-scope slugs sequenced earlier); `- scope:`
  names its folder. A single-stub scope is fine.
- **One-off findings are triage stubs** — `.icm/intake/triage/<slug>.md` with
  `- lane: bug | tweak | chore` and `- found-by:`. Park it in a minute and move on —
  never widen the current PR to absorb it.
- **Identity is the path** (`<scope>/<slug>`) — no ticket numbers. H1 is
  `# Stub: <title>`. Triage holds at most 60 active stubs.
- Optional dash-lines: `- priority: P0|P1|P2` (P0 urgent · P1 next · P2 whenever),
  `- complexity: low|medium|high|research` (`select-model.sh` reads it), `- blocked:
  <reason>` (external blockage — remove the line when it lifts), `- sources:` (cite the
  evidence), `- touches:` (the surfaces it will change).

**A stub is its own brief; `## Prompt` is optional.** What the board's "Copy prompt" sends
is the verb and the slug — `new <scope>/<slug>` for a scope stub, `<lane> <slug>` for a
triage stub (`chore fix-dependencies`) — which `route-request.sh` routes to `/pipeline`
where the repo carries the router; a repo without one reads the stub by its path. Write a
`## Prompt` only when the Problem and Proposed change cannot carry the words (a template
change request always has one).

## Status is positional

- **Open** = the stub sits in a live epic or triage. **Next** = lowest unmet sequence.
- **Done is a folder move, never a field**: `git mv` the stub to its scope's (or
  triage's) `_done/` in the PR that finishes the work. **Dropped work is deleted or
  archived, never left open**: delete it (the commit says why) or move it to `_done/` with a
  `> Dropped: <reason, date>` line when the reasoning is worth keeping. Never reuse a slug
  within a scope.
- **A completed scope archives whole**, and the front run that cut it goes with it:
  every stub in `_done/` → `git mv intake/<scope>/ <archive>/<scope>/` (`intake_archive`
  in `.icm/project.json`, else `intake/_done/`).
- **Today** lives in one file — icm-board's `.icm/today.md`, written by `/day`, at most
  10 entries estate-wide. Ticket files never carry a today flag.

## The standing rules

- Any plan, backlog or task list becomes stubs here — **never a loose `TODO.md` or
  `BACKLOG.md`**. Cutting what's left is part of ending any session.
- The board reads each repo's `main` — so a stub exists once it is pushed there. Outside a
  run, every ticket change is a direct commit to `main`, in icm-board and client repos alike
  (`pr-conventions` → Ticket commits); inside a run it rides the run's PR.
- A request to change a template-owned file is parked in the repo as a
  `found-by: template-change` triage stub and cut again in icm-board (D33); it retires with
  `- superseded-by:` when the sync brings the change back.

## What the session says

This is about the **chat** only — PR bodies, stubs and `handoff.md` stay as full as they need to
be, and a gate checkbox lives in the PR body, never in chat. In chat: valuable information, easy
to parse. While working, a short line per phase change or notable event (`CI red on lint —
fixing`) — no narration of tool calls, no pasted files or diffs. At a stop: a bold outcome line
`<task> <outcome> · CI <verdict> · <PR link>`, 2–5 bullets of what matters (decisions, surprises,
what was parked), then `Operator:` as a numbered list of human-only acts with where to do them (a gate is
named with its PR link), then `Unverified:` when anything was. **Never trimmed:** a STOP and its
reason, a red check, anything skipped or unverified, a plaintext credential found. Pipeline repos
hold the full doctrine in `.icm/_shared/output.md`.
