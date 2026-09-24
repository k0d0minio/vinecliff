# Stage 03 — Build (contract)

Invoked via `/pipeline build <slug>`. The `/pipeline` router reads this file and follows it. Your
job: turn the approved spec into working code on the run's branch, then flip the run's draft PR to
open (ready for review) **and push**, so the full gate and the previews land. Reviews and the
merge are Release's job — the operator smoke-tests the preview of what you hand over and ticks
**Ready to merge** on the strength of it, so hand over only what you believe is complete.

**The cadence is blind-until-ready** (`_shared/ci.md` → the cost floor, verdict by phase): while
the PR is draft, CI owes nothing — no quality job and **no previews** — you are building blind, by
the operator's explicit decision, and that is not a defect to work around; the session's
changed-files scripts are the pre-flip check. The ready flip is the moment the machine spends: the
affected product apps preview and the advisory quality job reports. Build finishes on a clean
pre-flip check, flips, pushes, and settles the full verdict — in that order.

## Inputs (read only these)

- `.icm/_shared/stage-preamble.md` — run it **first**: it resolves the run into the working tree
  or STOPs. Never recreate a missing run.
- `.icm/runs/<slug>/02_define/output/spec.md` — the canonical spec you implement against.
- `.icm/runs/<slug>/run.md` — branch + PR pointers.
- `.icm/runs/<slug>/status.md` and `handoff.md` — where the last session stopped (the canonical
  file pack, `.icm/scripts/run-pack.sh`); then `plan.md` and `tasks.md`, which this stage owns.
- The capability-skills registry — `.icm/scripts/list-skills.sh --bare` (Level 1 only; a
  `SKILL.md` body is loaded only when one of its triggers matches a step below).
- The repo's code rules — the file `_shared/conventions.md` points at — plus the subtree
  `AGENTS.md` files, where the repo has them: the canonical code rules you must follow.
- `.icm/_shared/project-rules.md` → **Learned rules** — the constraints earlier runs paid for,
  one per error class a run fixed (`retrospective.sh` appends them at Release and at the end of
  every lane). Read them before the first edit, with the same standing as the code rules.
- `.icm/_shared/knowledge-map.md` — routes to the docs tree (`docs_path` in `.icm/project.json`).
  Read only the page(s) it names for Build: the architecture and package pages that say where
  code lives and which workspace package is the right entrypoint.
- `.icm/_shared/github.md` — the GitHub MCP calls (gate read, draft → open).
- `.icm/_shared/ci.md` — what the checks are and what green means. Step 9 depends on it.
- The specific source files named in the spec's `touches:` — those, not the whole repo.

Context budget: the Inputs table above is the budget (see `.icm/CONTEXT.md` → Layers) —
everything except the source files you actually edit. Record overruns on a one-line
`Context budget:` note in `notes.md`.

## Process

