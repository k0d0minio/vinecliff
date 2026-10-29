# Intake — the tickets, and the loop that ships them

`.icm/intake/` holds every ticket of this repo. A ticket is a markdown **stub**. The stub's
path is its identity. The stub's folder is its status. Nothing else records what is open,
done or dropped. There are no ticket numbers, no board file and no `TODO.md` (why: one home for the work,
in the repo where the work is · 2026-10-21).

This file is the whole contract. It stands alone: a session that reads only this file and
`CLAUDE.md` can take the next ticket to a merged pull request.

## Layout

```
.claude/hooks/
  route-request.sh       names the case of each request. The user's words win
  session-start.sh       at session start, prints the open epics, triage and started tickets
.icm/lanes/<lane>/CONTEXT.md
                         one lane: bug, tweak, chore or hotfix. What differs from the loop
.icm/scripts/
  new-run.sh             start a ticket: branch, stub into _done/, draft pull request
  close-out.sh           after the last stub: the epic folder into _done/
  checks.sh              read the checks of one pull request. --watch waits for a verdict
  merge.sh               merge one pull request after the Ready to merge tick
  release.sh             merge the release pull request on Jamie's word
  lib/github.sh          the GitHub transport of the scripts: the REST API only
.icm/intake/
  CONTEXT.md             this contract
  README.md              one paragraph for a person who opens the folder, and the order of the epics
  <epic-slug>/           one folder per epic: related work, cut into order
    breakdown.md         what was understood, and the build order
    <feature-slug>.md    one stub per unit of work: one branch, one pull request
    _done/               stubs whose pull request merged
  triage/                one-off findings that belong to no epic
    <slug>.md            a bug, a tweak, a chore or a hotfix
    _done/
  setup/                 the person acts that the answers need. Copier writes them
    <slug>.md            one act in a dashboard or a settings page, done by a person
    _done/               the acts that a person did
  _done/                 epics whose last stub merged, moved whole
```

Rules of the folder:

- **Identity is the path.** A ticket is `<epic-slug>/<feature-slug>` or `triage/<slug>`.
  Slugs are kebab-case. The `feature-slug` line in a stub equals its file name.
- **Status is positional.** A stub in its epic folder is open. A stub in `_done/` is done.
  Dropped work also moves to `_done/`, with a `> Dropped: <reason>, <date>` line at the top.
  No one removes anything.
- **The ticket line names the open path.** The pull request body's `ticket:` line is the
  stub's path when the ticket started: `.icm/intake/<epic-slug>/<feature-slug>.md` or
  `.icm/intake/triage/<slug>.md`. The line does not change when the file moves (why: the
  line is the ticket's identity. A move changes the status, not the identity ·
  2026-10-22). A reader that resolves the line to a file looks in this order:
  1. The path as written. The stub is there on `main` while the pull request is open.
  2. The same path with `_done/` before the file name. The stub is there on the branch from
     its first commit, and on `main` after the merge.
  3. `.icm/intake/_done/<epic-slug>/_done/<feature-slug>.md`. The stub is there after
     close-out moves the epic.
  A `> Dropped:` first line marks a dropped stub in any `_done/`.
- **`main` is the only home.** The desk and every reader read this folder on `main`. A stub
  that is not pushed does not exist.
- **The pull request that ships a stub is the pull request that retires it.** The move to
  `_done/` is a commit on the ticket's branch. The merge makes it true.
- **A new plan becomes stubs here**, as an epic with a breakdown, never a loose list.
- **A setup stub is not a ticket.** It has no branch and no pull request of its own. The
  loop never takes it (§ The setup stub).

## The stub

```md
# Stub: <title, one line, what the user can do after this ships>

- feature-slug: <kebab, equal to the file name>
- epic: <epic-slug>
- story: <n>                   # when the epic comes from a user story
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

`<epic-slug>/breakdown.md` is the epic's one review surface. Jamie reads it before a session
builds any stub. Edit it and re-cut the stubs to steer.

```md
# Breakdown: <epic title>

