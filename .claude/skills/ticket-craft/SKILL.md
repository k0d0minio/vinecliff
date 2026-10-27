---
name: ticket-craft
description: "The judgement behind a good ticket in this repo. It covers a stub that a cold session can build and the cut of an epic from a story or a proposal. It also covers the triage stub and a dropped stub. Use when you write, cut, plan, park, move or drop work. Triggers: ticket, stub, epic, breakdown, triage, plan, backlog."
---

# Ticket craft — the judgement

The contract is `.icm/intake/CONTEXT.md`. It holds every shape: the stub, the breakdown, the
triage stub, the order of the epics and the loop. This skill adds the judgement that fills a
shape well. Where the two disagree, the contract wins.

## A stub a cold session can build

A session with no chat history reads the stub and builds it. Write for that reader.

- **The title** says what the user can do after the stub ships, not the task. Write "The
  client downloads the invoice as a PDF", not "Add PDF export".
- **`Problem`** says what you observed: a file, a screen, a message, a count. Do not write a
  guess as a fact. A guess goes in `Notes`, with "may".
- **One observable result per criterion.** A reviewer checks each line on the preview or in
  the diff. "Works well" is not a result. Two results are two lines.
- **`Out of scope`** names the near work that a reader can expect and that waits. It stops the
  build from growing.
- **`Notes`** holds the decisions that the build must keep, each with its why. It names the
  files that the build will touch, when you know them.
- **`complexity` is honest.** It decides the first gate: `low` drops Spec approved. Write
  `low` only when the stub leaves no decision open. When you are not sure, write `medium` (why:
  a skipped gate can cost a rebuild, and a kept gate costs one tick · 2026-10-27).

## The cut from a story or a proposal

- One story is one epic. A proposal or a plan is one epic too, unless it holds two goals that
  can ship apart.
- Every criterion of the story gets a row in `Criteria → stubs`, also a criterion that is not
  built. Nothing that the client wrote is lost silently.
- One stub is one branch and one pull request that a reviewer reads in one sitting. A stub that
  needs two reviews is two stubs.
- The stubs that touch shared files go first: the schema, the lockfile, the layouts.
- Sequences run without a gap. `depends-on` names a stub with a lower sequence, or `none`.
- When another epic is open, ask for the order, as the contract's § The order of the epics
  says. Never set the order on a guess.
- A cut holds decisions. Push it and stop for Jamie's review, as the contract's § A request
  with no stub says.

## The triage stub

- Park it in a minute. Write the lane, `found-by` and what you observed. Then go back to the
  ticket.
- Pick the lane by the kind of change, not by its size. A fault is `bug`. A small change that
  the request fully specifies is `tweak`. Work with no change in behaviour is `chore`. A
  `hotfix` starts on Jamie's word only.
- Never widen the current pull request to absorb a finding. Park the stub in the same pull
  request and list it under `Parked`.
- One finding is one stub. Two findings in one file are two stubs when they can ship apart.

## Status is positional

- The folder is the status. Do not add a status line, a done box or a done date to a stub.
- The move to `_done/` rides the pull request that ships the stub. A stub in `_done/` on
  `main` shipped, or a session dropped it.

## A dropped stub

- Drop a stub when the need is gone, when another stub covers it, or when Jamie says no to it.
  Do not drop a stub because it is hard.
- Write the reason for a reader one year later: what changed, or which stub covers the work.
  "Not needed" tells that reader nothing.
- A dropped stub moves, as the contract's § Rules of the folder says. Never delete it.

## A slug is never reused

A slug names one piece of work for ever. New work gets a new slug, also when the old stub was
dropped (why: the branch, the pull request and the `ticket:` line carry the slug. A reuse joins
two histories · 2026-10-27).

## No `TODO.md`

- A plan, a backlog or a list of leftovers becomes stubs in `.icm/intake/`. Never a `TODO.md`,
  a `BACKLOG.md` or a list in the chat.
- Cut the remaining work into stubs before the session stops.

## The words

Write every stub, breakdown and pull request body under `.claude/skills/asd-ste100`, in its
STE-flavored mode. This lets Jamie read it on a phone in one pass (why: Jamie's reference
for every ticket across the estate · 2026-10-27). Keep every hedge and every condition. A
question for Jamie follows the contract's § Writing rules.