1. **Run the shared preamble** (`.icm/_shared/stage-preamble.md`) — resolve the run or STOP.
   Then the first act of every stage: `.icm/scripts/usage-snapshot.sh <slug> build start`
   (`SKIP` is fine, never a stop). Read `status.md` and `handoff.md`; set `status.md` to
   `phase: build`. Build is the **executor** pass: `.icm/scripts/select-model.sh <slug> --stage
   03_build` prints the model this session should be on (`sonnet` for ordinary work, `opus` when
   the spec's complexity is `complex`) — if the session is on a lower tier than it prints, say so
   in one line; the operator decides, nothing switches itself. A subagent this stage dispatches
   runs on the executor line, never above it.
2. **Gate-check.** Read the PR body (GitHub MCP, per `_shared/github.md`): the **Spec approved**
   checkbox must be ticked. **If it isn't, STOP** — do not build against an unapproved spec, and
   never tick the box yourself. Tell the user to settle the spec (`revise <slug> "…"` if it
   needs changing) and tick the box, then re-run Build.
3. **Stage label — project it yourself, once, after the first push that carries `notes.md`**
   (step 8): `.icm/scripts/project-labels.sh <slug> --stage auto` derives `stage:*` from which
   run outputs exist and PUTs the full set (`_shared/github.md` → Labels). No workflow does this
   any more (the cost floor) — the board moves when the session that pushed the output says so.
4. **Plan, then implement** the acceptance criteria, and only those. First act: write
   `plan.md` — the change in passes, each one layer (schema, server, UI, docs) with what "done"
   looks like — and the commit-sized queue in `tasks.md` under the definition of done the spec
   seeded. Work the queue in order; tick a task when its commit lands. A change to the data model
   loads the `database-migration` skill (`.icm/skills/database-migration/SKILL.md`): the run's
   own database (`db-branch.sh <slug> up`, `SKIP` means run no migration locally), the
   migration named by `check-migrations.sh --new`, never by hand. Follow the repo's code rules
   exactly. Keep edits minimal and focused — no drive-by refactors. Something broken or ugly that is
   **not this ticket's** → park it as a stub in `.icm/intake/triage/` (shape in
   `.icm/intake/CONTEXT.md`) and move on; never absorb it into this diff. **Cap notice:** if the
   folder then holds more than 60 active stubs (`ls .icm/intake/triage/*.md | wc -l`;
   `intake/CONTEXT.md` → Triage → cap), the stop report carries it as an `Operator:` item —
   `run triage report — triage/ holds N active stubs (cap 60)`.
   The finding is still parked either way.
   - **Tests ride along, scoped by the spec.** When the diff touches pure logic that already has
     unit tests, update them in the same commit — a knowingly-red suite never gets pushed as
     "someone else's problem". When the spec's acceptance criteria are unit-assertable (pure
     functions, validators, policy tables), write the asserting tests **from the criteria, not
     from your implementation** — that independence is the point. Do not add tests beyond the
     spec's scope, and never test the classes the repo's code rules exclude (their Testing
     section, where there is one). **Write them; don't run them** — the test run is blocked
     locally like every other gate, and the repo's quality workflow is what tells you whether
     they pass.
   - **Build does not gather requirements.** If the spec is ambiguous, or an `## Open questions`
     entry blocks an acceptance criterion, **do not** decide it here or invent an answer —
     **STOP** and send the user back to `revise <slug> "<what to change>"`, then re-run Build.
   - **Errors are recorded where they are fixed.** A CI `RED`, a `lint.sh` `PROBLEMS`, a script
     that failed, an error you hit that cost a turn to understand — each is an entry in
     `.icm/runs/<slug>/03_build/output/error.log` (the shape in Outputs): a dated `## ` header
     naming the source, the failing lines verbatim, and — once the fix landed — a `- resolved:`
     line written as a sentence the next run can act on. Add a `- rule:` line only when the fix
     is a constraint of **this repo** the next run would hit again (a nullable field every
     route must guard, a package that must be imported from one place), never for a slip.
     Release's `retrospective.sh` reads the file: a flagged rule, or a signature that recurs
     across the archive, becomes a line in `_shared/project-rules.md` → Learned rules. A clean
     run writes no `error.log` at all.
5. **Use capability skills where they apply — and only then.** The registry from Inputs lists
   each skill's triggers; when a step's work matches one, load that `SKILL.md` body and follow
   it (`security-audit` for a gate finding, `database-migration` for a schema change,
   `preview-deploy` for steps 9–12). For repeatable product work (new shared component, new
   model, route, action, notification…) prefer the matching repo skill named in
   `_shared/project-rules.md` → Capability skills over hand-rolling it. Never load a skill on the
   chance it helps: the Inputs are the budget.
