---
name: pr-conventions
description: The estate's git and PR rules — branches, commits, what goes to main, what CI owns. Use before committing, branching, pushing, or opening a PR in any estate repo.
---

# PR conventions — how code ships in this estate

Canonical doctrine: icm-board's `_system/README.md` § House doctrine. This skill is the
working knowledge.

## Branches and what goes where

- Code changes go through a **PR on a `claude/` branch** — never straight to `main`.
- **Ticket-only commits go straight to `main`** (planning is data): only `.icm/` paths,
  message `Plan: <one line>` or `Wrap: <one line>`.
- Never rewrite history on a shared branch; never force-push `main`.

## Committing

- **Stage paths explicitly — never `git add -A`.** Anything dirty that the task didn't
  touch is left strictly alone.
- Commit messages say what changed and why in the first line; no model identifiers.
- **No secrets in git, ever.** Env vars only. A plaintext credential found anywhere is a
  P0 — flag it immediately, do not commit around it.

## CI owns verification

- **CI is the source of truth. Never run `build`/`lint`/`typecheck`/`test` locally** —
  push and read the checks. A red check is the task; a green check is the proof.
- Gates and checkboxes in tickets or pipeline docs are **human checkboxes** — read
  them, never tick them.

## Finishing

- The PR that finishes a stub's work `git mv`s the stub to its epic's (or triage's)
  `_done/`. The `wrap-reminder` Stop hook asks about this at session end when a branch
  shipped work matching an open stub it never touched — it asks, it never moves the
  file. Partial work is a legitimate answer: say so and carry on (status is positional;
  there is no field to flip).
- Work discovered mid-PR that doesn't belong in it becomes a new stub, not scope creep —
  park it in `.icm/intake/triage/` (or its epic) and reference it in the PR description.
