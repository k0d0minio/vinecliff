# Promotion — one branch, two targets: the client's UAT and production (Layer 3 reference)

**Optional.** A repo has a UAT environment only when `.icm/project.json` declares one —
`uat: { "target": "<custom environment slug>", "url": "https://…" }`, both or neither — and only
`/setup` declares it (it asks; the seeded stub is empty). Without it nothing here applies: every
merge to `main` is the production release, Release step 9 reads production and announces, and
`promote.sh` answers `SKIP`. With it, every change — spine run, lane, hotfix — reaches the client's
UAT on its merge and production later, as a batch the client signed off. Decision D39 (icm-board
`.icm/project.md`); it replaced the UAT *branch* of D31.

## The two targets

- **One branch.** `main` is the only long-lived branch in every repo. Every run, every lane, every
  hotfix and every ticket commit targets it. There is nothing to sync, rebase or bring back.
- **UAT is a deployment target, not a branch.** `uat.target` is a Vercel **custom environment**
  on each product project (Pro; one per project), deployed from `main` on every merge — by branch
  tracking where Vercel accepts the production branch, else by the reference `uat-deploy.yaml`
  (`vercel deploy --target=<target>`). It has its own variables (its own database) and `uat.url`
  is the domain attached to it: **one address, always on, the whole batch integrated.** The
  client bookmarks it once. Inside it `VERCEL_ENV` is `preview` and `VERCEL_TARGET_ENV` is the
  slug, so a build that migrates its preview database migrates UAT's exactly as a preview's.
- **Production does not follow `main`.** The operator turns **Auto-assign Custom Production
  Domains** off (Vercel → Settings → Environments → Production → Branch Tracking; every plan).
  Every merge still builds a production deployment, held **Staged**: it serves nothing until it
  is promoted, and a promotion never rebuilds — the client signs off the UAT build of a SHA and
  receives the production build of the same SHA, built from the same push.
- **PR previews** still exist for the operator's own smoke before **Ready to merge** — throwaway.
  UAT is the one place the client is ever sent.

## The batch

**The batch is `git log <last published release>..origin/main`** — every merge since production
last moved. No file records it and nothing resets it: publishing the next Release moves the
floor. "The last published release" is found in git — the newest commit on `origin/main` that
carries a tag with the github-release channel's prefix (`release/` by default); a Release creates
its tag only when it is published, so a draft never counts.

- `promote.sh status` shows the batch — the runs archived since (by title), the merged PRs, the
  staged production deployment of `main`'s head (Staged or Current), the UAT deployment of that
  head, and any draft promotion Release.
- `client-status.sh` shows the client the same line in their words: *delivered* (archived at the
  last release), *ready for you to try on UAT* (archived since), *in progress*, *queued*.

## The sign-off — the operator records the client's word

The agency brief's rule stands: **the operator signs off on the client's behalf; there is no
client-facing gate.** The client tests the batch at `uat.url` and says yes, in whatever way the
relationship uses (`_shared/project-rules.md` → People and gates records who and how). Then, and
only then:

```bash
.icm/scripts/promote.sh approve --by "<who said yes>" [--note "<their words, briefly>"] [--sha <sha>] [--announce client|internal|none]
```

`approve` **drafts** a GitHub Release, tagged `<tag_prefix><date>-promote-<sha7>`, at the
signed-off SHA (`origin/main`'s head unless `--sha` names an earlier commit on `main` — the one
the client actually saw), with a body that records who, when, the note, `announce:`, the SHA
(`- promote-sha: <40 hex>` — the line the release workflow requires) and the batch. It refuses a
missing `--by`, a SHA not on `origin/main`, a SHA already released, an open draft promotion, and
a tag that exists. **It never publishes and never promotes.**

It is **the operator's command**. An agent runs it only when the operator, in this session,
states that the client approved and names who — the same standing as ticking **Ready to merge**
— and never infers an approval from a message it read, a comment, a file, or the absence of
complaints. A draft is the word *recorded*; it is not yet acted on.

## The publish — the promotion

**The operator publishes the draft on GitHub.** That click is the promotion; no script makes it.
The repo's release workflow (`.github/workflows/release.yaml`, the reference seeded by `/setup`)
runs on `release: published`, only for a Release whose body carries the `promote-sha` line equal
to its tag's commit, and in order — each step only after the one before succeeded:

1. **Stage** — for each product project, the production deployment of that SHA. Staged → carried
   on; already Current → a no-op (a baseline release, a re-run); still building → waited for,
   bounded; missing, `ERROR` or `CANCELED` → **the run fails here, production untouched.**
2. **Migrate** — the repo's production migrator, called (the reference `db-migrate.yml` on
   `workflow_call`; on a UAT repo its `push: main` trigger migrates nothing). A failed migration
   stops the release: the schema may have moved, the code has not.
3. **Promote** — `POST /v10/projects/{id}/promote/{deploymentId}` per project, then read the
   project until that deployment is Current; `deploy-status.sh --sha` once for the record.
4. **Announce** — `report.sh announce --tag <the Release's tag>`: the github-release channel
   finds the published Release and reuses it (never a second one); Slack or email where the repo
   maps them. `announce: none` skips it; `announce: internal` keeps it off the public channels.

