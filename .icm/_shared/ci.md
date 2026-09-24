# CI — what green means (Layer 3 reference)

The single home for **reading the factory's verdict**. Build, Release and every lane gate on
CI; this file says how a check is classified, which ones are signal, and what counts as a verdict.
Stage contracts reference it — they never restate the check names, because the check names change
and a copy would rot. The names themselves are the repo's own: `required_checks` and `smoke_check`
in `.icm/project.json`, written up in `_shared/project-rules.md` → The factory.

The rule the whole file exists to enforce: **a stage never merges, hands off, or declares done on a
verdict it did not actually establish.** Not-yet-red is not green.

## What CI is for — the cost floor (decision D43)

GitHub bills Actions **per job, rounded up to a whole minute**, and only on private
repositories — a ten-second label job costs the same minute as a ten-second lint, and a
workflow that fires on every push to every PR spends its minutes whether or not it had anything
to say. The estate's answer is one shape for every repo, public and private alike, so nothing
changes when a repo's visibility does:

| Belongs in CI                                                                                                                                                                                                       | Does not                                                                                                                                                                                                                                                 |
| ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **The deploy** — Vercel's build of the PR head, read as a commit status. It is the verdict, and it costs no Actions minute.                                                                                          | A `build` step — Vercel already built it.                                                                                                                                                                                                                |
| **One advisory quality job** on a **ready** head only — lint, typecheck, unit tests — named `… (advisory)`: reported by `ci-status.sh`, never required, never waited on by the merge.                                | The same job on a draft head, on `main` after a merge, or on a diff of `.icm/**` and markdown only.                                                                                                                                                      |
| **What needs a secret, a runner or a clock the session does not have** — a production migration behind its environment gate, a preview database made per PR, a nightly audit, a cleanup on PR close, the release workflow. | The pipeline's own chores — label projection, spec / intake / knowledge-map validation, gate reading. The session runs the same scripts (`project-labels.sh`, `validate-*.sh`) at the step that changes the thing; the gate is read from the PR body. |
| A browser walk **only where a client pays for its minutes**.                                                                                                                                                        | Everywhere else the walk is the operator's, at Ready-to-merge, from the preview URL `ci-status.sh` printed — and anything that fires on every commit status or every PR edit "to be safe".                                                             |

So on the typical repo a PR carries **the deploy status** (blocking, and on a ruleset where the
plan allows one) and **one advisory job on a ready head**, and `required_checks` in
`.icm/project.json` is **empty**. A draft head owes CI nothing: its pre-flip check is the
session's changed-files scripts (`format.sh`, `lint.sh`, `security-check.sh`), and
`ci-status.sh` on a draft settles at once on zero signals — GREEN there means "nothing owed,
nothing red", and authorises only the flip. The full gate is the ready head's: the previews'
statuses, and the advisory job's report beside them.

Two rules keep the shape honest:

- **Advisory is not optional.** A red advisory job is a finding: read at the stop, fixed on the
  branch like any other, named in the stop report. `ci-status.sh` lists it under its own heading.
  What "advisory" changes is only that the merge never waits on it — the deploy is what the merge
  waits on, and a ruleset requires the deploy status or nothing.
- **Never add a workflow "because it is cheap".** Every job is a minute; every trigger is a run.
  A new workflow is a template change request (`_shared/template-change.md`) or, for a
  project-owned file, a line in `_shared/project-rules.md` → The factory saying what it costs and
  what it buys. `setup.sh` names the retired chore workflows (`pipeline`, `gates`, `labels`) and
  a quality workflow that still fires on `push: main` or on drafts, for the operator to remove.

## Two surfaces, and you must read both

GitHub reports a commit's health in **two separate places**, and the pipeline's most important
signal is split across them:

| Surface             | API                         | GitHub MCP                           | What lands here                                          |
| ------------------- | --------------------------- | ------------------------------------ | -------------------------------------------------------- |
| **Check runs**      | `/commits/<sha>/check-runs` | `pull_request_read` `get_check_runs` | GitHub Actions jobs — the repo's workflows               |
| **Commit statuses** | `/commits/<sha>/status`     | `pull_request_read` `get_status`     | **Vercel deploys** — the previews, one per deploy project |

