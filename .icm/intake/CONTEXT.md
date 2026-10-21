# Intake — the tickets, and the loop that ships them

`.icm/intake/` holds every ticket of this repo. A ticket is a markdown **stub**. The stub's
path is its identity. The stub's folder is its status. Nothing else records what is open,
done or dropped: no ticket numbers, no board file, no `TODO.md` (why: one home for the work,
in the repo where the work is · 2026-10-21).

This file is the whole contract. It stands alone: a session that reads only this file and
`CLAUDE.md` can take the next ticket to a merged pull request.

## Layout

```
.icm/intake/
  CONTEXT.md             this contract
  README.md              one paragraph for a person who opens the folder
  <epic-slug>/           one folder per epic: related work, cut into order
    breakdown.md         what was understood, and the build order
    <feature-slug>.md    one stub per unit of work: one branch, one pull request
    _done/               stubs whose pull request merged
  triage/                one-off findings that belong to no epic
    <slug>.md            a bug, a tweak or a chore
    _done/
  _done/                 epics whose last stub merged, moved whole
```

Rules of the folder:

- **Identity is the path.** A ticket is `<epic-slug>/<feature-slug>` or `triage/<slug>`.
  Slugs are kebab-case. The `feature-slug` line in a stub equals its file name.
- **Status is positional.** A stub in its epic folder is open. A stub in `_done/` is done.
  Dropped work also moves to `_done/`, with a `> Dropped: <reason>, <date>` line at the top.
  Nothing is deleted.
- **`main` is the only home.** The desk and every reader read this folder on `main`. A stub
  that is not pushed does not exist.
- **The pull request that ships a stub is the pull request that retires it.** The move to
  `_done/` is a commit on the ticket's branch. The merge makes it true.
- **A new plan becomes stubs here**, as an epic with a breakdown, never a loose list.

## The stub

```md
# Stub: <title, one line, what the user can do after this ships>

- feature-slug: <kebab, equal to the file name>
- epic: <epic-slug>
- sequence: <n> of <m>
- depends-on: <feature-slug, or none>
- complexity: low | medium | high | research
- priority: P0 | P1 | P2
- blocked: <reason>            # optional. Remove the line when the block lifts.

## Problem

<What is wrong or missing today. One to three sentences.>

## Proposed change

<What the build does, in the user's words. Not how.>

## Acceptance criteria

- [ ] <One observable result per line. The pull request copies these lines.>

## Out of scope

- <What this stub does not do.>

## Notes

<Decisions the build must keep. Files it will touch, when known. Optional.>
```

Required lines: the H1, `feature-slug`, `epic`, `sequence`, `depends-on`. The desk shows the
others when they are present. `complexity` decides the first gate (see The loop).

### The breakdown

`<epic-slug>/breakdown.md` is the epic's one review surface. Jamie reads it before any stub
is built. Edit it and re-cut the stubs to steer.

```md
# Breakdown: <epic title>

- epic-slug: <slug>
- source: <where the work came from: the proposal's scope, a call, a review>

## What I understood

<Three to six sentences. A misread is caught here, before any cut.>

## Build order

1. <feature-slug> — <one line> — depends-on: none
2. <feature-slug> — <one line> — depends-on: <feature-slug>

## Out of scope

- <What no stub covers this round.>
```

The build order is strict: sequences run `1..m` with no gap, every `depends-on` names a stub
sequenced earlier, and the order agrees with each stub's `sequence` line. The stubs that touch
shared files (the lockfile, the schema, the layouts) go first (why: every later stub merges
over them).

### The triage stub

Anything found that is not the current ticket's goes here, as one small stub, and the session
moves on. Never widen a pull request to absorb it. Never lose it in chat.

```md
# Stub: <title>

- lane: bug | tweak | chore
- found-by: <where> · <YYYY-MM-DD>
- complexity: low | medium | high | research
- priority: P0 | P1 | P2

## Problem

<Observed. One or two lines. File paths when known.>

## Proposed change

<One line, or "investigate".>
```

No breakdown, no `sequence`, no `depends-on`. The folder is a backlog, not a batch. Jamie
prunes it. A session only adds to it and consumes from it.

## Writing rules

Every stub, breakdown and pull request body is technical text. Write it in Simplified
Technical English:

- Active voice. Simple tenses. One instruction per sentence. Sentences of 20 words or fewer.
- One word for one thing, used the same way every time.
- No semicolons. No phrasal verbs. No hedges removed: a "may" stays a "may".
- A list for any sequence of three or more steps or conditions.

A question for Jamie follows the same rules, and three more:

1. Number the questions. One question per line.
2. Give a default answer after each question. Write "Default: <answer>".
3. Make each question answerable with one word where that is possible.

Write the questions in the pull request body under `## Questions`, or in the breakdown under
`## What I understood`, and stop. Do not build on a guess (why: Jamie reads on a phone, and a
short numbered list with defaults is answered in one reply · 2026-10-21).

## The loop

One ticket is one branch and one pull request. A session runs the loop from `CLAUDE.md`.

1. **Take the next stub.** Read `breakdown.md`, then the open stub with the lowest
   `sequence` whose `depends-on` is in `_done/`. A triage stub needs no order.
2. **Branch from `main`.** Name the branch after the stub: `<feature-slug>` or
   `triage/<slug>`.
3. **Open the pull request first, as a draft.** Use `.github/pull_request_template.md`. Fill
   `Ticket`, `What changes` and `Acceptance criteria` from the stub. The body carries two
   gates at its top.
   - **Spec approved** is required when `complexity` is `medium`, `high` or `research`, and
     for every stub whose `Notes` leave a decision open. Write what you will build and your
     questions, push, and stop. Jamie ticks the box, then says "build".
   - **Spec approved** is not required for a `low` stub or a triage stub. Delete its two lines
     from the body (the anchor comment and the checkbox). A missing anchor means "not
     required", never "unticked".
4. **Build the ticket.** Commit in Conventional Commits form. Push. CI is the verdict: never
   run build, lint, typecheck, test, format or dev locally. A red check: fix, commit, push,
   read again.
5. **Retire the stub on the branch.** `git mv` the stub into its epic's `_done/` (or
   `triage/_done/`). Commit it with the work. Park every off-ticket finding as a triage stub
   in the same pull request and list it under `Parked`.
6. **Flip the pull request to ready** when CI is green and the preview exists. Put the
   preview URL in the body. Tick nothing. Stop. Your last message names the pull request and
   says what waits on Jamie.
7. **Jamie tests the preview**, ticks **Ready to merge**, and merges. A session never merges
   and never ticks a gate (why: the gate is where Jamie's judgement enters ·
   2026-10-21).
8. **After the merge** the epic whose last stub merged moves whole into `.icm/intake/_done/`,
   in the next pull request that touches the folder, or by hand.

Gates are human checkboxes. Read them. Never tick them.
