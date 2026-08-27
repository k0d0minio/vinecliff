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

- The PR that finishes a ticket's work moves the ticket file to `.icm/intake/_done/`.
- Work discovered mid-PR that doesn't belong in it becomes a new ticket, not scope
  creep — cut it and reference it in the PR description.