**Reading only `get_check_runs` is the classic mistake**: the Vercel builds are not check runs, so
a PR whose preview failed to compile still shows every check run green. If a stage's decision
depends on the preview — the operator's pre-tick smoke, Release's merge — it must read the
statuses too.

## The inventory — signal, advisory, noise

### Check runs

The check runs a PR carries are the repo's own — its advisory quality job, whatever conditional
jobs it wires (database migrations, audits), and a smoke check where a client pays for one. This
file does not list them: the names `ci-status.sh` waits for are `required_checks` in
`.icm/project.json` — **empty by default** (the cost floor above) — and what each one runs, and
on which tier, is written up in `_shared/project-rules.md` → The factory.

Three things hold for every repo, whatever its inventory:

- **A required check's absence is never "not applicable".** If it has not appeared, CI has not
  started. A check that is safe to require in branch protection runs on **every** PR and
  short-circuits to success on a diff it has nothing to say about (markdown-only, `.icm/**`-only),
  rather than being left out by a path filter — a required check that a path filter skips hangs
  every PR that did not trigger it. An **advisory** job is under no such rule: nothing waits on
  it, so it path-filters freely and skips drafts, which is exactly what makes it cheap.
- **A check run is named after its job, not its workflow.** Match on the job name — that is what
  appears on the PR, what branch protection requires, and what `required_checks` lists.
- **`Vercel Preview Comments` is noise.** Not a build. A zero-second, always-`success` marker that
  Vercel's comment bot is wired up. It carries no information about whether anything compiled.
  **Never** read it as the preview's verdict, and never report it. Its name sounds like the smoke
  check's, and only one of the two looked at a page.

#### The smoke check is required conditionally, and that conditionality is the point

A browser walk in CI is the one exception the cost floor names — only where a client pays for its
minutes. Everywhere else the walk is the operator's, at Ready-to-merge, from the preview URL
`ci-status.sh` printed, and `smoke_check` is absent from `.icm/project.json`. Where one is
declared, the rest of this section holds.

A repo that declares a smoke check — `smoke_check` in `.icm/project.json`, an object of `name`
(the check run), `workflow` (the file that creates it) and `preview_status` (the deploy status it
walks) — has the one check that does not exist on every PR, because it cannot: it needs a preview
to walk.

- **Draft head** → the previews are suppressed, so nothing runs and **no check run is created at
  all**. The absence is the report.
- **Ready head, the preview skipped by the deploy's ignore step** → same: there is no preview for
  that commit, so there is nothing to smoke.
- **Ready head, the preview really built** → the walk is owed, and `ci-status.sh` requires the
  check from that moment. Outstanding is `PENDING`, not `GREEN`; failed is `RED`.

`ci-status.sh` derives that requirement per pass from the signals it has already read — a ready
head, from this repo rather than a fork, plus the `smoke_check.preview_status` status in the
`blocking`/`pass` class — rather than carrying the smoke check in `required_checks` or
`PIPELINE_REQUIRED_CHECKS`, which would demand it on every PR and hang forever on the ones that are
never owed one. It also asks the default branch, once, whether `smoke_check.workflow` is there: a
workflow not yet merged produces no check, and requiring one that cannot exist would hang every
ready PR at `PENDING`, the PR introducing the workflow first among them. A repo with no
`smoke_check` skips all of this.

Design notes worth knowing when reading a PR, and when wiring such a workflow:

- **No job in the smoke workflow is named after the check.** A job skipped by `if:` reports
  `skipped`, which branch protection counts as success, so a job by that name would report a green
  smoke on every draft PR having smoked nothing. The workflow creates and completes the check
  itself, against the deployed commit's SHA.
- **The workflow only fires from the default branch.** It triggers on the `status` event, and
  GitHub runs those from the default branch only. A PR that changes the smoke workflow does not
  exercise its own change; the next ready PR after the merge is the first run of it.