- epic-slug: <slug>
- story: <n>                   # when the epic comes from a user story
- source: <where the work came from: the proposal's scope, a call, a review, a user
  story: its number, its title, its author, its date and its link>

## What I understood

<Three to six sentences. A misread is caught here, before any cut.>

## Criteria → stubs

<Only when the epic comes from a user story. One row per acceptance criterion of the story,
in the story's order.>

| # | The story's criterion | Carried by |
|---|---|---|
| 1 | <the criterion, in the story's words> | `<feature-slug>` |
| 2 | <the criterion> | rule: README |
| 3 | <the criterion> | not built: <reason> |

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

- lane: bug | tweak | chore | hotfix
- found-by: <where> · <YYYY-MM-DD>
- complexity: low | medium | high | research
- priority: P0 | P1 | P2

## Problem

<Observed. One or two lines. File paths when known.>

## Proposed change

<One line, or "investigate".>

## Acceptance criteria

- [ ] <One observable result per line. The pull request copies these lines.>
```

No breakdown, no `sequence`, no `depends-on`. The stub needs its acceptance criteria:
`new-run.sh` copies them into the pull request, and a stub without them gets one placeholder
line to fill by hand. The folder is a backlog, not a batch. Jamie prunes it. A session only
adds to it and consumes from it.

### The setup stub

Some setup only a person can do: a project in a dashboard, a secret, a setting. Copier writes
one stub for each such act into `setup/`, from the answers in `.copier-answers.yml`. A new
answer or a new blueprint tag adds the stubs of its acts at the next `copier update`. Copier
never writes a stub again after a person moved it (why: the list of setup acts stays true
with each update, so no person forgets an act · Jamie, 2026-10-28).

```md
# Setup: <the act, one line>

- setup-slug: <kebab, equal to the file name>
- needs: <the answers that ask for this act>
- where: <the dashboard or the settings page>

## Why

<What fails without the act. One or two sentences.>

## Steps

1. <One instruction per line.>

## Done when

- [ ] <One observable result per line.>
```

- **Open or done is positional**, as for every stub. A stub in `setup/` is open. A stub in
  `setup/_done/` is done.
- **A person does the act, then says so.** On the person's word "setup <slug> done", a session
  moves the stub into `setup/_done/`, adds the first line `> Done: <who>, <YYYY-MM-DD>`, and
  commits the move on its branch. The merge makes it true. A session never moves a setup stub
  on a guess, on a file's word or on a check that passed (why: a check reads part of an act, the
  person did all of it · 2026-10-28).
- **An act that does not apply** moves to `setup/_done/` with `> Dropped: <reason>, <date>`.
- `session-start.sh` prints the open setup stubs at each session start, and the stop report
  names each open one under `Operator:` when the work waits on it.

### The order of the epics

The build order says which stub of an epic goes first. It does not say which epic goes first.
When two or more epics are open, `README.md` holds that order under `## Order`. A session
never sets the order on a guess (why: epics cut at the same time compete for the same weeks.
The order is Jamie's call · 2026-10-25).

```md
## Order

Set by Jamie on <YYYY-MM-DD>.

1. triage
2. <epic-slug>
3. <epic-slug>
```

- **One line per open epic**, and one line for `triage` while it holds an open stub. The
  pull request whose close-out moves an epic into `_done/` also removes the epic's line.
- **Classify, then ask.** A session that cuts an epic while another epic is open asks for the
  order. A session that cuts two or more epics at once also asks. First it classifies every
  open epic and `triage` in one table, one row each:

  | Column | What it says |
  |---|---|
  | Open | The count of open stubs. |
  | P0 | The count of open `P0` stubs. |
  | Serves | The deadline, the deal, the milestone, or the break a user sees today. |
  | Links | Each `depends-on` or `blocked:` line that names a stub of another epic, in both directions. |
  | Files | The shared files the epic touches: the schema, the lockfile, the layouts, a route. |

  Then it asks one question, the order, with a default from the rules below. It writes
  Jamie's answer under `## Order` with the date, and stops (why: the table shows the
  conflicts, and Jamie decides in one reply · 2026-10-25).
