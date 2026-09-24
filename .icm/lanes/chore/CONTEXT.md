# Lane — Chore (contract)

Invoked via `/pipeline chore "<task>"` — or `/pipeline chore <stub-name>` to start from a parked
finding in `.icm/intake/triage/` (the router resolves the name; the stub pre-seeds the task and
`new-run.sh --stub` moves it to `triage/_done/`). A fast lane for work with **no user-facing
behaviour change**: refactors, dependency bumps, migrations, cleanups, CI/tooling. No scope, no
spec, no Spec-approved gate. **One invocation, one PR, no gate checkbox** — the lane ends with a
PR the operator squash-merges themselves from GitHub the moment their smoke test passes; the
merge button is the gate, and nothing is left for a second invocation. If behaviour would change
for any persona, it's not a chore — route to the spine (or `bug`).

## Inputs (read only these)

- The user's request (the argument / conversation), or the triage stub.
- The repo's code rules — the file `_shared/conventions.md` points at — and the subtree
  `AGENTS.md` files, where the repo has them.
- `.icm/_shared/project-rules.md` → **Learned rules** — the constraints earlier runs paid for;
  read them before the first edit, with the same standing as the code rules.
- `.icm/_shared/github.md` — the lane-PR regime (no gate checkboxes; a human merges in the
  GitHub UI).
- `.icm/_shared/ci.md` — what the checks are and what green means; the hand-off rests on it.
- Only the source the task names. For a migration (symmetric `up`/`down`) or schema-adjacent
  work: the matching capability skill, where the repo ships one (`_shared/project-rules.md` →
  Capability skills).

Context budget: the Inputs table above is the budget (see `.icm/CONTEXT.md` → Layers).

## Process

1. **Pick a slug** — then the first act of every lane: `.icm/scripts/usage-snapshot.sh <slug> chore start` (`SKIP` is fine, never a stop). Pick it (kebab-case) and state the invariant: what must be true before and after
   (behaviour unchanged; only <X> differs). A dep bump names the version delta; a refactor names
   the shape change; a migration names the data delta and its `down`. A request whose subject is a **template-owned file** — a `T` line of `.icm/MANIFEST`, or a
   canonical `.claude/` asset — is not lane work: STOP before the slug, write the template change
   request (`_shared/template-change.md`), park it, open no run.
2. **Do the work** with the matching capability skill where one exists. Keep it single-purpose —
   a chore PR that also "fixes a few things on the way" is two PRs pretending to be one. Write
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
   .icm/scripts/new-run.sh <slug> --lane chore --summary "<the invariant in one sentence>" \
     [--stub .icm/intake/triage/<name>.md]
   ```

   It commits `.icm/runs/<slug>/`, pushes, opens a **draft** PR (body: Summary with a
   `- slug:` line, Steps to test — **no checklist**), and labels it `type:chore`.

3. **Settle the cheap tier.** `ci-status.sh <slug>` on the draft head → `GREEN`. `RED` → record
   it in `.icm/runs/<slug>/lane/output/error.log` (the shape in `stages/03_build/CONTEXT.md` →
   Outputs: a dated `## ` header, the failing lines, a `- resolved:` line once fixed, a
   `- rule:` line only for a constraint of this repo), fix on the branch, push, re-run the
   call. `PENDING` → re-run it; nothing-has-failed-yet is not green.
   The one blocking script call is the only CI read — lane PRs, like every pipeline PR, are
   **never subscribed to PR activity** (`_shared/github.md` → PR events).
4. **Finish the run on the branch, while the PR is still draft.** Chores never write a changelog
   page (no user-facing change to announce). Run the retrospective —
   `.icm/scripts/retrospective.sh <slug>`: `SKIP` or `NONE` → carry on; `CANDIDATES n` → read
   them, re-run with `--apply`, delete any that reads as a slip, and commit the appended rules
   with `notes.md` (its `- learned:` line) before the close-out. Then run the close-out:

   Record the lane's end first — `.icm/scripts/usage-snapshot.sh <slug> chore end` — so the
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
   **chore <slug> ready** · CI GREEN · <PR link>

   - <what changed, and the invariant held>
   - <anything parked in triage, or a surprise the operator should know>

   Operator:
   1. <if a product app built> smoke the previews: <the URLs ci-status.sh printed>
   2. squash-merge the PR from GitHub
   ```

   You do not merge lane PRs and you do not re-invoke the lane — the operator's merge click is
   the gate. A chore announces nothing (the reporting hook
   is for user-visible change — `_shared/project-rules.md` → Reporting); nothing watches the
   merge. On a UAT repo the merge reaches UAT, and production with the batch's
   promotion (`_shared/promotion.md`). The usage `end` line was written
   just before the close-out (above); nothing is written now. If you
   parked a finding in `.icm/intake/triage/` on the way and the folder now holds more than 60
   active stubs (`ls .icm/intake/triage/*.md | wc -l`; `intake/CONTEXT.md` → Triage → cap), add
   `run triage report — triage/ holds N active stubs (cap 60)` to `Operator:`.

## Outputs

**Run-scoped, without exception** (`.icm/_shared/stage-preamble.md` → Run-scoped isolation): everything this lane writes while working lands under
`.icm/runs/<slug>/lane/`, on the run's own branch `claude/<slug>`.

`.icm/runs/<slug>/run.md` (with `- lane: chore`), `.icm/runs/<slug>/usage.md` (the `chore start`/`end` lines) and
`.icm/runs/<slug>/lane/output/notes.md` — both archived to the runs archive (`runs_archive` in
`.icm/project.json`; `.icm/runs/_done/` by default) under `<slug>/` by step 4:

```md
# Chore: <slug>

- invariant: <behaviour unchanged; what differs>
- change: <file/area>: <what and why>
- rollback: <migration down / revert — how this is undone if needed. Not a revert by a
  session's own decision: a revert is the hotfix lane's, prepared by `rollback.sh` and merged
  by the operator (`lanes/hotfix/CONTEXT.md`); a forward-only repo (`migrations.reversible:
  false`) names how the reverted code tolerates the newer schema instead of a `down`>
- learned: <n rule(s) appended to _shared/project-rules.md | none>
```

## Verify

- No user-facing behaviour changed; the invariant holds. Migrations have a working `down` where
  the repo declares `migrations.reversible: true` (forward-only repos say how the code tolerates
  the schema instead); new env vars are declared and present where they are scoped —
  `.icm/scripts/env.sh audit --changed` → `OK` before the flip.
- One PR, `type:chore`, no gate checkboxes in its body; you never merged it and never re-invoked
  the lane.
- Everything the run owed was committed **before** the flip, and the push followed it
  immediately — the PR was never mergeable while incomplete, and that post-flip push is what built
  the previews.
- The full gate settled on the flipped head, the migration checks (where the repo has them)
  included — `GREEN`, or a `RED` handed over under `_shared/ci.md`'s one exit with the check
  named, a stub parked and `notes.md` recording it.
  Never a verdict inherited from an earlier head, and never `GREEN` claimed for either.
- No changelog page: a chore has nothing to announce, and `notes.md` says what changed instead.
- `retrospective.sh` ran before the close-out, on the live run folder; `close-out.sh` reported
  `CLOSED` and its commit is pushed on the PR's head — the archive move rides in the PR, so the
  merge publishes it.
