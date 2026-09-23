# Intake — the batch formats, triage, and the archive rules

`.icm/intake/` holds the sequenced batches of feature **stubs** that `/pipeline new` walks into
Define — one folder per scope, one stub per future run / future PR — plus the `triage/` parking
lane. This file owns the **formats** (breakdown and stub), the **triage** shape, and what happens
**after the batch**. How a batch is cut — the seams, the build order, `validate-intake.sh` — is
the Scope stage's job and lives in `.icm/stages/01_scope/CONTEXT.md` (step 6). There is no
`/pipeline decompose` subcommand; the cut is the last thing Scope does.

The stub folder is the only state (no branch or run PR of its own); Scope lands it with
`scope.md` through one ticket PR into the repo's **ticket base branch**. Re-cutting after the human edits `breakdown.md` regenerates the stubs. **Every scope
gets an intake folder, however small** — a single-PR scope gets exactly one stub whose
`feature-slug` is the scope slug itself.

**Where ticket state lives (D38).** This folder has one home: the **ticket base branch** —
`lib/project.sh → pipeline_base_branch`, the UAT branch where `.icm/project.json` declares one,
else `main`. The board and every script that reads the queue read it there; on a UAT repo `main`
carries a lagging copy that only promotions update, and nothing reads it for tickets. Every write
reaches it through a PR: inside a run, the run's own PR (the stub it consumes, the triage stubs it
parks, the close-out's archive move); outside a run — a cut, a drop, a `_done/` move, a parked
finding, a `triage batch` or `prune` — a **ticket PR** the session merges at once
(`.claude/skills/pr-conventions/SKILL.md` → The ticket PR). Never a direct push. The hotfix lane
and the knowledge lane merge into `main`, so on a UAT repo what they move reaches this home only
through `promote-uat.sh sync` (`.icm/uat/CONTEXT.md`).

One audit may write here too, where the repo ships one (`_shared/project-rules.md` → Capability
skills): a codebase-audit skill fired daily by a Claude Routine parks **at most one** finding a day
in `triage/` — the triage stub shape below, `found-by: codebase-audit · <date>`, on its own
one-file PR — and never cuts an epic of its own. There is no story and no `scope.md` behind it; a
quiet day writes nothing.

Two scripts may write here as well. `.icm/scripts/process-raw.sh` turns each client asset dropped in
`.icm/raw/` into extracted text under `.icm/processed/` and parks **one triage stub per asset** —
the triage shape below, `lane: chore`, `found-by: process-raw · <date>`, `complexity: research` —
so an email or a voice note that arrived is on the board until somebody scopes it
(`.icm/raw/README.md`). The stub is a pointer, never a cut: it names the processed file as a
source for `/pipeline scope`, and Scope retires it to `triage/_done/` with a `- superseded-by:`
line when it records that source (`stages/01_scope/CONTEXT.md` step 2). Nothing is scoped, split or
sequenced by a script.

`.icm/scripts/health-check.sh`, when production fails its one post-merge read (Release step 9a),
writes **one stub per merge SHA** — `triage/health-check-<date>-<short-sha>.md`, the triage shape
below, `lane: bug`, `found-by: health-check · <date>`, `complexity: high` — carrying the endpoint,
the code each attempt saw, the merge SHA and the recoveries `rollback.sh` prepares. It writes
the file and commits nothing: the stage names it in its stop message and the operator decides —
land it for the bug lane (a ticket PR), or open `/pipeline hotfix` by hand. Nothing parks a stub for the
hotfix lane.

A **template change request** is parked here too (`_shared/template-change.md`): when a request
in this repo would change a template-owned file — a `T` line of `.icm/MANIFEST`, or a canonical
`.claude/` asset — the session writes no edit but one stub, `triage/template-change-<what>.md`,
the triage shape below, `lane: chore`, `found-by: template-change · <date>`, whose `## Prompt` is
the self-contained request for an icm-board session. It is a pointer, never a cut, and **no lane
in this repo consumes it** — a chore run on it would be the edit the rule forbids; the board's
"Copy prompt" hands it over, and the commit that brings the changed file back (the sync) retires
it to `triage/_done/` with a `- superseded-by: icm-board <PR or commit>` line.

**`.icm/intake/triage/` is the third resident** — the parking lane for off-ticket findings, with
its own lighter stub shape (see **Triage** below). It is a permanent backlog folder, not an epic:
no breakdown, no sequence, never walked by `/pipeline new`, never archived.

## Formats

`.icm/intake/<scope-slug>/breakdown.md` — the single review surface:

```md
# Breakdown: <scope title>

- scope-slug: <slug> · story: runs/<slug>/01_scope/\_source/story.md
- initiative: <name> / objective: <current-Q objective>
- personas: <from the repo's persona vocabulary — `personas` in .icm/project.json>

## What I understood

<3–6 sentences restating the intent — so a misread is caught before the cuts>

## Where it sits

<the journey step(s) + entity(ies) this touches, named as the knowledge map's pages name them>

## Build order

<The exact order `/pipeline new` walks — a strict total order, one stub per line.>

1. <feature-slug> — <one line> — depends-on: <none / other feature-slugs>
2. <feature-slug> — <one line> — depends-on: <…>

## Parallelizable

<Derived, never asserted (decision D26): a parallel set holds only stubs whose `touches:`
guesses do not overlap; omit if a plain chain. See "Parallelizable is derived" below.>

## Out of scope (whole scope)

- <carried from `scope.md` — what no stub covers this round>
```

`.icm/intake/<scope-slug>/<feature-slug>.md` — one per feature. The **handoff contract**:
fields map mechanically onto Define's `spec.md`.

```md
# Stub: <feature title>

- feature-slug: <kebab>
- scope: <scope-slug>
- personas: <from the repo's persona vocabulary>
- initiative: <name> / objective: <current-Q objective>
- depends-on: <other feature-slugs, or none>
- sequence: <n of m> # what `/pipeline new` reads to find "next"
- complexity: <low | medium | high | research> # optional — carried from scope.md, sharpened per stub
- recommended-model: <sonnet | opus | fable> # optional — what `select-model.sh` prints, or the operator's override

## Problem

<one-liner → seeds the spec's Problem; connect to the objective it advances>

## Proposed change

<what we'll build, functionally — not implementation detail>

## Acceptance criteria (rough)

- [ ] <observable, testable outcome>

## Out of scope (this feature)

- <things this feature explicitly won't do>

## Notes for Define

<scope-level decisions Define must honour (name the `D-n` behind each) and any point left under
`## Open for Define` in scope.md that lands here; optional `touches:` guess>
```

**`## Parallelizable` is derived from `- touches:`, never asserted (decision D26).** Runs
are cut for disjointness: a parallel set contains only stubs whose optional `touches:`
guesses (in `Notes for Define`) do not overlap; two stubs that share a surface are sequenced,
not parallelised. **The shared-file stubs go first in the build order** — the ones that touch
the dependency manifest and lockfile (`pnpm-lock.yaml` conflicted 120 times in sustentus's
last 300 commits, more than every other file combined), the schema and the migrations
journal (`schema.ts` and `meta/_journal.json` lead remi-ai's list), the app layouts
(`app/**/layout.tsx`) and the message catalogues — because every later stub merges over
them. A stub with no `touches:` guess is sequenced after the ones that have one. Nothing
here is a script: Scope reads the guesses and writes the section; `new-run.sh` warns when a
new run's `touches:` overlaps a live run's; the operator decides.

**`complexity` and `recommended-model` are optional, and older stubs carry neither.** Where they are
present, `.icm/scripts/select-model.sh <epic>/<feature-slug>` reads them and prints the model the
session that picks the stub up should be opened on — `sonnet` for `low`/`medium`, `opus` for
`high`, `fable` for `research`; an explicit `recommended-model` wins; a stub with neither reads as
`medium`. Add `--stage 02_define` (the advisor pass — `opus`) or `--stage 03_build` (the executor
— `sonnet` unless `high`) and it prints the harness flag for that pass. It prints a
recommendation and starts nothing (`_shared/scope-template.md` → Complexity and the model). The stub's word seeds Define's own `complexity:` in `spec.md`, which keeps its own
vocabulary because the labels depend on it: `low → trivial`, `medium → standard`, `high → complex`;
a `research` stub is a spike, and Define sets the spec's complexity from what the spike is.

The order invariants — `sequence` unique and contiguous over the whole batch (`_done/` included),
`of m` matching the stub count, every `depends-on` naming an in-batch stub sequenced first,
`## Build order` and the stubs' `sequence:` agreeing — are checked by
`.icm/scripts/validate-intake.sh <scope-slug>` → `RESULT: OK`. Scope runs it before pushing; a
repo whose CI re-runs it advisorily on any PR touching `.icm/intake/**` (`_shared/project-rules.md`
→ The factory says whether this one does) is what catches a later hand-edit to `breakdown.md`.

## Triage — the parking lane (`.icm/intake/triage/`)

The pipeline's rule for anything found that is **not the current ticket's** — a review finding
Release won't fix pre-merge, a wart Build steps around, a paper cut anyone spots in passing — is:
**park it here as one small stub and move on.** Never widen a PR to absorb it, never lose it in a
conversation. Writing the stub costs a minute; that is the whole point.

`.icm/intake/triage/<kebab-name>.md`:

```md
# Stub: <title>

- lane: bug | tweak | chore
- found-by: <run slug / review / audit / conversation> · <YYYY-MM-DD>
- complexity: <low | medium | high | research> # optional — read by `select-model.sh`

## Problem

<observed, one or two lines; file paths if known>

## Proposed change

<one line — or "investigate", if the fix isn't obvious>
```

Rules of the folder:

- **No breakdown, no `sequence:`, no `depends-on`** — it is a backlog, not a batch.
  `validate-intake.sh` checks only that each stub carries a valid `lane:` line.
- **Consumed by the lanes, not by `new`**: `/pipeline bug|tweak|chore <stub-name>` resolves the
  stub, pre-seeds the lane from it, and `new-run.sh --stub` moves it to `triage/_done/`.
- An entry nobody will ever pick up is deleted, not hoarded — the human prunes, the agent only
  adds and consumes (`triage prune` below lists the candidates; it never deletes).
- The folder itself is **never archived**: `close-out.sh` skips it in the epic scan even when it
  is empty.
- **Cap: 60 active stubs** (top-level `.md` files; `_done/` does not count). Over the cap, every
  stage or lane that parks a finding says so in its stop message — one line,
  `triage/ holds N active stubs (cap 60) — run triage report` — and `triage report` is the
  suggested next command. The cap changes nothing else: the finding is still parked (a PR is
  never widened to dodge the notice), the lanes still consume, `new` still never reads the
  folder. The number lives here; `triage-report.sh` carries it as its `--cap` default and prints
  the verdict.

### Managing the backlog — `triage report | batch | prune`

The folder has one reader of its own, `.icm/scripts/triage-report.sh`, and three verbs on the
router (`.claude/skills/pipeline/SKILL.md` → Resolving `triage`). None of them opens a run or a
PR; `batch` writes an intake epic, the others only read.

- **`triage report`** — runs `.icm/scripts/triage-report.sh` and shows its markdown: active and
  `_done/` counts against the cap, counts by lane, by found-by source (which Release review
  pass, Build, a lane, an audit), by area (the `apps/<app>` / `packages/<pkg>` / `.icm` /
  `.github` / `.claude` paths each stub cites) and by age (days since the found-by date, with
  the over-30-days names listed), then the near-duplicates: titles sharing four or more
  significant words, and stubs citing the same `file:line`. Deterministic — same folder, same
  `--today`, same output; last line `RESULT: OK — …`. Read it before `batch` or `prune`, and
  whenever a stop message says the folder is over its cap.
- **`triage batch <area|lane> "<epic-title>"`** — the way findings leave this folder as a
  **planned** batch instead of one lane PR at a time. The selector is an area from the report
  (`apps/<app>`, `packages/<pkg>`, `.icm`, `.github`, …) or a lane (`bug` / `tweak` / `chore`).
  The agent reads every matching active stub, **drops the duplicates first** — each superseded
  stub is `git mv`'d to `_done/` with a line added under its `found-by:`,
  `- superseded-by: <surviving-stub>.md — <why>` — then cuts the survivors into a normal intake epic
  `.icm/intake/<epic-slug>/` (slug from the title) with `breakdown.md` and sequenced stubs in the
  **Formats** above: one feature stub per shippable unit, grouping several small findings where
  one PR would fix them together, `feature-slug` fixed at the cut, `depends-on` where a fix rests
  on another, `sequence: n of m`. The originals move to `triage/_done/` with a
  `- superseded-by: <epic-slug>/<feature-slug>.md` line, so the report stops counting them and
  the trail survives. Then `.icm/scripts/validate-intake.sh <epic-slug>` → `RESULT: OK`, and
  the agent **stops** — the epic is the review surface; `new` walks it once the human has read
  `breakdown.md`. There is no story and no `scope.md` behind such an epic; the `story:` slot of
  `breakdown.md`'s header line reads
  `none — cut from triage/ by triage batch <selector>`. A `batch` that finds product decisions inside a stub leaves
  that stub in place and says so; it does not decide.
- **`triage prune`** — lists, for the human, the stubs older than 30 days (found-by date) and
  the ones that look superseded: a title sharing four or more significant words with another
  stub, the same `file:line` cited elsewhere, or a body naming a run or PR that has since
  merged. One line per candidate — name, age, the reason — and the exact `git rm` for each.
  **It never deletes.** The human confirms name by name; the agent then runs only the deletions
  confirmed, in one commit on one ticket PR, and nothing else. A candidate that is a duplicate rather than dead
  is better retired with a `superseded-by:` line into `_done/` (as `batch` does) than removed.

## After the batch

`/pipeline new` consumes stubs one at a time into `_done/`. When the last stub has been spun out
**and** every one of those runs has merged, the epic folder is archived to the intake archive
(`intake_archive` in `.icm/project.json`; `.icm/intake/_done/` by default) under
`<scope-slug>/` — breakdown, `_done/` stubs and `_source/` intact. `.icm/intake/` therefore holds
only epics with work left in them.

**`_done/` alone is not the signal: it means spun out, not shipped** — the two ends of a stub's
life sit in different stages. Define moves it into `_done/` when the run opens (`new-run.sh
--stub`); the epic is archived by `.icm/scripts/close-out.sh`, run on the branch by the Release
that merges the batch's final run, which is why the script re-checks each sibling's PR rather than
trusting the folder. That final run is excluded from its own sibling check — it is the one merging
now, and its merge is what publishes the epic's move. Neither end is a later cleanup pass.