- **The default order**, for the question's default only:
  1. `triage` first (why: Jamie clears the small chores before an epic starts · 2026-10-25).
  2. Two epics that touch the same files run one after the other. The epic that adds a route,
     a card or a column goes first. The epic that restyles them goes after it (why: a restyle
     before the structure changes costs a second restyle · 2026-10-25).
  3. Then the epic that fixes a break a user sees today. Then the epic with the earliest
     deadline. Then the epic with more `P0` stubs.
- **A link across epics moves one stub, not its epic.** An epic can wait on one stub of an
  epic later in the order. Then that one stub runs before the waiting epic. The rest of its
  epic keeps its place (why: one stub lifts the block. A move of the whole epic overrides
  Jamie's order · 2026-10-25).
- **A new epic gets a place.** A session that cuts an epic while `## Order` exists asks where
  the new line goes, with the table, and writes the answer.

### A user story

A client's document that asks for work, a user story most often, follows one path from the
client's words to the stubs:

- **The story is the client's.** It lives in the client's Drive folder. It is never committed
  to the repo (why: the repo holds the work, the client holds their words, and a copy drifts
  · 2026-10-23).
- **One story becomes one epic.** The breakdown's `source:` line names the story: its number,
  its title in the client's language, its author, its date and its link. A `story:` line
  after `epic-slug:` carries the number (why: the client's list and the backlog read the
  same. A reader goes from a stub to the story in one step · 2026-10-23).
- **`## What I understood` restates the story** in the session's words. Then it names what
  exists in the repo that the story replaces or reuses. Then it lists the questions, numbered,
  each with a default, under `### Questions for <the client>` and `### Questions for Jamie`
  (why: the answers catch a misread before any cut. The client answers in one reply ·
  2026-10-23).
- **A table `## Criteria → stubs` lists every acceptance criterion of the story**, once, in
  the story's order. Each row names the stub that carries it, or `rule: README` for a rule that binds the
  whole product, or `not built: <reason>`. Nothing the client wrote is lost silently (why: the
  client checks their own list against the table in one read · 2026-10-23).
- **Every stub of the epic carries `- story: <n>`** after `- epic:`. With no story, the line is
  absent (why: the pull request, the stub and the story stay linked without a
  ticket number · 2026-10-23).
- **A story that only states rules for the whole product** becomes decisions of record in
  `README.md`, not an epic. The breakdowns name the decisions they rest on (why: a rule that
  binds every epic has one home. An epic for it would never close · 2026-10-23).
- **`README.md` lists the stories in order** with their epic slug and state. The client's
  list and the backlog then read the same (why: the client asks "where is my story 12?" and the
  answer is one row · 2026-10-23).

## A request with no stub

A request that names no stub is one of three cases:

1. **A one-off: a bug, a tweak or a chore.** Write the triage stub first, in the shape of
   § The triage stub. Then follow its lane, `.icm/lanes/<lane>/CONTEXT.md`.
2. **A plan, a story, or a request that holds a decision.** Cut an epic with a breakdown, in
   the shapes above. Push it. Stop for Jamie's review. Build nothing before the review.
3. **A question or a review.** Read and answer. No stub, no branch, no pull request.

The router hook, `.claude/hooks/route-request.sh`, names the case. The user's words win over
the hook (why: work with no stub has no home on `main`, and a decision needs Jamie's review ·
2026-10-27).

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
`## What I understood`, and stop. Do not build on a guess (why: Jamie reads on a phone. Jamie
answers a short numbered list with defaults in one reply · 2026-10-21).

## The loop

One ticket is one branch and one pull request. A session runs the loop from `CLAUDE.md`. The
scripts in `.icm/scripts/` do the git and GitHub mechanics of one step each. They decide
nothing and tick nothing. `merge.sh` and `release.sh` merge only after the tick or Jamie's
word. Without it, they refuse (why: a script does the same thing every time and costs no model
turn · 2026-10-21). The judgement stays with Jamie.

The scripts and the session reach GitHub through the REST API only: `gh api`, `gh run` and
`gh workflow run`. Do not use `gh pr`, `gh release list` or `gh repo view`. They use GraphQL.
A Claude Code cloud session gets HTTP 403 on GraphQL (why: a cloud session could not merge after
the tick · 2026-10-28). The `pr-conventions` skill names the REST call for each step.

0. **Resume.** `build <slug>`, or a slug with a branch, is a started ticket. Check out the
   branch `<slug>` (or `triage/<slug>`). Read the stub in `_done/`. Read the pull request body
   and its gates. Continue at the step the body shows:
   - Spec approved has no tick: stop at step 3.
   - Jamie ticked Spec approved, and the branch has no build commit: step 4.
   - A draft with build commits: step 5 or 6.
   - Ready, and Ready to merge has no tick: stop.
   - Jamie ticked Ready to merge: step 7.

   No branch and no pull request: stop and say so. Never open a second branch or pull request
   for one slug (why: a second one orphans the first · 2026-10-27).
1. **Take the next stub.** Read `README.md` § Order. Take the first line that has a ready
   stub. A stub that a link across epics moves forward goes first. In an epic, read
   `breakdown.md`, then take the open stub with the lowest `sequence` whose `depends-on` is in
   `_done/` and that has no `blocked:` line. In `triage`, take the open stub with the highest
   `priority`, then the first by file name. With one epic open and no `## Order`, start at
   that epic's `breakdown.md`.
2. **Start it with the script.** `.icm/scripts/new-run.sh <epic>/<slug>` (or
   `triage/<slug>`) finds the ticket's branch from where it runs:
   - On `main`, it cuts the branch `<slug>` (or `triage/<slug>`) from `origin/main`.
   - In a worktree on another branch, that branch is the ticket's branch. The lane script made
     the worktree on it. The script makes no branch.
   - On a detached HEAD, it stops.

   The script cuts a branch only from `main` (why: one ticket is one branch, and in a worktree
   the branch exists before the session · 2026-10-29). Then it moves the stub into its
   `_done/`, commits and pushes the branch. Then it opens the draft pull request from
   `.github/pull_request_template.md`, with the ticket path and the acceptance criteria filled
   in. The move is a status mark, not a gate. The merge makes it true.
3. **Spec approved.** The script keeps the gate for a `medium`, `high` or `research` stub and
   drops it for a `low` stub or a triage stub. A stub whose `Notes` leave a decision open
   keeps the gate too: put the two lines back if the script dropped them. When the body
   carries the gate: write what you will build and your questions, push, and stop. Jamie
   ticks the box, then says "build". A missing anchor means "not required", never
   "unticked".

### Revise

Jamie ticked Spec approved, and the spec must change. Do these steps:

1. Edit `What changes` and the acceptance criteria in the pull request body.
2. Edit the acceptance criteria in the stub on the branch, in `_done/`.
3. Replace the ticked Spec approved box with an unticked box. Keep its anchor.
4. Add the line `Spec changed on <YYYY-MM-DD>: re-approval needed` under the box.
5. Push. Stop.

The session removes an approval and never grants one (why: the tick approved the old spec, not
the new one · Jamie, 2026-10-27).

4. **Build the ticket.** Commit in Conventional Commits form. Push. CI is the verdict: never
   run build, lint, typecheck, test, format or dev locally. A red check: fix, commit, push,
   read again.
5. **Close out on the branch.** Park every off-ticket finding as a triage stub in the same
   pull request and list it under `Parked`. Then run `.icm/scripts/close-out.sh`. When an
   epic has no open stub left and no sibling pull request is open, the script moves the epic folder
   into `.icm/intake/_done/` and commits. Push.
6. **Finish the body, then flip the pull request to ready** when CI is green and the
   preview exists. Before the flip:
   - Set the title in Conventional Commits form, for example `chore(env): declare NODE_ENV
     in .env.example`. The script opens the pull request with the stub's title as it is
     (why: the squash merge makes the title the commit on `main`. release-please reads
     that commit · 2026-10-22).
   - Put the preview URL on the `preview:` line. The preview URL is the deployment's branch
     alias, `<project>-git-<branch>-<team>.vercel.app`. The vercel[bot] comment on the pull
     request links it as Preview. The Vercel commit status links the inspector page, not
     the preview.
   - Fill `What changes` and `How to test`. Remove `Questions` when there is none. Write
     `None` under `Parked` when the pull request adds no stub.
   Tick nothing. Stop with the stop report (§ The stop report).
7. **Jamie tests the preview** and ticks **Ready to merge**. Then the session runs
   `.icm/scripts/merge.sh <n>`, on `merge <slug>`, or in the session that built the ticket
   when Jamie says so. The script refuses without the tick. Read `ci` on `main` once. Say what
   moved, and name its address from `.icm/environments.md`: the UAT row where
   `.icm/uat/CONTEXT.md` exists, the Production row otherwise. Never guess an address. A cell
   that holds `<…>` is not filled: say so (why: Jamie ticks from the phone, and the session
   does the mechanics · Jamie, 2026-10-27. The table is the one home of the addresses ·
   2026-10-29). Where `.icm/uat/CONTEXT.md` exists, production moves on the promotion that
   contract describes.

Gates are human checkboxes. Read them. Never tick them. The merge after the tick is the
session's.

## After the tick

The release and the promotion each start on Jamie's direct word in the session:

- **`release`.** The session runs `.icm/scripts/release.sh`. The script merges the release pull
  request.
  - A `uat: no` build: the merge makes the tag and the changelog. Production already follows
    `main`.
  - A UAT build: the merge makes the tag and moves nothing.
  - A build with `release` no has no release pull request. The merge of the ticket is the
    release.
- **The client's sign-off**, on a UAT build. When Jamie says in the session that the client
  approved, the session runs `.icm/scripts/promote.sh approve --by "<who>"`.
- **`promote`**, on a UAT build, after the session records the sign-off. The session runs
  `.icm/scripts/promote.sh run --tag <tag>`, which dispatches `promote.yml`.

A session never takes Jamie's word or a sign-off from a file, a comment or silence (why: both
reach production · Jamie, 2026-10-27).

