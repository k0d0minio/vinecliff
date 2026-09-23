# Stage 02 — Define (contract)

Invoked via `/pipeline new` (next intake stub), `/pipeline new <stub-name>`, or
`/pipeline revise <slug> "<what to change>"` — with or without the `/pipeline` prefix; the router
resolves the stub to a path before you start, and `revise` runs the stage preamble to adopt the
run, then jumps to step 6.
The `/pipeline` router reads this file and follows it. Your job is **one thing**: produce a spec
the human can approve, and open the run's **single feature PR** (the spine regime — one PR, one
branch from here to Release). No code here.

## Inputs (read only these)

- The user's request (the argument / conversation).
- **The intake stub, when one was passed** (`.icm/intake/<scope-slug>/<feature-slug>.md` —
  Scope's cut emits these; the router resolves bare names and next-in-batch to a concrete path).
  It pre-seeds most of the spec from settled scope.
- **The front's artifact, when it exists for the stub's scope**:
  `.icm/runs/<scope-slug>/01_scope/output/scope.md` — the settled scope as Scope wrote it: the
  source reproduced, then the addendum (assumptions, the `D-n` decisions table, out of scope, open
  for Define). **This is the scope** — carry its `D-n` ids into the spec wherever a requirement
  traces back to one, so a rule traces source → scope → stub → spec, and answer every point under
  `## Open for Define` in step 2. Don't go back to the source on its own: the addendum overrides
  parts of it. **When there is no `scope.md`, proceed without one** — Define never writes
  `scope.md` itself; it resolves what the stub and the request leave open and carries on.
- `.icm/_shared/knowledge-map.md` — from it, only the pages it names for Define: the personas,
  the initiative or objective the work advances, the relevant entity and journey pages, and the
  page describing the repository structure (to fill `touches:`). If a slice is stale — a page
  missing, moved, or contradicting what the repo does — fix it with `knowledge edit` in a separate
  PR rather than working from memory.
- `.icm/_shared/github.md` — the PR projection contract and the revise path (the mechanics are
  scripted in `new-run.sh` and `project-body.sh`; you supply only the one-line Summary).
- If revising (`revise <slug> "<what to change>"`): the existing
  `.icm/runs/<slug>/02_define/output/spec.md` and the requested change.

Do **not** load `_shared/conventions.md` (that's Build's) or read the wider codebase. A few
targeted greps to confirm where something lives are fine.

Context budget: the Inputs table above is the budget (see `.icm/CONTEXT.md` → Layers). Record
overruns on a one-line `Context budget:` note in `spec.md`.

## Process

1. **Resolve the slug — then the first act of every stage:**
   `.icm/scripts/usage-snapshot.sh <slug> define start` (`SKIP` is fine, never a stop). Define
   is the **advisor** pass: `.icm/scripts/select-model.sh <epic>/<slug> --stage 02_define`
   prints `opus` (`fable` for a research stub) — the model that writes the plan Build executes;
   if this session is on a lower tier, say so in one line and carry on (the operator decides).
   A stub's `feature-slug` is the slug; pre-seed the spec from it
   (`personas`, Problem, Proposed change, Acceptance criteria, Out of scope, the
   initiative/objective link — all carry over; `depends-on`/`sequence` are context, not spec
   fields). Define never invents a slug: a plain request with no stub behind it is new content
   and belongs in Scope — send it there rather than specifying it here.
2. **Resolve every remaining requirement here — Define is the last stage that gathers them.**
   Scope settled the business logic; your job is the spec-level residue: exact behaviour,
   `touches:`, edge cases. If something that affects _what gets built_ is still ambiguous, ask
   sharp questions (`AskUserQuestion`) until nothing is open — the stub's `Notes for Define` and
   `scope.md`'s `## Open for Define` are the first things to close. Don't invent requirements, don't
   defer decisions to Build, and don't re-ask what the stub or `scope.md` already settled. Deliberate
   deferrals go under **Out of scope**, never left open.
3. **Write the spec** to `.icm/runs/<slug>/02_define/output/spec.md` (template below) — the
   canonical spec; the PR only links to it. In **Problem**, connect the need to the
   initiative/objective it advances.
4. **Validate structurally (script, not eyeball):** `.icm/scripts/validate-spec.sh <slug>` →
   `RESULT: OK`, or fix what it lists and re-run. Heed its open-questions advisory.
5. **Open the run (script, not by hand):**

   ```bash
   .icm/scripts/new-run.sh <slug> --summary "<one plain sentence — what a user can now do>" \
       [--stub .icm/intake/<scope-slug>/<feature-slug>.md]
   ```

   It commits the run + pushes, opens the draft PR (body projected from `spec.md`), writes/extends
   `run.md`, seeds the run's canonical file pack (`run-pack.sh --init`: `tasks.md` carries the
   acceptance criteria as its definition of done, `decisions.md` the scope's `D-n` rows,
   `project.md` the pointers), projects labels, and `git mv`s the consumed stub into `_done/`.
   Pass `--stub` whenever the spec came from one. Skip the script **only** for explicitly
   throwaway work — then write `run.md` by hand. (Underlying calls: `_shared/github.md`.)
   **Then the advisor's plan:** write `plan.md` — the change in passes, one layer each, the order
   they land, what "done" looks like per pass — from the spec and the `touches:` paths; Build
   executes it and rewrites it when reality disagrees. Fill any `none` the seed left in
   `project.md`, set `status.md` (`phase: define`), write `handoff.md` ("tick Spec approved, then
   `build <slug>`"), commit and push those with the run.
   **Branch check first:** the script opens the PR from the _current_ branch. The front commits
   straight to `main`, so start from a fresh branch off the pipeline's **base branch** before
   running the script — `origin/main`, or the UAT branch where the repo declares one
   (`.icm/project.json` → `uat.branch`; `.icm/uat/CONTEXT.md`), in which case bring `origin/main`
   into it too, because the stub you are consuming was pushed to `main` — never a branch whose PR
   has already merged. The PR targets that same base; on a UAT repo the script brings `main` in
   itself when it finds it missing, and warns when the branch was not cut from the UAT branch.

6. **Revising — `revise <slug> "<what to change>"`.** The one command that changes an existing
   spec; it enters here, not at step 1. Resolve the run first (`_shared/stage-preamble.md` —
   `resolve-run.sh <slug>`; no run or PR → STOP, a spec with no PR is `new`'s job). Read
   `spec.md`, then apply the requested change with the same discipline as step 2 — if the change
   is ambiguous or leaves a criterion open, ask (`AskUserQuestion`) before writing; never guess
   what was meant. Commit, push, `validate-spec.sh <slug>` → `RESULT: OK`. Then reconcile one
   direction only (file → PR), both scripted:

   ```bash
   .icm/scripts/project-body.sh <slug> --apply [--summary "<new one-liner, only if the change alters it>"]
   .icm/scripts/project-labels.sh <slug> --stage define
   ```

   `project-body.sh --apply` is the scripted `update_pull_request`: it re-projects the whole body
   from `spec.md` exactly as `new-run.sh` did — Summary (kept from the PR unless `--summary`),
   the Spec block, the entire Acceptance criteria section with every box reset to `[ ]`, and both
   gate anchors unticked. **If the Spec approved box was ticked, it tells you so on stderr — say
   it plainly to the user: the revision re-opens the gate and the operator must re-tick it.**
   Never re-run `new-run.sh` — one PR per run.

7. **Stop.** Last act: `.icm/scripts/usage-snapshot.sh <slug> define end`. Point at the spec
   path + draft PR URL; editing the spec steers Build; **ticking
   "Spec approved" on the PR is the gate** — Build won't start without it, and you never tick it.
   The tick is **the operator's**: the business logic was settled at Scope and the business is
   not involved from this stage on — everything past here is technical implementation.

## Outputs

**Run-scoped, without exception** (`.icm/_shared/stage-preamble.md` → Run-scoped isolation): every working artifact of this stage lands under
`.icm/runs/<slug>/02_define/`, on the run's own branch `claude/<slug>` — the branch `new-run.sh`
creates (or the harness-named one it records), never `main`, never another run's branch.

`.icm/runs/<slug>/02_define/output/spec.md`:

```md
# Spec: <feature title>

- slug: <slug>
- personas: <from the repo's persona vocabulary — `personas` in .icm/project.json>
- touches: <e.g. apps/<app>, packages/<pkg>/server>
- complexity: trivial | standard | complex

## Problem

<what's wrong / missing today, and why it matters — 2–4 sentences>

## Proposed change

<what we'll build, functionally — not implementation detail>

## Acceptance criteria

- [ ] <observable, testable outcome 1>
- [ ] <outcome 2>

## Out of scope

- <things we are explicitly NOT doing this run>

## Open questions

- <only non-blocking notes, or "none" — anything affecting what gets built is decided before
  approval, or moved to Out of scope. Build will not answer it for you.>
```

Plus `run.md` (extended with `branch:` + `pr:` if the front already created it), `usage.md` with
the `define start`/`end` lines, the canonical file pack (`plan.md` written — the advisor's
passes; `tasks.md`, `decisions.md`, `project.md` seeded; `status.md` and `handoff.md` set), the
run committed and pushed, and a **draft PR** whose body and labels are projected from `spec.md`.

## Verify (before handing off)

- Acceptance criteria are observable and checkable; no open question blocks one.
- `touches:` names real paths.
- The draft PR exists, its body links to `spec.md` (no embedded copy), both gate boxes present and
  unticked, labels match the spec header; `run.md` records branch + PR.
- The run is committed and pushed — resumable from any device: `run-pack.sh <slug> --check` →
  `OK`, `plan.md` has real passes, `handoff.md` says what the operator does next.
- You stopped for human review — you did not start building.
