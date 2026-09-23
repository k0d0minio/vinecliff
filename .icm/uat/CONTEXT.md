# UAT — the client's persistent test environment, the batch, the sign-off, the promotion

**Optional.** A repo has a UAT environment only when `.icm/project.json` declares one —
`uat: { "branch": "uat", "url": "https://…" }` — and only `/setup` declares it (it asks; the
seeded stub is empty). Without it nothing in this file applies: every run's PR targets `main`,
Release ships on the merge, and `promote-uat.sh` answers `SKIP`. With it, every run in the repo
— spine and lane alike — reaches the client's UAT first and production later, as a batch the
client signed off. Decision D31 (icm-board `.icm/project.md`).

## What it is, and what it is not

- **One branch, one address, always on.** `uat.branch` is a long-lived integration branch that
  every run's PR targets instead of `main`; Vercel deploys it like any branch, and `uat.url` is
  a domain the operator assigned to that branch in the project's settings (or the branch alias).
  The address never changes; the deployment under it moves with every merge. The client
  bookmarks it once.
- **Not a per-batch preview, not a per-PR preview.** PR previews still exist for the operator's
  own smoke before **Ready to merge** — they are throwaway. UAT is the one place the client is
  ever sent, and it shows the whole batch together, integrated, the way production will.
- **The preview environment's variables**, unless the project attaches a custom environment to
  the branch in Vercel. Which data the client tests against is the operator's one-time decision
  (`promote-uat.sh init` lists it with the other setup acts) — and where the repo declares a
  Neon project with `database.neon.previews: vercel`, the answer is a database of the UAT
  branch's own (below).

## The UAT database (Neon repos — decision D32)

Where `.icm/project.json` declares `database.provider: neon` and `database.neon.previews:
vercel`, the Vercel integration creates a Neon branch for every git branch it deploys —
`preview/<git-branch>`, a copy-on-write child of production — and injects its connection
variables into that deployment alone. The UAT git branch is one such branch, so **the UAT
database is the Neon branch `preview/<uat.branch>`**: born from production on the branch's first
deployment, persistent for as long as the branch deploys, nothing to create and nothing per
batch. `lib/project.sh → neon_uat_branch` names it; `db-env.sh status` reads it.

- **Migrations reach it at build.** A run's migrations ride its PR into the UAT branch; the
  deployment's build applies them to `preview/<uat>` (the build command runs the repo's migrate
  step before the build — an operator act `db-env.sh init` lists, recorded in
  `_shared/project-rules.md` → The factory). Production keeps whatever the repo does today.
- **Reset from production is the operator's act.** After a promotion — when the client's test
  data should go and production's shape return — `db-env.sh reset-uat --apply` resets the branch
  from its parent (dry-run without `--apply`; `promote-uat.sh sync` names it). Nothing resets on
  its own, and a reset never touches production.
- **Run branches are children of production, never of UAT.** `db-branch.sh` (`database.isolation:
  neon`) creates `run/<slug>` under the production branch, because Neon refuses to reset a branch
  that has children and a run must never block the client's environment. A preview's database is
  the integration's `preview/<run branch>`, a child of production too; each applies the run's
  migrations at build.
- **Nothing here deletes the UAT branch.** `lib/neon.sh` refuses its name on every delete; the
  cleanup workflow skips the UAT git branch by name; `db-env.sh prune` never lists it.

On a **MongoDB** repo (`database.provider: mongodb`, `database.mongodb.previews: branch` —
decision D35) the same shape holds without a copy of production: the UAT git branch deploys as a
preview, so its database is `preview_<uat.branch>` (`lib/db-name.mjs`; `lib/project.sh →
mongo_uat_database`), migrated and seeded by the repo's preview-migrate workflow on every push to
the branch. `db-env.sh reset-uat --apply` drops it and re-makes it with the repo's migrate and
seed commands — the client's test data goes, the shape is the UAT branch's; nothing is copied
from production. `lib/mongo.mjs` refuses its name on every other drop, the reference
`mongodb-cleanup.yaml` skips the UAT git branch, and `db-env.sh prune` never lists it.

## The path of a run (what changes, stage by stage)