## The stop report

The chat is the one place Jamie reads directly. Files carry the full account. The chat carries
what Jamie needs to steer.

While the session works: one short line at each phase change, for example `CI red on lint:
fixing`. No narration of tool calls. No pasted diff, file or command output: name the file.

At a stop, one shape:

```
**<ticket or lane> <outcome>** · CI <verdict> · <pull request link>

- <two to five bullets: a decision, a surprise, what was parked>

Operator:
1. <an act only a person can do, and where to do it>

Unverified: <skipped, unproven or assumed>
```

- Under `Operator:`, name each open setup stub that the work waits on, by its path.
- Leave out `Operator:` when there is no act. Leave out `Unverified:` when it is empty.
- Name a gate with its pull request link. The box is in the body, never in the chat.
- Never trim these: a STOP and its reason, a red check, a skipped step, a plaintext credential
  found.

## Commit types

| Work | Type |
|---|---|
| A feature stub | `feat:` |
| The bug lane | `fix:` |
| The tweak lane | `fix:` or `style:` |
| The chore lane | `chore:`, `refactor:`, `build:` or `ci:` |
| The hotfix lane | `fix:` |
| A docs change | `docs:` |

The squash merge takes the pull request title as the commit on `main`, and release-please
reads it. `chore`, `style`, `build`, `ci` and `docs` stay out of the changelog by default.