- **A `neutral` conclusion always means "nothing was smoked", never "it passed".** It is reached
  when the walk could not run for a reason that is not this PR's fault — an operator kill switch,
  a preview environment missing the values the walk needs — and the check summary says which. They
  are passes to the verdict arithmetic — deliberately, because failing them would block every open
  PR over a configuration gap — but none of them is evidence that a page works. `ci-status.sh`
  prints the reason next to the verdict, so a GREEN cannot hide a walk that never happened.
- A kill switch, where the repo has one, completes the check `neutral` with a summary saying so.
  `neutral` is a pass, and that is deliberate — an operator turned it off. It is never made to
  vanish, because a check that vanishes would hang the requirement above.

**The classification is by rule, not by any list.** A check run is noise if it is
`Vercel Preview Comments`, advisory if its name ends `(advisory)`, and **blocking otherwise** — so
a workflow added tomorrow is blocking by default, and a repo's write-up can fall behind without a
new check being silently ignored. Don't "recognise" an unfamiliar check as skippable.

### Commit statuses — the deploy projects

The repo's deploy projects, which of them preview on a working branch and which build only on
merge, and which diffs affect each are the repo's own — `_shared/project-rules.md` → The
factory. What holds everywhere is how their statuses behave, and how to read them.

**A preview project posts a status when the diff affects it AND the PR is ready for review.**
Before the PR is ready the previews are **suppressed** — the deploy's ignore step skips the build
on two verified answers: the PR is **draft**, or the branch has **no open PR yet** (the opening
push always lands before the PR exists, so a branch without one is pre-draft by construction). It
fails open into the ordinary affected-check on any **error**, never on a verified answer. A
pre-ready push's statuses therefore read as skipped for the affected projects (or absent, when the
native skip filtered them first) — **suppressed — pre-ready** is a designed state, not missing
evidence. Previews for the affected projects arrive on the first push after the ready flip (Build's
contract flips ready, then pushes). One consequence for PRs opened **ready** from a branch that
already pushed (a human PR, or an audit branch): the opening push was suppressed, so no preview
exists until the next push after the PR opens.

