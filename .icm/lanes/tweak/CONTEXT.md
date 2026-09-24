# Lane — Tweak (contract)

Invoked via `/pipeline tweak "<small adjustment>"` — or `/pipeline tweak <stub-name>` to start
from a parked finding in `.icm/intake/triage/` (the router resolves the name; the stub pre-seeds
the request and `new-run.sh --stub` moves it to `triage/_done/`). A fast lane for tiny, low-risk,
already-clear changes — copy, spacing, a label, a default, a threshold. No scope, no spec, no
Spec-approved gate. **One invocation, one small PR, no gate checkbox** — the lane ends with a PR
the operator squash-merges themselves from GitHub the moment their smoke test passes; the merge
button is the gate, and nothing is left for a second invocation. If it needs a decision the user
hasn't already made, or touches data/auth/payments, it isn't a tweak — STOP and route to
`/pipeline scope` (or `bug`/`chore` if that's what it really is).

## Inputs (read only these)

- The user's request (the argument / conversation), or the triage stub.
- The repo's code rules — the file `_shared/conventions.md` points at — and the subtree
  `AGENTS.md` files, where the repo has them (sentence case, typography, tokens — most tweaks
  live in these rules).
- `.icm/_shared/project-rules.md` → **Learned rules** — the constraints earlier runs paid for;
  read them before the first edit, with the same standing as the code rules.
- `.icm/_shared/github.md` — the lane-PR regime (no gate checkboxes; a human merges in the
  GitHub UI).
- `.icm/_shared/ci.md` — what the checks are and what green means; the hand-off rests on it.
- Only the file(s) being adjusted.

Context budget: the Inputs table above is the budget (see `.icm/CONTEXT.md` → Layers).

## Process

1. **Pick a slug** — then the first act of every lane: `.icm/scripts/usage-snapshot.sh <slug> tweak start` (`SKIP` is fine, never a stop). Pick it (kebab-case) and confirm the change is fully specified by the request — a
   tweak has no open questions by definition. An open question → STOP and route. A request whose subject is a **template-owned file** — a `T` line of `.icm/MANIFEST`, or a
   canonical `.claude/` asset — is not lane work: STOP before the slug, write the template change
   request (`_shared/template-change.md`), park it, open no run.
2. **Make the adjustment** — smallest possible diff, house style, matching capability skill if one
   applies (where the repo ships one — `_shared/project-rules.md` → Capability skills). Write
   `notes.md` (template below), then open the lane PR:

   **Before the script — it commits and pushes — the zero-trust gate:**
   `.icm/scripts/security-check.sh <slug> --branch` → `RESULT: OK`. `BLOCKED n` is a STOP for
   the push: the redacted trace is in `lane/output/error.log`; follow
   `.icm/skills/security-audit/SKILL.md` → On BLOCKED — never `--no-verify`. The script also
   seeds the run's canonical file pack (`run-pack.sh --init`); a lane keeps `status.md` and
   `FAILURE.md` current (`error.log` takes what a tool reported; `FAILURE.md` what no tool
   logged) and leaves `handoff.md`
   to say "PR open — smoke, then squash-merge from GitHub".

   ```bash
   .icm/scripts/new-run.sh <slug> --lane tweak --summary "<the adjustment in one sentence>" \
     [--stub .icm/intake/triage/<name>.md]
   ```

   It commits `.icm/runs/<slug>/`, pushes, opens a **draft** PR (body: Summary with a
   `- slug:` line, Steps to test — **no checklist**), and labels it `type:tweak`.

3. **Settle the cheap tier.** `ci-status.sh <slug>` on the draft head → `GREEN`. `RED` → record
   it in `.icm/runs/<slug>/lane/output/error.log` (the shape in `stages/03_build/CONTEXT.md` →
   Outputs: a dated `## ` header, the failing lines, a `- resolved:` line once fixed, a
   `- rule:` line only for a constraint of this repo), fix on the branch, push, re-run the
   call. `PENDING` → re-run it; nothing-has-failed-yet is not green.
   The one blocking script call is the only CI read — lane PRs, like every pipeline PR, are
   **never subscribed to PR activity** (`_shared/github.md` → PR events).
4. **Finish the run on the branch, while the PR is still draft.** If the change is user-visible
   enough to announce, write the repo's changelog page (`_shared/project-rules.md` → Announcing
   names where it lives and the skill that owns its shape; a repo with no changelog records
   `announce: none`) — otherwise record `not warranted` in `notes.md`. Run the retrospective —
   `.icm/scripts/retrospective.sh <slug>`: `SKIP` or `NONE` → carry on; `CANDIDATES n` → read
   them, re-run with `--apply`, delete any that reads as a slip, and commit the appended rules
   with `notes.md` (its `- learned:` line) before the close-out. Then run the close-out:

   Record the lane's end first — `.icm/scripts/usage-snapshot.sh <slug> tweak end` — so the
   line rides in the close-out commit: nothing written after the close-out reaches the PR. Then
   run the close-out:

   ```bash
   .icm/scripts/close-out.sh <slug>
   ```

   It `git mv`s `.icm/runs/<slug>/` into the runs archive (`runs_archive` in `.icm/project.json`;
   `.icm/runs/_done/` by default) and commits that on the branch (the triage stub, if any, is
   already in `triage/_done/` from `new-run.sh`). `RESULT: CLOSED` → push; `RESULT: STOP` → read
   the reason and fix it. Push, then `ci-status.sh <slug>` once more → `GREEN` (the repo's
   required check(s) — `required_checks` in `.icm/project.json` — carry the verdict on a
   docs-only push).