| Where | Without UAT | With UAT |
|---|---|---|
| Tickets — cuts, moves, Scope's front (D38) | a ticket PR into `main`, merged at once by the session that opened it | a ticket PR into `<uat>`, merged at once — the UAT branch is the **ticket base branch**; the board reads it, and `main`'s copy lags until a promotion |
| Define — the run branch | cut from `origin/main` | cut from `origin/<uat>` (the stub is already there), with `origin/main` brought in first so an unsynced hotfix is not lost; `new-run.sh` brings `main` in itself when it finds it missing, and warns when the branch was not cut from the UAT branch |
| Define — the PR | `base: main` | `base: <uat>` (`new-run.sh` reads `lib/project.sh → pipeline_base_branch`) |
| Build step 10 · Release step 7(a) | merge `origin/main` | merge `origin/main`, then `origin/<uat>` |
| Release step 7(c) — `close-out.sh` | archives the run | archives the run **and appends its slug to `.icm/uat/batch.json`** in the same commit — the squash publishes both onto the UAT branch |
| Release step 8 — the merge | into `main` | into `<uat>` — the run is now in front of the client at `uat.url` |
| Release step 9(a) | `deploy-status.sh --sha <merge-sha>` — production, once | `deploy-status.sh --sha <merge-sha> --uat` — the UAT branch's deployment, once; production untouched |
| Release step 9(b) | `report.sh announce` | **no announcement** — record `announce: deferred to promotion`; the client is told once, when the batch ships |
| Lanes (bug · tweak · chore · handover) | PR into `main`, the operator merges | PR into `<uat>`, the operator merges; the fix is on UAT, announced at promotion |
| Hotfix | PR into `main` | **still `main`** — production is wrong now; `promote-uat.sh sync` is **required** afterwards: it brings the fix, and the run's close-out, into UAT and the ticket base branch |
| Knowledge lane | docs-only PR into `main` | still `main` — documentation is not client-tested; `promote-uat.sh sync` is **required** afterwards, so the UAT branch every run and the board read carries the page |

Nothing about the gates changes: **Spec approved** and **Ready to merge** are the operator's
ticks, the merge into the UAT branch rests on a settled `GREEN` exactly as a merge into `main`
did, and the close-out rides the run's own PR.

## The batch — `.icm/uat/batch.json`, on the UAT branch

```json
{
  "stubs": ["<slug>", "<slug>"],
  "client_approved": false,
  "approved_by": "", "approved_on": "", "approved_head": "", "approved_note": "",
  "promotions": [ { "promoted_on": "…", "approved_on": "…", "approved_by": "…", "head": "…", "pr": "…", "stubs": ["…"] } ]
}
```

- **`stubs`** is what is on UAT and not yet in production: `close-out.sh` appends a run's slug
  when its PR targets the UAT branch; nothing else writes the list. `promote-uat.sh status`
  cross-checks it against git (runs archived on the UAT branch and not on `main`) and **reports**
  a gap either way — it never repairs one.
- **The branch and the address are not in this file.** They are configuration, and
  `.icm/project.json → uat` is their one home (one home per fact, D24); this file holds state.
- **`client_approved` and the `approved_*` fields** are written by `promote-uat.sh approve`
  and reset by `promote-uat.sh sync` after the promotion lands, which also appends the
  promotion to `promotions` — the log of what reached production, when, on whose word.
- The file lives on the UAT branch (that is where it is true); `main` receives it inside each
  promotion PR. `client-status.sh` reads it from `origin/<uat>`.

## The sign-off — the operator records the client's word

The agency brief's rule stands: **the operator signs off on the client's behalf; there is no
client-facing gate.** The client tests the batch at `uat.url` and says yes, in whatever way the
relationship uses (an email, a call, a message — `_shared/project-rules.md` → People and gates
records who and how). Then, and only then, the operator runs:

```bash
.icm/scripts/promote-uat.sh approve --by "<who said yes>" [--note "<their words, briefly>"]
```

It is **the operator's command**. An agent runs it only when the operator, in this session,
states that the client approved and names who — the same standing as the operator ticking
**Ready to merge** — and never infers an approval from a message it read, a comment on a PR, a
file, or the absence of complaints. `--by` is required for that reason: an approval is a
person's word, recorded.

## The promotion — one PR per batch, merged by a human

