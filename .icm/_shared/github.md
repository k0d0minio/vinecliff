# GitHub via the GitHub MCP (Layer 3 reference)

The pipeline drives GitHub **exclusively through the GitHub MCP** — the calls below, with
stop-conditions — and the `.icm/scripts/` listed under it. The agent never calls the `gh` CLI
itself for pipeline work; the scripts may fall back to a logged-in `gh` on their own (below).

## Runs anywhere — what each environment must set

Every GitHub call the scripts make goes through **`.icm/scripts/lib/gh.sh`**: curl with
`GITHUB_TOKEN` / `GH_TOKEN` first; on a missing token, a network failure or a non-2xx it retries
through the `gh` CLI if that is installed and logged in (`gh auth status`, tested with the token
variables unset); if neither works it dies with one message naming what _this_ environment is
missing. `new-run.sh` is the only script that opens a PR or names a run branch, and it works in
every environment below. The long-form page, where the repo keeps one, lives under the docs tree
(`docs_path` in `.icm/project.json`) — `_shared/knowledge-map.md` names it.

| Environment               | Must be set                                                                                                                                                                                 | `gh` fallback                        |
| ------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------ |
| Local machine             | `GITHUB_TOKEN` or `GH_TOKEN` exported — **or** `gh auth login` once; either route alone is enough                                                                                           | yes                                  |
| Claude Code cloud session | `GH_TOKEN` (injected by the session's GitHub connection) or `GITHUB_TOKEN` added to the environment's variables                                                                             | no — `gh` is not installed there     |
| OpenCode                  | `GITHUB_TOKEN` or `GH_TOKEN` in the shell OpenCode was started from — or a `gh auth login` on that machine                                                                                  | yes                                  |
| GitHub Actions            | `GH_TOKEN` set to the workflow's `github.token` (or `GITHUB_TOKEN` to `secrets.GITHUB_TOKEN`) in the step's `env`, plus `permissions: contents: write, pull-requests: write, issues: write` | yes — preinstalled, reads `GH_TOKEN` |

Optional everywhere: `GITHUB_REPO` (default: derived from `origin`) and `GITHUB_API_URL` (default
`https://api.github.com`; GHES only). **Minimum token scopes:** fine-grained — _Contents_,
_Pull requests_ and _Issues_ read/write (labels live on the issues API); classic — `repo`.

**Verify in ten seconds:** `.icm/scripts/resolve-run.sh <any-live-slug>` → `RESULT: READY`
(the PR lookup proves the credential when the run is not already in the working tree; a run
already checked out resolves offline), or `.icm/scripts/lib/gh.sh --check` → `RESULT: OK`, which
always makes the call and prints the route that answered.

**Repository-scoped endpoints only.** Every call the scripts make is under
`/repos/{owner}/{repo}/` — never `/search/…`. A Claude Code cloud session's agent proxy answers
the search API with HTTP 403 ("sessions are bound to their configured repositories. Use
repository-scoped endpoints"), so a script that searched would work everywhere except the
environment the pipeline is most often driven from. `resolve-run.sh` finds a run's PR through
`/repos/{owner}/{repo}/pulls` for that reason.

Repo: the repo's owner/repo, derived from `origin` (`GITHUB_REPO` overrides) — every MCP call
takes that `owner` and `repo`. **Token discipline:** one narrow call per question —
`pull_request_read` with the one `method` you need; `search_pull_requests` with a tight query and
small `perPage`. Never page through comment threads or diffs you don't need.

**Scripts own the mechanical projections; the MCP is for reads, content, and merges.** The
deterministic work runs through the `curl`+`jq` scripts in `.icm/scripts/` (config from the
environment: `GITHUB_TOKEN`/`GH_TOKEN`, optional `GITHUB_REPO`/`GITHUB_API_URL` — Runs anywhere,
above):

- **`resolve-run.sh <slug>`** — resolve a run into the working tree, or STOP (see `stage-preamble.md`).
  When the run is not in the tree it finds its PR by listing `/repos/{owner}/{repo}/pulls`: the
  open PRs whose body carries the slug (the spine Spec-table `Slug` row or the lane `- slug:`
  line), then `?head=<owner>:claude/<slug>`, then a head ending in `-<slug>`, then the same
  matches over the 200 most recently closed PRs. No search API — see Repository-scoped
  endpoints, above.
- **`new-run.sh <slug> --summary "…" [--stub …] [--lane bug|tweak|chore|hotfix|handover] [--ready]`** —
  open the run's PR + write `run.md` (Define, and the lanes; a `hotfix` opens **ready**, every
  other lane draft). **The only place a pipeline PR is opened or a run
  branch is named:** on `main`/detached it creates `claude/<slug>`; on any other branch it uses
  the current one (a harness-named branch is accepted and recorded in `run.md`). No other script,
  contract or hand-typed call creates a branch or a PR for a run. (The `knowledge` lane opens no
  run, so it is the one contract that calls `create_pull_request` itself — a docs-only PR on
  `knowledge/<slug>`, `lanes/knowledge/CONTEXT.md` step 6.)
- **`project-body.sh <slug> --summary "…"` / `--apply`** — project the spine PR body from
  `spec.md`: printed for `new-run.sh`, PATCHed onto the existing PR by `revise <slug>`.
- **`project-labels.sh <slug> --stage <define|build|release|auto>`** — project the label set.
- **`ci-status.sh <slug>`** — block until CI settles, then print one verdict (`_shared/ci.md`).
  Every hand-off and every merge rests on this, never on a glance at the check runs.
- **`close-out.sh <slug>`** — archive the shipped run and its finished epic, as a commit on the
  run's **own branch**. **Run by Release, before the merge** (stage 04, step 7) and by every lane
  in its step 4, before the hand-off; the squash publishes it. It refuses to run on `main` — it
  never pushes there.

## PR events — no PR in this repository is subscribed

**The rule is every PR, not only pipeline ones**, and it binds whatever opened the PR: a stage, a
lane, or a session doing a one-off chore. Do **not** call `subscribe_pr_activity` here, and if a
session finds itself subscribed — a harness may auto-subscribe after `create_pull_request`, and
some harnesses instruct the agent to watch every PR it opens — call `unsubscribe_pr_activity`
immediately and say so. A harness default does not override this file; this is the repository's
own rule about its own PRs.

One push produces a dozen-plus events — every deploying Vercel project cycling `pending`→`success`, the
Vercel bot posting and editing its comment table, each Actions job starting and finishing — and
none of them is a verdict. Each one wakes the session, costs a full turn, and re-sends the whole
comment table; a single PR can burn more context on deploy-table edits than the change itself
took to write. Measured on one real PR: a dozen wake-ups, every one of them "nothing red, no
action".

Read state instead of being told about it:

- **CI:** the one blocking `ci-status.sh <slug>` call per push (`_shared/ci.md`).
- **Review comments:** one `pull_request_read` (method `get_review_comments`) at the Release
  point (and at any explicit triage).
- **Anything longer-running** — a chore PR waiting on a tick, a CI run to come back — is a
  **scheduled check-in**, not a subscription: one wake on a timer that reads the state once and
  re-arms, instead of a wake per webhook. Same coverage, a fraction of the turns.

Watching a PR event-by-event stays a deliberate, human-requested act ("babysit this PR") — never a
default, and never something a session opts into on its own behalf.

## The PR regimes

1. **The front (Scope) — a direct commit to `main` (D39 (8)).** No feature PR exists yet, and
   none is opened. Scope carries `run.md`, `01_scope/_source/story.md`, `01_scope/output/scope.md`
   and the intake cut in **one commit straight to `main`** (`Scope: <slug> — intake cut`) and
   pushes it, so the scope is never trapped on one device and the stub exists for `new` the moment
   it lands. **The path guard:** the commit touches only `.icm/runs/<scope-slug>/**` and
   `.icm/intake/<scope-slug>/**`. Anything outside those two → STOP; never push it — the front
   writes markdown, never code. The scope is still reviewed by the operator before `new`, on
   `main`. Every other ticket commit — a `Plan:`/`Wrap:` cut, a stub moved — goes the same way
   (`.claude/skills/pr-conventions/SKILL.md`). A ruleset on `main` that requires checks keeps the
   operator's identity on its bypass list so this push lands; nothing is merged with `--admin`.

   This is the regime's first shape, back for every repo. D38 had moved it to a ticket PR into a
   "ticket base branch" because a UAT *branch* birthed a stub on one branch and retired it on
   another; with one long-lived branch (D39) a stub is born and dies on `main`, and the board,
   the dashboard and hygiene all read `main`.

2. **The spine (Define → Release)** — **exactly one PR per run.** Define opens it once (via
   `new-run.sh` → `create_pull_request`, draft); every later stage adds commits to the same
   feature branch — code, docs, changelog, cleanup. Never open a second PR for a
   run, never re-run `new-run.sh` against it, never branch off a docs-only or cleanup-only PR.

3. **The close-out — inside regime 2, not after it.** The archive move rides in the run's own PR:
   Release runs `close-out.sh <slug>` on the branch as part of its last commit (stage 04, step 7;
   a lane does the same in its step 4, before handing the PR to the operator to merge), under the
   same kind of path guard as the front (`.icm/runs/**`, `.icm/intake/**`, the runs and intake
   archives — `runs_archive` / `intake_archive` in `.icm/project.json`, `.icm/runs/_done/` and
   `.icm/intake/_done/` by default — nothing else), and the squash-merge is what publishes it.
   **There is no second PR and no third regime** — the close-out is simply the last thing the
   run's one PR carries. After the merge the repo's reporting hook announces —
   `.icm/scripts/report.sh announce`, called by Release step 9 (`reporting.announce_from:
   session`, the default) or by the repo's release workflow (`ci`); what a channel is — a GitHub
   Release by default, Slack, email — is `.icm/project.json` → reporting
   (`_shared/project-rules.md` → Reporting). A fault after the merge is `report.sh alert`, and
   where `alert` maps to no channel the red CI job is the alert. Both are reads plus one send;
   nothing watches.

   This is not the shape it started with. CI used to run `close-out.sh` after the merge and push a
   second commit straight to `main`, and that push can never land: `main`'s branch protection
   requires the repo's required status checks, which no direct push can carry, and GitHub refuses
   the Actions bot as a ruleset bypass actor — _"must be part of the ruleset source or owner
   organization"_. Every Release run went red and every merged run was left in `.icm/runs/` with
   its archive commit stranded on a `chore/close-out-<slug>` branch. The move belongs where the
   branch still exists.

   The old rule forbade exactly this, on the grounds that a run folder moved before the squash is a
   claim about a merge that hasn't happened. It isn't: the move reaches `main` only if the PR
   merges, and if the PR never merges the move never happened. That is the same standing as the
   changelog page, which also says _this shipped_ and is also written on the branch before the
   merge.

4. **The promotion — UAT repos only, and not a PR.** Where `.icm/project.json` declares `uat`,
   regimes 2 and 3 are unchanged — every PR targets `main` — but the merge reaches the client's
   UAT environment and builds a **Staged** production deployment instead of shipping. Production
   is reached by a **GitHub Release**: `promote.sh approve --by "<who>"`, run on the client's
   sign-off — the operator's act, never inferred — drafts it at the signed-off SHA; **the
   operator publishes it on GitHub**, and the repo's release workflow migrates production,
   promotes the staged deployment of that SHA and announces. Nothing here publishes, promotes or
   merges. `_shared/promotion.md` owns the rule.

Fast-lane PRs (`--lane`) are a degenerate shape of regime 2, finished in **one invocation**: one
PR — **opened draft, like the spine** (blind-until-ready; the one exception is `hotfix`, which
opens **ready** so an incident gets the full gate and the previews at once) — whose body carries the Summary (with
a `- slug:` line, so `resolve-run.sh` finds it by body) and Steps to test, and **no gate
checkboxes**. On a cheap-tier GREEN the lane finishes the run **while the PR is still draft** —
the changelog page when the change is user-visible (bug/tweak; chores never; a repo with no
changelog records `announce: none` — `_shared/project-rules.md` → Announcing), then
`close-out.sh` on the branch — and only then pushes, flips ready, settles the full gate once and
**stops**. The flip is deliberately the last act: it is what makes the PR mergeable, so nothing
the lane still owes may come after it. That ordering is what an early lane run lacked — it merged
while its lane was still working, and the archive move needed a sweep PR to carry it. **The merge
is a human's, in the GitHub UI:** the operator smoke-tests the previews and presses squash-merge
themselves — the merge button is the gate, nobody reads a checkbox, and the agent never calls
`merge_pull_request` on a lane PR and is never re-invoked for one. After the merge the repo's
reporting hook announces where the repo has wired a caller for lanes (its release workflow, or
the operator by hand); the lane itself never calls it. **One live run per touched surface**: a
lane or run that would edit a file another live run is editing waits or is sequenced
(`stage-preamble.md` → Run-scoped isolation).

**The PR is the run's GitHub home.** Its body and labels are one-way projections of the run's
`spec.md` (spine) or `notes.md` summary (lanes). No issue is created — PRs carry no `Closes #`.

## Gates — checkboxes in the PR body (spine PRs only)

The feature-PR template ends with the Gates block — a horizontal rule above and below, a
`### Gates` heading, and one checkbox per gate, each anchored by an HTML comment so parsing never
depends on wording. **Lane PRs carry neither anchor** — their gate is the merge button, pressed by
a human in the GitHub UI (fast-lane PRs, above):

```md
---

### Gates

<!-- gate:spec-approved -->

- [ ] **Spec approved** — _Define gate: a human ticks this before Build starts._

<!-- gate:ready-to-merge -->

- [ ] **Ready to merge** — _Release gate: a human ticks this to authorise the squash-merge; the tick attests your own preview smoke-test._

---
```

- Read a gate: `pull_request_read` (method `get`) → find the anchor comment in the body → the next
  checklist line is the gate; `[x]` = ticked.
- **A missing anchor means "not required", never "unticked".** Parse what's present. A missing
  `gate:ready-to-merge` anchor on a **spine** PR is a malformed body — STOP and fix the body
  first. On a lane PR its absence is by design (`type:bug|tweak|chore`, or a
  `PIPELINE RUN (lane: …)` marker): there is nothing to read, and nothing to tick.
- **The agent never ticks either box.** If a required box is unticked: STOP and tell the user. The
  ticked **Ready to merge** box _is_ the merge authorisation — it also attests that the operator
  has smoke-tested the preview by hand, which is why Release re-asks for no manual checks. On a
  lane PR the same attestation is the merge click itself. (The one other hard gate — the scope
  reviewed on `main` before `new` — lives outside the PR.)
- **Both boxes are the operator's to tick.** The business's involvement happens earlier and ends
  there: the scope is settled with the operator at Scope and committed to `main` for review. From Define onward no gate waits on the business; the checkboxes record the
  operator's decisions.
  Nothing else ever ticks them — there is no scripted exception.
- **The boxes bind the agent, not the merge button.** What branch protection on `main` requires
  is the repo's required check(s) (`required_checks` in `.icm/project.json`; `.icm/_shared/ci.md`);
  no workflow, ruleset or script reads the gate anchors to allow or refuse a merge —
  `project-body.sh` (and any report the repo runs over its PRs) only reads them to describe the
  PR. Build refuses to start on an unticked **Spec approved** and Release refuses to merge on an
  unticked **Ready to merge**, but a human can squash-merge a spine PR from the GitHub UI with
  both boxes unticked, and that is accepted: the merge click carries the same attestation the
  tick would (lane PRs carry neither box and work this way always). The checkboxes exist to stop
  the agent self-advancing, not to stop the operator.

## Labels

The fixed vocabulary lives in `.github/labels.yml` (documentation + one-time repo setup).
**Projection is CI's job, not the agent's:** on every push touching `.icm/runs/**`, the
`labels` job in `.github/workflows/pipeline.yaml` runs `project-labels.sh <slug> --stage auto
--pr <n>` — it reads personas/complexity from `spec.md` and derives `stage:*` from **which run
outputs exist** (spec.md → define · `03_build/output/notes.md` → build · a `## Release` section
in that notes.md → release). Pushing a stage's output is what moves the label. `new-run.sh`
projects the initial set when the PR opens; the script stays the manual fallback.

**Release is the one exception — it projects its own label.** A spine PR moves
`stage:define → stage:build → stage:release`, and the first two moves are CI's: Define's push
carries `spec.md`, Build's first push carries `notes.md`. Release's outputs are different: the
`## Release` record is pushed at the end of the stage, and the close-out push that follows it
moves the run folder out of `.icm/runs/`, where the labels step can no longer see it. Left to
CI, the PR would read `stage:build` for the whole of Release and `stage:release` only for the
minutes between the record push and the merge. So Release's step 1 runs
`project-labels.sh <slug> --stage release` itself, and the PR reads `stage:release` from the
moment the stage starts. Lane PRs carry `type:<lane>` only and never move.

- `stage:` exactly one of `define → build → release`.
- `type:feature` on spine PRs · `type:{bug,tweak,chore,hotfix,handover}` on lane PRs
  (the vocabulary is `lib/project.sh` → `pipeline_lanes`; add `type:hotfix` and `type:handover`
  to `.github/labels.yml` when adopting the lanes).
- `persona:<name>` (the repo's persona vocabulary, `.github/labels.yml`) and
  `complexity:{trivial,standard,complex}` from the spec header (spine only).

## Define — draft PR projected from `spec.md`

```bash
.icm/scripts/new-run.sh <slug> --summary "<one plain sentence>" [--stub .icm/intake/<scope>/<feature>.md]
```

Commits `.icm/runs/<slug>/` and pushes; opens the draft PR (`base: main` — the one long-lived
branch, UAT or not (D39); title = spec title,
body = the template projected from `spec.md` by `project-body.sh`: Spec block, acceptance-criteria
checklist mirrored unticked, both gate anchors, and the **link** to `spec.md` — never an embedded
copy); writes/extends `run.md`; projects labels; `git mv`s a consumed stub into `_done/`. One PR
per run.

## Revise — the spec changes, the PR follows

`revise <slug> "<what to change>"` (stage 02, step 6) edits `spec.md`, commits, pushes, validates,
then reconciles one direction only (file → PR), both scripted:

```bash
.icm/scripts/project-body.sh <slug> --apply [--summary "…"]   # the scripted update_pull_request
.icm/scripts/project-labels.sh <slug> --stage define
```

`project-body.sh --apply` replaces the whole body with the same projection `new-run.sh` opened it
with — the Summary and Steps to test are kept from the current body unless overridden; the
Acceptance criteria section is mirrored again with every box reset to `[ ]`; **both gate anchors
come back unticked.** A ticked Spec approved box is therefore cleared by a revision — the script
says so on stderr, and the stage says so to the operator, who re-ticks. Never `new-run.sh` again,
never a second PR.

## Build — gate-check, implement, flip ready, then push

1. Gate: `pull_request_read` (method `get`) → **Spec approved** must be `[x]`. Unticked → STOP.
2. Implement; commit run files with the code; push (CI advances `stage:build`). Tick satisfied
   acceptance criteria via `update_pull_request` (tick state lives on the PR; text stays the spec's).
   Draft pushes run the cheap tier and build no previews (blind-until-ready — `_shared/ci.md`).
3. `ci-status.sh <slug>` → a settled cheap-tier `GREEN` before flipping. `RED` is Build's to fix,
   not Release's.
4. Hand-off: `update_pull_request` with `draft: false`, **then push** — an empty commit when
   nothing is pending. The flip starts the full gate; the push makes the full-tier run and the
   affected product-app previews land on a fresh head. Settle the full verdict with one more
   `ci-status.sh` call; the operator's smoke and the **Ready to merge** tick follow it.

## Release — reviews, gated merge

1. `project-labels.sh <slug> --stage release` — the PR reads `stage:release` from the start
   (Labels, above).
2. Gate: **Ready to merge** must be `[x]`. Unticked → STOP and ask. Never tick it; never merge
   without it.
3. Review comments to triage: `pull_request_read` (method `get_review_comments`) — once. Trivial
   in-ticket fixes are commits on the same branch; everything else is a `intake/triage/` stub
   (`stages/04_release/CONTEXT.md` owns the rule). The code review itself is `/code-review`,
   in-session, at the spec's complexity — there is no CI review job.
4. **Two pushes before the verdict, in this order** (stage 04, step 7): merge `origin/main` into
   the branch (a merge commit, never a
   rebase — the close-out's sibling check must see what the base branch archived since the
   branch was cut), commit and push the `## Release` record with the
   docs and the changelog page, **then** run `close-out.sh <slug>` and push its commit on its
   own. The record push is the one the Pipeline workflow reads; the close-out push carries only
   the move.
5. **Establish the verdict, then merge — Release refuses to merge on anything but green.**
   `ci-status.sh --pr <number>` on the head you are about to merge, after the last push
   (`_shared/ci.md`; `--pr` by preference — `<slug>` still resolves from the archive).
   `RED` → STOP: read the failing run (`get_job_logs`, `failed_only: true`), fix, push, re-run the
   call. `PENDING` → STOP and re-run it. Only `GREEN` → re-read the gate, then
   `merge_pull_request`, `merge_method: "squash"`, attempted **once**. Branch protection on
   `main` backstops this, but the STOP is the contract regardless of repo config.

   Do **not** substitute a bare `get_check_runs` read here. It misses the Vercel deploys entirely
   — those are commit statuses — and it returns every attempt on the SHA, so a superseded
   `cancelled` run reads as a failure on a PR that is actually green. The script handles both.

6. Post-merge: update the PR body's spec link to its `blob/main/` URL (`update_pull_request` —
   the branch link dies with the squash-merge); read production once
   (`.icm/scripts/deploy-status.sh --sha <merge-sha>` → the `- production:` line for the stop
   message); announce through the repo's hook (`.icm/scripts/report.sh announce …`, or record
   `deferred to CI` where `announce_from` is `ci`). Those are the only post-merge acts: the
   close-out already rode in the PR. Don't wait for a workflow. A run found unarchived after
   its merge is a fault in the Release that merged, not a chore for a sweep PR — read step 4
   again.