5. **STOP.** Report per `.icm/_shared/output.md`:

   ```
   **tweak <slug> ready** · CI GREEN · <PR link>

   - <what changed, in a line>
   - <anything parked in triage, or a surprise the operator should know>

   Operator:
   1. smoke the previews: <the URLs ci-status.sh printed>
   2. squash-merge the PR from GitHub
   ```

   You do not merge lane PRs and you do not re-invoke the lane — the operator's merge click is
   the gate. After their merge the repo's reporting hook
   announces — `report.sh announce`, called by the repo's release workflow where
   `reporting.announce_from` is `ci`, and by the operator by hand (or not at all) where it is
   `session` (`_shared/project-rules.md` → Reporting); a lane never calls it, never waits, and
   never watches production. On a UAT repo the merge into `main` puts the change on the
   client's UAT address, and the announcement waits for the batch's promotion
   (`_shared/promotion.md`). The usage `end` line was written
   just before the close-out (above); nothing is written now. If you
   parked a finding in `.icm/intake/triage/` on the way and the folder now holds more than 60
   active stubs (`ls .icm/intake/triage/*.md | wc -l`; `intake/CONTEXT.md` → Triage → cap), add
   `run triage report — triage/ holds N active stubs (cap 60)` to `Operator:`.

## Outputs

**Run-scoped, without exception** (`.icm/_shared/stage-preamble.md` → Run-scoped isolation): everything this lane writes while working lands under
`.icm/runs/<slug>/lane/`, on the run's own branch `claude/<slug>`.

`.icm/runs/<slug>/run.md` (with `- lane: tweak`), `.icm/runs/<slug>/usage.md` (the `tweak start`/`end` lines) and
`.icm/runs/<slug>/lane/output/notes.md` — both archived to the runs archive (`runs_archive` in
`.icm/project.json`; `.icm/runs/_done/` by default) under `<slug>/` by step 4:

```md
# Tweak: <slug>

- change: <file/area>: <before → after, one line>
- changelog: <entry added | not warranted | announce: none>
- learned: <n rule(s) appended to _shared/project-rules.md | none>
```

## Verify

- The diff is as small as the request; nothing was decided on the user's behalf.
- One PR, `type:tweak`, no gate checkboxes in its body; you never merged it and never re-invoked
  the lane.
- Everything the run owed was committed **before** the flip, and the push followed it
  immediately — the PR was never mergeable while incomplete, and that post-flip push is what built
  the previews.
- The full gate settled on the flipped head — `GREEN`, or a `RED` handed over under
  `_shared/ci.md`'s one exit with the check named, a stub parked and `notes.md` recording it.
  Never a verdict inherited from an earlier head, and never `GREEN` claimed for either.
- The changelog page is in the PR, or `notes.md` records it as not warranted (or
  `announce: none`, where the repo has no changelog).
- `retrospective.sh` ran before the close-out, on the live run folder; `close-out.sh` reported
  `CLOSED` and its commit is pushed on the PR's head — the archive move rides in the PR, so the
  merge publishes it.