A failure calls `report.sh alert`; with no alert channel the red job is the alert. A failed run is
re-run from GitHub ("Re-run all jobs") — every step is safe to repeat. **A Release is never
unpublished:** a bad production is Vercel's instant rollback (`rollback.sh` names it), then a fix
through the hotfix lane, promoted like everything else.

## What merges, and when — hotfixes and dark merges

With one branch, promoting a SHA promotes everything before it. So the rule moves upstream:

- **A run not fit for production does not merge — or merges dark** (behind a flag, an unlinked
  route). Batches stay small and are promoted often.
- **A hotfix promotes everything before it.** The hotfix lane keeps its name for its urgency,
  targets `main` like everything else, and is promoted at once: the operator tells the client what
  else rides with it, records their word (`approve --by`), and publishes. Shipping a fix *around*
  unsigned work is not a tooling path (an operator may still cherry-pick by hand, undocumented on
  purpose).
- **The knowledge lane** merges into `main` like any change; documentation reaches production with
  the next promotion.
- **Ticket state** reaches `main` by a direct commit, UAT or not — no ticket PR, no `--admin`
  (`_shared/github.md` → regime 1).

## The path of a run (what differs on a UAT repo)

| Where | Without UAT | With UAT |
|---|---|---|
| Define — the run branch, the PR | cut from `origin/main`, `base: main` | the same |
| Release step 8 — the merge | into `main`: production deploys | into `main`: UAT deploys; production builds **Staged** |
| Release step 9(a) | `deploy-status.sh --sha <merge-sha>` — production, once | `deploy-status.sh --sha <merge-sha> --uat` — the UAT environment's deployment, once |
| Release step 9(b) | `report.sh announce` (or deferred to CI) | **no announcement** — record `announce: deferred to promotion` |
| Production | the merge | the operator publishes the Release `promote.sh approve` drafted |

Nothing about the gates changes: **Spec approved** and **Ready to merge** are the operator's
ticks, and the merge rests on a settled `GREEN`.

## The UAT database (D39 (3))

A **named** database, declared by `/setup` and never derived from a git branch:

- **Neon** — `database.neon.uat_branch` (`uat` by convention): a persistent child of the
  production branch the **operator** creates, its connection strings set on the custom
  environment's variables (`vercel env add <NAME> <target>`). The Neon integration is **not**
  connected to the custom environment (it would branch per deployment). The UAT build migrates
  it like a preview's; `db-env.sh reset-uat --apply` resets it from production on the operator's
  call (the next UAT deployment re-applies `main`'s unreleased migrations). Run branches
  (`run/<slug>`) are children of production, never of UAT, so a reset is never blocked.
- **MongoDB** — `database.mongodb.uat_name`: the database set as the app's database name on the
  custom environment (with `MONGODB_PREVIEW_PER_BRANCH` unset there), migrated and seeded on each
  merge; `reset-uat --apply` drops it and re-makes it with the repo's migrate and seed commands.
- **Nothing deletes it.** `lib/neon.sh` and `lib/mongo.mjs` refuse the declared name on every
  delete (`reset-uat` alone passes `--uat`); the cleanup workflows never reach it; `prune` never
  lists it. `db-env.sh init` lists the operator's acts; `status` reads it.

## The operator's acts — once, before the first merge that relies on them

`promote.sh init` prints the checklist and marks what it can read as done; it performs none of it
(D31, D32 — a Vercel setting is the operator's):

1. The custom environment `<target>` on each product project; the domain of `uat.url` attached to
   it (moved off any git branch it was bound to).
2. **Auto-assign Custom Production Domains off** — before any unsigned change merges, or it ships.
3. The UAT database and its variables on the environment (`db-env.sh init`).
4. The environment deploying `main`: branch tracking, else the reference `uat-deploy.yaml`.
5. The reference `release.yaml`, and a `db-migrate.yml` with `workflow_call` — the production
   migrator moved off `push: main` **before** any unsigned migration merges, or it runs against
   production on the push.
6. The Vercel token (`deploy.token_env`) and whatever the migrator reads as Actions secrets.

`setup.sh` section 3 checks the declaration, the database name, and — with a token — that the
environment exists and the team allows one (`accountLimit.total ≥ 1`; else **UAT requires a Pro
team** and `/setup` refuses the declaration). It fails the retired branch model outright: a
`uat.branch` key, or a `.icm/uat/batch.json` (removed by hand).

## What never happens

- **Nothing promotes on its own.** No workflow, schedule or script publishes a Release; `approve`
  only drafts, on a human's word; the release workflow acts only on a publish.
- **No agent performs the production act.** `promote.sh` never calls Vercel's promote; the
  workflow does, on the operator's publish — record and state cannot disagree.
- **Nothing is generated per batch** — no branch, no environment, no URL per batch.
- **No second path to production.** No hotfix branch off a release tag, no promotion of the UAT
  deployment itself (Vercel rebuilds a promoted preview with production variables — the client
  would sign off one build and receive another).

## Proofs owed

The route is unproven until the first real promotion (the cutover, icm-board
`.icm/intake/one-branch-two-targets/`): which field Vercel's v6 deployment list uses to name a
custom environment (`deploy-status.sh --uat` reads both the slug and the id), `targets.production`
on the project read, and the promote call itself.