6. **Self-check** each acceptance criterion; if one can't be met, note it rather than dropping it.
   Tick the satisfied criteria in the PR body (tick state lives on the PR; the text stays the
   spec's — to reword, edit `spec.md` and reconcile).
7. **Commit and push — the factory verifies, not you.** Before each commit, the zero-trust gate:
   `.icm/scripts/security-check.sh <slug>` → `RESULT: OK` (the staged change, seconds, no
   network unless a lockfile moved). `BLOCKED n` is a **STOP for that commit**: the redacted
   trace is in `03_build/output/error.log`; follow `.icm/skills/security-audit/SKILL.md` → On
   BLOCKED (remove the secret, the operator rotates it, then complete the `error.log` entry the
   gate wrote — its `- resolved:` line) — never
   `--no-verify`. Where the repo wires the same call as its git pre-commit hook it runs on its
   own. Don't run the full sweep — format, lint,
   typecheck, test, build (see Verify below). A pre-commit hook formats on commit, where the repo
   has one; the advisory quality job runs lint/typecheck/test once the head is ready; the Vercel
   preview builds the PR. Spend your turns on code. A pre-commit hook only exists in a fresh
   cloud session once the repo's dependencies are installed — if the session-start output said
   the hook is off, the commit lands unformatted. Two cheap, changed-files-only tools are the
   draft head's whole check (`_shared/ci.md` → the cost floor), where the repo wires them
   (`_shared/project-rules.md` → The factory): `.icm/scripts/format.sh` (the repo's formatter
   over the files the branch changed) before committing when the pre-commit hook is
   unavailable, and `.icm/scripts/lint.sh` (the repo's linter over the same files, each
   package's own config, the repo's warning ceiling in view) **before every push**. Both run in
   seconds, build nothing, and end in one `RESULT:` line; neither is the verdict — the deploy is.
8. **Write build notes** (`notes.md`, Outputs below) and keep the pack current: `status.md`
   (`step`, `ci`, `blocked`), `tasks.md` ticks, `decisions.md` for any decision this stage had to
   make (a spec gap — say so in Notes for Release). Commit the run files alongside the code and
   push, so the PR reflects current state and a session that resumes finds where this one is.
9. **Establish the pre-flip verdict on the draft head — Build does not flip an unread run.**

   First, the environment this branch changed, measured: `.icm/scripts/env.sh audit --changed`
   → `RESULT: OK`. `GAPS` names a key this branch added that is missing from a surface it is
   scoped to — declare it in `.env.example` (`env.sh doc <KEY>` prints the block) and tell the
   operator where the value must exist; the value is never yours. Release re-asks the same call
   as stop class 3, so a gap left here is a gap that stops the merge.

   ```bash
   .icm/scripts/ci-status.sh <slug>
   ```

   It blocks until the run settles and prints `RESULT: GREEN | RED | PENDING`, naming the tier it
   settled on (`_shared/ci.md`). On a draft head that is **nothing owed** — no quality job, zero
   previews, the call settles at once — so the verdict that matters here is the scripts': a
   `lint.sh` `PROBLEMS` or a `security-check.sh` `BLOCKED` is a RED of your own to fix before
   the flip. A draft GREEN authorises exactly one thing: the flip.
   - **GREEN** → go to step 10.
   - **RED** → this is your failure to fix, not Release's: read the failing job
     (`get_job_logs`, `failed_only: true`), record it in `error.log` (step 4), fix on the
     branch, add the entry's `- resolved:` line, push, and re-run the call. Handing
     a red branch onward wastes the reviews on code that doesn't compile. If it is
     genuinely not yours to fix, say which check and why in `## Notes for Release` — never silently.
     The `error.log` entry is the ledger of what a tool reported (`retrospective.sh` reads it at
     Release); `FAILURE.md` takes only what no tool logged — a wrong assumption, a STOP, a plan
     rewritten — and its `## Learned rules` reach `_shared/project-rules.md` through
     `close-out.sh` (`run-pack.sh --sync-rules`).
   - **PENDING** → the run didn't settle. Re-run the call. Never treat "nothing has failed yet"
     as green, and never read the verdict off a Vercel deployment event — those arrive per push
     and none of them is the verdict.

10. **Bring the base branch in before the flip — a merge commit, never a rebase (D26).**

    ```bash
    git fetch origin && git merge --no-edit origin/main     # every repo — main is the only base (D39)
    ```

    Runs are cut for disjoint surfaces, but `main` has moved since this branch was cut, and
    the place to meet it is here — on the cheap tier, before the full gate and the previews
    spend anything — not at Release step 7, where a conflict costs a full gate and a smoke.
    Resolve conflicts on this branch; **a conflict inside `.icm/runs/<slug>/` itself is a
    STOP** (someone else wrote to this run — the preamble's run-folder rule). When the branch
    carries a migration: `.icm/scripts/check-migrations.sh` → `OK` or `SKIP` here, where a
    `STALE`/`MISNAMED` costs a cheap-tier push instead of a full gate (`--apply` renames; commit
    the renames; reset the run's database — the `database-migration` skill). On a MongoDB repo
    with `database.isolation: database`, then `.icm/scripts/db-branch.sh <slug> prove` →
    `PROVEN` or `SKIP`: this branch's own migrations up → down → up on the run's database, the
    indexes restored by `down` where `migrations.reversible` is true, and a second `up` changing
    nothing. `UNPROVEN n` is a fix on this branch (a missing or incomplete `down`, a migration
    that is not idempotent), never a flip with a note. Then the branch
    as a whole through the gate once: `.icm/scripts/security-check.sh <slug> --branch` → `OK`.
    Release's step 7(a) stays as the final merge and is usually a no-op after this. A merge
    that changed code takes step 9's scripts again before flipping.

11. **Flip ready, then push.** `update_pull_request`, `draft: false` (per `_shared/github.md`),
    **then push** — an empty commit (`git commit --allow-empty -m "chore: <slug> — ready"`) when
    nothing is pending. The flip itself produces no push, and previews build per push: the
    post-flip push is what makes the full-tier run and the affected product-app previews
    materialise on a fresh head, so the full verdict can never rest on a stale draft-era green.
    Open means "reviewable"; it is not the merge authorisation.
12. **Settle the full verdict on the post-flip head** — the same `ci-status.sh <slug>` call, which
    now reports the **full gate**: the affected product-app previews with their URLs (the
    verdict) and the advisory quality job's report beside them (`_shared/project-rules.md` → The
    factory). RED here is still yours to fix — and a red advisory job is fixed too: it is a
    finding the merge never waits on, not one it may ignore.
13. **Stop.** Rewrite `handoff.md` (next: smoke the previews, tick Ready to merge, release;
    blockers, if any) and set `status.md` to `step: done · ci: GREEN`; commit and push them with
    the last change. Last act: `.icm/scripts/usage-snapshot.sh <slug> build end`. Report per
    `.icm/_shared/output.md`:

    ```
    **build <slug> done** · CI GREEN (full gate) · <PR link>

    - <what was built, in a line>
    - <anything that differs from the spec, a criterion met in an unexpected way, what was parked>

    Operator:
    1. smoke the previews: <the URLs ci-status.sh listed>
    2. tick **Ready to merge** in the body of <PR link>, then run /pipeline release <slug>
    ```

    The tick attests the manual testing, so nothing after it re-asks. A Build that STOPs mid-way
    (an unapproved spec, an unanswerable criterion, a blocked gate) writes `handoff.md` and
    `status.md` (`blocked: yes — why`) before it stops — an operator act that unblocks it is a
    Blockers line `blocked on operator: <act>` as well as an `Operator:` item — and reports the
    STOP and its reason in full (never trimmed).

## Outputs

**Run-scoped, without exception** (`.icm/_shared/stage-preamble.md` → Run-scoped isolation): every working artifact of this stage — notes, scratch
lists, intermediate results — lands under `.icm/runs/<slug>/03_build/`, on the run's own branch
`claude/<slug>` and in a working tree no other live run is using.

- Code on the run's branch, small conventional commits (`feat: <slug> — <what>`).
- A settled `GREEN` from `ci-status.sh` on the pushed head; `env.sh audit --changed` → `OK`;
  `security-check.sh <slug> --branch` → `OK`.
- The canonical file pack, current: `plan.md` (the passes), `tasks.md` (ticked as landed),
  `status.md` (`phase: build`, the step, the CI verdict), `handoff.md` (rewritten at the stop),
  `decisions.md` (anything decided here), `FAILURE.md` (what no tool logged — a STOP, a wrong
  assumption, a rewritten plan; a tool's error is an `error.log` entry, below).
- `.icm/runs/<slug>/usage.md` with the `build start` and `build end` lines.
- The PR flipped from draft to open, satisfied acceptance criteria ticked.
- `.icm/runs/<slug>/03_build/output/notes.md`:

```md
# Build notes: <slug>

- commits: <short list>
- ci: <GREEN on <sha> | RED on <check> — why it is not mine to fix>

## What changed

- <file/area>: <why>

## Acceptance criteria status

- [x] <criterion> — <how it's met>
- [ ] <criterion> — <blocked because…>

## Notes for Release

- <anything the reviews should look at closely; a check you already know will fail, and why>
```

(Release later appends its own `## Release` record to this same file — leave the file ending
clean so the append reads naturally.)

- `.icm/runs/<slug>/03_build/output/error.log` — **only when something failed on the way**
  (step 4); absent on a clean run. One entry per error, in the order they were hit:

```md
## <ISO-8601Z> <source: ci <check> | lint.sh | format.sh | session> — <what failed, one line>
<the failing lines, verbatim — the error text, the rule id, the file:line; trimmed to what
fails, never the whole log>
- resolved: <one line, a sentence the next run can act on: what was wrong and what is true now>
- rule: <optional, 1–2 lines — a constraint of THIS repo the next run would hit again; omit
  for a slip. A second line is indented two spaces.>
```

`retrospective.sh` reads it at Release, gives each entry a signature (the error class — `TS2532`,
an ESLint rule id, an errno, an exception class — never the instance), counts it across the
archive, and appends the entries that earn it to `_shared/project-rules.md` → Learned rules. The
file travels with the run into the archive, where later runs' retrospectives count it.

## Verify (owned by the factory, not this agent)

Mechanical checks are deterministic, non-AI work — they belong to the factory (a pre-commit hook
where the repo has one + CI + the Vercel preview), not to your context window. **Do not run the
full sweep — format, lint, typecheck, test, build** — the `.claude/hooks/block-local-checks.sh`
`PreToolUse` hook blocks them, where the repo ships it: push and read CI back.

- **Format / Lint / Typecheck / Test** — on a draft head, the session's changed-files scripts
  (`format.sh`, `lint.sh`); on a ready head, the repo's **advisory** quality job, named
  `… (advisory)`, reported by `ci-status.sh` and never required (`_shared/ci.md` → the cost
  floor). `required_checks` in `.icm/project.json` is empty unless the repo names something it
  still waits for — and a required check that has not appeared means CI has not started, never
  "not applicable". A pre-commit hook, where the repo has one, additionally auto-formats staged
  files.
- **Build** — the Vercel preview deploys, **from the ready flip on** (drafts are blind). These are
  **commit statuses, not check runs**: reading only the check runs is how a PR whose preview
  failed to compile looks entirely green. `.icm/_shared/ci.md` says how to read both surfaces and
  `_shared/project-rules.md` → The factory names the repo's deploy projects; `ci-status.sh` reads
  both surfaces for you.
- **Errors, recorded** — every `error.log` entry carries its `- resolved:` line, or names the
  check handed over under `_shared/ci.md`'s one exit. An entry with neither is a fix that never
  landed or a record never finished; `retrospective.sh` lists it as unresolved and learns
  nothing from it.

Build, Release and every lane gate on the settled verdict from `ci-status.sh`. The only local
exception: if you _already know_ an edit introduced a type error, fix it before pushing rather than
burning a CI round-trip — but don't kick off a full-repo sweep to go looking.

- **Security** — `security-check.sh` is the one local check that is a gate, not feedback: it
  reads the staged change (or the branch) for secrets and known-high dependencies, seconds, and
  a `BLOCKED` aborts the commit. It is local because a secret must never reach the remote at all
  — CI is too late for that one class.