Two filters decide whether a project builds, and a repo may run either or both: Vercel's native
**"Skip deployment for unaffected projects"** toggle decides first, platform-side, before any
container starts — a natively-skipped project occupies no build slot and creates **no deployment
and no commit status at all** (it reads as absent) — and the deploy's in-container ignore step
(`turbo-ignore`, or the platform's own) is the second filter for whatever the native skip lets
through, creating the deployment and then cancelling it.

#### The ignore step can fail open — and why the first ready push builds everything

The ignore step compares the diff against the project's **previous deployment on the branch**, and
falls back to the default branch when there is none. A deployment the ignore step cancelled does
**not** count as a previous deployment, so the draft pushes leave no baseline behind; and the
deploy's clone may not carry the default branch, so the fallback comparison cannot run and the
step **fails open**: every affected-or-not project builds. Every push after that has a baseline —
the deployment the fail-open produced — and is skipped accurately when nothing it depends on
changed.

Two consequences every contract here depends on. The **first push after the flip is the only one
guaranteed to produce a preview** — so a stage or lane that owes a preview to smoke must put its
last push after the flip, never before. And that push may build **every** preview project whatever
the diff, which is why a preview existing is not by itself evidence that the diff touched that
project.

Two platform footguns the native arrangement introduces:

- **A changed Vercel env var never re-triggers a skipped project.** The skip is git-diff-based;
  it cannot see the dashboard. After changing a project's env vars, the remedy is a manual
  **Redeploy with "Use project's Ignore Build Step" unchecked** — not a new push.
- **Never press "Start Building Now" on a queued build.** It converts that build to on-demand
  concurrency, which bills per minute. The queue is the design.

**Quiet projects — no status on a working branch at all; the build happens on the default branch
after the merge.** A repo may switch off working-branch deployments for the projects whose preview
is not worth the queue: `git.deploymentEnabled` in the project's `vercel.json`, set `false` per
working-branch pattern, never in the bare boolean form (that would kill the default-branch deploy
too). A push to such a branch creates no deployment at all — no queue entry, no concurrency slot,
no bot row, and **no commit status**. Which projects are quiet, and which branch patterns they
disable, is the repo's own (`_shared/project-rules.md` → The factory); a branch outside every
pattern still previews everything, so a new branch convention has to be added to each quiet
project's file.

**Ticket commits — a recipe for cost, never a gate** (decision D39 (8); the `pr-conventions`
skill). A ticket commit carries only `.icm/` markdown and goes straight to `main`, waiting for no
check — but its push still rebuilds production (on a UAT repo: the UAT environment and a Staged
production build) for a markdown change. A repo that wants none of that adds, per deploy project,
in its `vercel.json`:

- an ignore step that skips a commit touching only `.icm/`:
  `"ignoreCommand": "git diff --quiet HEAD^ HEAD -- ':!.icm'"` (exit 0 skips the build) — or, where
  the project already has one, the two joined: `git diff --quiet HEAD^ HEAD -- ':!.icm' || npx
  turbo-ignore`.

Both are the repo's own edits, recorded in `_shared/project-rules.md` → The factory. Neither is
required: the merge never waits for a deployment, so a repo without them only pays the build.

**Where the repo declares UAT, every push to `main` builds twice** (`.icm/project.json` → `uat`;
`_shared/promotion.md`; D39): once for the Vercel custom environment `uat.target` — its own
variables, its own database (the second Marketplace database's default branch on a Neon repo —
D41), the domain `uat.url` always serving its newest READY deployment,
which keeps the client's address constant while the batch under it changes — and once for
production, held **Staged** (Auto-assign Custom Production Domains off) until the release workflow
promotes it on a published Release. Neither is a PR preview and neither carries a PR status:
Release reads the UAT one once, after the merge, with `deploy-status.sh --sha <merge-sha> --uat`,
and production is read by the release workflow after it promoted.

**An absent status is not a skipped one, and neither is a pass you may quote.** Two different
things read as "not built":

- **Absent** — a quiet project on a working branch, or any project the native unaffected-skip
  filtered out platform-side. No deployment object exists, so nothing to read. `ci-status.sh`
  cannot wait on it and does not count it, which is why a PR settles on the affected preview
  projects' statuses only, never on one per project the repo deploys.
- **`state: success` with a skip description** — Vercel posts `success` for a project it did not
  build, and only the `description` says so. Two wordings exist:
  - `"Canceled by Ignored Build Step"` — a deployment that was created and then cancelled by the
    ignore step. This is what an unaffected preview project looks like on a PR, and what an
    unaffected quiet project looks like on the default branch.
  - `"Skipped - Not affected"` — Vercel's native unaffected-project skip, decided platform-side
    before any build slot is taken. When it posts a status at all, it can post one for **every**
    project on the commit — a row of `success` for a head with no preview behind any of them.

  Either is a skip, not a pass: there is no preview for that commit, so it cannot host a smoke,
  and quoting it as evidence that "the previews are green" is a false claim. Read the
  `description`, not just the `state`. `ci-status.sh` does exactly that — a description matching
  `Ignored Build Step`, `Skipped` or `Not affected` (case-insensitive) is classed `skipped`: it is
  listed under its own heading with the reason, never under "Previews built for this commit", its
  URL is never offered, and it never satisfies the "`smoke_check.preview_status` passed" condition
  that makes the smoke check required.

The preview URL to test against is the `target_url` of a project that **actually built**.

### Where a quiet project's verdict lands

The merge build **is** the proof for a quiet project — the operator's recorded risk acceptance for
the changes that reach it, taken knowingly in exchange for the queue its previews were costing. It
is an accepted failure mode, not a blind spot, and it is loud:

- A broken page that reaches the default branch **reds that commit's status for the project**,
  and Vercel raises its own deployment-failed notification. The previous production deployment
  stays live — a failed build never promotes — so the site is stale, not broken.
- Read it the same way as any other status: on the merge commit, via `get_status` on the default
  branch, or in the Vercel dashboard. The post-merge notification runs after the merge and does
  not gate on it.
- The fix is a follow-up commit to the default branch through the normal lanes, not a revert of
  the run *by a session's own decision* — a revert is the hotfix lane's (`lanes/hotfix/CONTEXT.md`),
  prepared by `rollback.sh` and merged by the operator; fix-forward stays the default.

## The verdict vocabulary — three values, not two

| Verdict     | When                                                                                                                                 |
| ----------- | ------------------------------------------------------------------------------------------------------------------------------------ |
| **GREEN**   | Every blocking check and status has **completed**, the repo's required checks among them, and none concluded in failure.             |
| **RED**     | At least one blocking check or status concluded `failure`, `timed_out`, `cancelled`, `action_required`, or status `failure`/`error`. |
| **PENDING** | Anything else — a check `queued` or `in_progress`, a status `pending`, or a required check not yet registered at all.                |

`neutral` and `skipped` conclusions count as passes. Advisory jobs are reported but can only ever
be a note; they never make a verdict RED.

### What GREEN means depends on the PR's phase (blind-until-ready)

The three values are the same in both phases; what differs is **which signals exist to settle
them**, and `ci-status.sh` prints which tier its verdict settled on. Where the repo declares its
deploy projects (`.icm/project.json` → deploy.projects), the script also names a product project
that has posted nothing yet on a ready head as `[INFO] expected, not yet posted` — a notice, never
a wait:

| Phase                | GREEN means                                                                                                                                                                                                                                                                                       |
| -------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Draft**            | **Nothing owed** (the cost floor): no quality job, the conditional jobs skipped by design, and **zero previews** — `ci-status.sh` settles at once on zero signals. The pre-flip check is the session's: `format.sh`, `lint.sh` and `security-check.sh` over the changed files. A draft GREEN authorises exactly one thing: Build flipping the PR ready. A repo that still runs a job on drafts says so, with what it costs, in `_shared/project-rules.md` → The factory. |
| **Ready for review** | The **full gate** settled: the affected preview projects' statuses (the verdict), the advisory quality job reported beside them, the conditional jobs where the diff warrants them, and any check the repo still names in `required_checks`. This is the only GREEN the smoke, the Ready-to-merge tick, and the merge rest on.                                                                                                                                       |

Two consequences worth spelling out:

- **The flip is what starts the full gate.** `ready_for_review` triggers the advisory job's run,
  and Build's contract follows the flip with a push (empty commit if nothing is pending), so the
  previews and the full verdict settle on a fresh head — never on a stale draft-era green.
- **`converted_to_draft` downgrades the verdict with it.** A ready PR pulled back to draft
  cancels its in-flight advisory run (the concurrency group) and re-settles on nothing owed; any
  full-gate GREEN it held no longer authorises a merge.

**PENDING is the verdict this pipeline kept losing.** It is not a soft green and it is not a reason
to proceed "since nothing has failed yet" — it means the factory has not answered. Zero checks on a
freshly pushed commit is PENDING, not GREEN: it takes GitHub 10–30 seconds to register a workflow,
and a stage that reads the moment after `git push` reads an empty list.

## One blocking call — never a model-driven poll

```bash
.icm/scripts/ci-status.sh <slug>          # or: --pr <n>
```

It resolves the PR's head SHA, reads **both** surfaces, discards the noise, waits for the run to
settle, and prints one verdict line. The waiting happens in the script's own loop, so it costs
wall-clock rather than model turns — which is why "wait for CI" is no longer in tension with "don't
burn context polling".

What it waits for is the repo's own. The `required_checks` array in `.icm/project.json` names the
check runs that must be present and completed before a run can be GREEN; the `smoke_check` object
adds one more, required per pass under the conditions above and never listed statically.
`PIPELINE_REQUIRED_CHECKS` in the environment overrides the array and is **newline-separated
only**: a check name may itself contain a comma (`Format, lint, typecheck` is one check), so a
comma split would wait forever on phantom names. An empty list means nothing is waited for beyond
the checks that appear — and an empty check list on a fresh push is CI not having started, not CI
having passed. Read the `RESULT:` line and act:

| `RESULT:` | exit | Obligation                                                                                                                                                                                                                  |
| --------- | ---- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `GREEN`   | 0    | Proceed. This is the only verdict any merge or hand-off may rest on.                                                                                                                                                        |
| `RED`     | 3    | **STOP.** Read the failing job (`get_job_logs`, `failed_only: true`), fix on the branch, push, and re-run this call — a fresh push means a fresh verdict. Never merge. Never hand off either, with the one exception below. |
| `PENDING` | 4    | The wait timed out with the run unsettled. **STOP** and say so. Re-run the call rather than guessing; if a required check never appeared, that is a broken workflow, not a pass.                                            |

The script prints, above the verdict, which deploy projects built and their preview URLs — that is
the list the operator smokes against before ticking **Ready to merge**.

### The one exit from `RED` — a failure that is not this PR's

Fix-and-push is the default and the row above is the rule. There is exactly one other exit, and it
is a **degraded hand-off**, never a green one: a blocking check this PR cannot turn green because
the fault is not in its diff. Take it only when all three hold.

- **The fault is outside the diff's reach.** The check fails in code, config or a workflow the PR
  does not touch, and its own output says so — a smoke check's "this is a configuration failure,
  not a persona failure" is the canonical wording.
- **It reproduces where the change is absent.** The same check is red on the base branch, on an
  unrelated PR, on a head of this PR that predates the change, or an `intake/triage/` stub already
  records it. The one permitted re-run may establish that; a second failure is evidence, not a
  flake.
- **No fix exists to port.** A fix that exists anywhere — a merged PR, the breaking commit's
  revert, a fix PR of your own — is ported into this PR and pushed instead. Porting is not
  widening.

Then, in the same invocation: park a triage stub if none records it (or name the one that does),
**finish the run's own bookkeeping anyway** — the close-out is never left hostage to a check it
does not depend on — and name the failing check in the hand-off report and in the PR itself, in
one comment. Record it in the run's `notes.md` too **only if the run is not closed out yet**: once
`close-out.sh` has archived the notes, the hand-off report and that comment are the record, and
reopening the archive for an annotation would put a commit after the flip for no one's benefit.
Never restate the verdict as `GREEN` and never imply the PR is clean; the
verdict is `RED` and the hand-off says so.

**This exit authorises a hand-off, never a merge.** A lane hands its PR to the operator's merge
button and Build hands its to the **Ready to merge** checkbox — both may hand over degraded,
because a human then decides with the failure named in front of them. Release _merges_, so it may
not: its hold list (`stages/04_release/CONTEXT.md`) is unchanged, and a blocking CI failure still
stops the merge.

**Re-running the call after a push is not polling.** The rule the contracts used to carry — "check
once, no polling" — was aimed at burning model turns on `sleep`-and-re-read loops, and it was read
as "one glance is enough". One glance at an unsettled run is worth nothing. The rule now is: **one
settled verdict per push**, obtained by the one call above.

## Webhook events — pipeline sessions don't listen at all

**Pipeline-managed PRs are never subscribed to PR activity** (`_shared/github.md` → PR events):
a single push produces a dozen-plus events — every Vercel project that deploys going `pending`
then
`success`, the Vercel comment bot posting and then editing its deployment table,
`Vercel Preview Comments` completing, each Actions job starting and finishing — and every one of
them costs context without carrying a verdict. The one blocking `ci-status.sh` call per push
replaces the whole stream. If a session finds itself subscribed to a pipeline PR, it
unsubscribes; watching a PR is a deliberate, human-requested act only.

Should a stray event still arrive (a human-requested watch, a race before unsubscribing), the old
rules hold:

- **Never act on a Vercel event.** Deployment-status events, the Vercel bot's comment and its edits,
  and `Vercel Preview Comments` are all pure noise. Reading a deploy failure out of an event is
  still fine — but establish it with the one call above before you touch anything.
- **Never act on a partial picture; one response per settled run, not one per event.** A burst of
  events from a single push is a single occurrence — the response is `ci-status.sh`, not a fix
  for the one job that happened to report first.
- **Advisory jobs never warrant a push.** Fix what they flag when you are already editing the run's
  files; a failing advisory job on its own is not a reason to touch the branch.
- **Your own pushes come back as events.** The event stream echoes what you just did — that is not
  a new instruction.