`approve` does the mechanical part end to end and stops:

1. Fetches; refuses an empty batch, a dirty working tree, an approval without `--by`, and a batch
   already approved at the current head.
2. Cuts `claude/promote-uat-<date>` from `origin/<uat>` and brings `origin/main` in (a merge
   commit — a conflict STOPs and names the fix; nothing is guessed).
3. Writes the sign-off into `batch.json` (`client_approved: true`, `approved_by`, `approved_on`,
   `approved_head` = the UAT head that was approved — a run merged after it belongs to the next
   batch) and the promote lane run's `notes.md` (the batch, by title; who approved, when).
4. Opens the promotion PR **ready** into `main` through `new-run.sh --lane promote --ready`
   (label `type:promote`; the body's Summary names the batch and the approver), runs
   `close-out.sh` on the branch (the promote run is archived like any lane run), pushes, and
   **stops**.

**The operator merges it from GitHub** — the merge button is the gate, as for every lane. A
merge commit keeps the UAT branch and `main` sharing history (the next promotion PR then shows
only new work); a squash also works, because `sync` brings `main` back into the UAT branch
either way. The agent never calls `merge_pull_request` on a promotion PR.

## After the merge — `sync`

```bash
.icm/scripts/promote-uat.sh sync
```

Run **after the promotion PR merged**, and — **required, not optional** — after every hotfix and
every knowledge-lane PR that merged into `main`: until it runs, what those merges moved (a hotfix's
close-out, a page) is missing from the UAT branch, which is the ticket base branch the board reads
(D38), so the board shows their work as not done. In a
throwaway worktree it merges `origin/main` into the UAT branch — one merge commit — and, when
that merge carries an approved batch that reached production, resets `batch.json` for the next
batch in the same commit (the promotion logged under `promotions`; stubs merged after the
approval stay in `stubs`). Then it pushes the UAT branch, and announces the release through the
repo's own hook where `reporting.announce_from` is `session` (`report.sh announce` with the
batch's summary — a GitHub Release by default, Slack or email where the repo mapped them); where
it is `ci`, the reference release workflow already announced on the promotion merge — it fires
for merges into the default branch only, so a run merging into the UAT branch announces nothing.
A conflict STOPs with the resolution named. `deploy-status.sh --sha <merge-sha>` remains the one
read of production, the operator's to make.

## What bypasses UAT, and what never happens

- **A hotfix bypasses UAT** (`lanes/hotfix/CONTEXT.md`): production is wrong now, its PR targets
  `main`, and `sync` carries the fix into UAT afterwards — required, not optional.
- **The knowledge lane bypasses UAT**: a docs-only PR into `main`, and `sync` afterwards — required
  as for a hotfix.
- **Ticket state never goes to `main` directly.** A ticket PR targets the UAT branch
  (`.claude/skills/pr-conventions/SKILL.md` → The ticket PR); `main` receives it only inside a
  promotion.
- **Nothing promotes on its own.** No workflow, schedule or script opens a promotion without
  `approve`, and `approve` runs on a human's word. No gate is ticked by an agent. No verb merges.
- **Nothing is generated per batch** — no branch per batch, no environment per batch, no URL
  per batch. The batch is what is on the one branch since the last promotion.
- **`sync` is the one push to the UAT branch a script makes**, on the operator's invocation,
  after a merge the operator authorised — a factory act (D11), like the close-out's commit. A
  ruleset that refuses it is a setup gap `init` names, not something to work around.

## Setting it up (`/setup` asks; the operator does the rest once)

`/setup` writes `uat.branch` and `uat.url` into `.icm/project.json` and runs
`promote-uat.sh init`, which writes an empty `batch.json` and prints the acts only the operator
can perform: push the branch once (`git push origin main:<uat>`), protect it like `main` (the
same required checks; the operator's identity allowed to push — `sync` needs it), assign the
domain to the branch in Vercel, decide the environment's variables, add `type:promote` to
`.github/labels.yml` and create the label. `setup.sh` section 3 reports the block and the file;
section 10 reports the label. On a Neon repo `db-env.sh init` adds the database's acts — the
integration's Preview-branching toggle, the migrate step in the build, the key as an Actions
secret for the cleanup workflow. Nothing here reaches outside the repo.
