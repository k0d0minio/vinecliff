# Stage 04 — Release (contract)

Invoked via `/pipeline release <slug>`. The `/pipeline` router reads this file and follows it.
Release is **one** stage and **one** human decision: by the time this runs, Build has flipped the
PR ready and pushed, the **full gate** has settled on that head (`_shared/ci.md` → verdict by
phase), and the operator has smoke-tested the post-flip previews by hand and ticked **Ready to
merge** — that tick attests all manual/signed-in testing, so this stage never re-asks for it. Your
job: confirm the factory agrees (CI green), run the review passes, park anything off-ticket, put
the one announcement file (where the repo has a changelog) and the close-out on the branch, and
squash-merge. **After the merge**: one read of production (`deploy-status.sh`), one call to the
repo's reporting hook (`report.sh announce` — unless the repo's `reporting.announce_from` is `ci`,
in which case its release workflow calls it and you record `deferred to CI`), and you are done.
What a channel is — a GitHub Release by default, Slack, email — is the repo's own
(`.icm/project.json` → reporting; `_shared/project-rules.md` → Reporting), never yours.

**Where the repo declares a UAT environment** (`.icm/project.json` → `uat`;
`_shared/promotion.md`), the PR you merge still targets `main` — but the squash puts the run in
front of the client at the one fixed UAT address and builds a **Staged** production deployment
that serves nothing yet. Production comes later, for the whole batch: the operator records the
client's word (`promote.sh approve --by`, which drafts a Release) and publishes the Release on
GitHub, and the repo's release workflow promotes. Everything in this stage is the same up to
step 8; step 9 reads UAT instead of production and announces nothing (the promotion announces).

**What may stop the merge — nothing else may:**

1. A **blocking CI failure** (`RESULT: RED`, or a `PENDING` that will not settle).
2. A **security-critical finding introduced by this diff** — an exploitable defect: auth bypass,
   leaked secret, tenant-scoping hole. **Measured first** by `security-check.sh <slug> --branch
   --audit` (step 4): a secret in what this branch added, or a high/critical advisory in the
   repo's lockfile (the audit runs on every Release read, whether or not this branch touched the
   dependency), is `BLOCKED n` with the redacted trace in `03_build/output/error.log`; the
   review passes cover what a pattern cannot. The one waiver is the operator's: a pre-existing
   advisory that cannot be bumped on this branch, recorded in the `## Release` record and
   re-read with `--branch --no-audit`.
3. A **deploy-breaking config finding** — measured, not eyeballed: `env.sh audit --changed`
   reports `GAPS` (a key this branch added is missing from a surface it is scoped to); a
   migration without a working `down` **in a repo that declares `migrations.reversible: true`**
   (forward-only repos are exempt — a revert there is the hotfix lane's, prepared by
   `rollback.sh`; on a MongoDB repo with `database.isolation: database` it is measured, not read:
   `db-branch.sh <slug> prove` → `UNPROVEN`, step 7); an index/migration mismatch; a support tier of `basic` or `retainer` with no
   fail-safe page or no Sentry key (`setup.sh` section 11 — report, never repair here).

Every other finding — style, structure, "should be refactored", anything not this ticket's — is
**parked as a stub in `.icm/intake/triage/`** (shape in `.icm/intake/CONTEXT.md`) and the merge
proceeds. A ticked box plus a green factory is the authorisation; do not manufacture reasons to
hold it.

## Inputs (read only these)

- `.icm/_shared/stage-preamble.md` — run it **first**: resolve the run or STOP.
- `.icm/runs/<slug>/run.md` — branch + PR pointers.
- `.icm/runs/<slug>/status.md` and `handoff.md` — where Build stopped (the canonical file pack);
  `FAILURE.md` for what it learned, which the close-out copies into the repo's rules.
- `.icm/runs/<slug>/02_define/output/spec.md` — acceptance criteria + `complexity:` (review
  effort) + `touches:` (conditional-pass triggers) + personas.
- `.icm/runs/<slug>/03_build/output/notes.md` — what changed, known gaps; the `## Release`
  record is appended here.
- `.icm/runs/<slug>/03_build/output/error.log` — what Build fixed on the way, entry by entry
  (absent on a clean run); `retrospective.sh` reads it in step 7.
- The branch diff (`git diff main...HEAD`) — what the reviews run against.
- `.icm/_shared/github.md` — gate read, review comments, merge; **pipeline PRs are never
  subscribed to PR activity** (its PR-events rule) — CI is read via `ci-status.sh` only.
- `.icm/_shared/ci.md` — what the checks are and what green means.
- `.icm/_shared/knowledge-map.md` — only the page(s) the change touches, for the docs sync and
  the changelog personas.
- The repo's docs sync skill and changelog skill, where it ships them (`_shared/project-rules.md`
  → Capability skills · Announcing) — the docs tree's own format rules and the changelog shape
  (including the one-line summary and the audience the announcement is built from).

Context budget: the Inputs table above is the budget (see `.icm/CONTEXT.md` → Layers). Record
overruns on a one-line `Context budget:` note in the `## Release` record.

## Process

1. **Run the shared preamble**, then the first act of every stage:
   `.icm/scripts/usage-snapshot.sh <slug> release start` (one `- usage:` line in the run's
   `usage.md`; `SKIP` is fine, never a stop). Read `status.md` and `handoff.md`; set `status.md`
   to `phase: release`. Confirm Build finished: `notes.md` exists and the
   PR is open (not draft). An acceptance criterion Build already flagged as unmet → send back to
   `/pipeline build <slug>`; don't release known-broken work. Then **project the stage label**:

   ```bash
   .icm/scripts/project-labels.sh <slug> --stage release
   ```

   The PR reads `stage:release` from the moment the stage starts. CI's own projection would only
   move it once the `## Release` record is pushed (step 7), at the end of the stage — and the
   close-out push that follows hides the run folder from the labels step altogether — so Release
   is the one stage that projects its own label (`_shared/github.md` → Labels).

2. **Read the gate.** `pull_request_read` (method `get`) → **Ready to merge** must be `[x]`.
   Unticked → **STOP** and tell the operator — this is the stage's one stop-and-wait, and you
   never tick it yourself. The tick means the preview was smoke-tested by hand; anything that had
   failed that testing would have gone back to Build instead.
3. **Establish CI green — the precondition for everything below.**

   ```bash
   .icm/scripts/ci-status.sh <slug>
   ```

   `RED` → fix on the branch if it is this ticket's, else back to `/pipeline build <slug>`.
   `PENDING` → re-run the call; an unsettled run is not a pass. `GREEN` → note the SHA and carry
   on. The script names the tier: a ready head settles the **full gate** — a cheap-tier verdict
   here means the PR is somehow still draft, which is Build unfinished, not a pass.

   Your own docs/changelog/close-out pushes below need not re-earn this verdict at full price
   where the repo's quality workflow carries a settled verdict forward across a push whose diff
   is entirely verdict-preserving (`.icm/**`, markdown, the archive move) — whether it does, and
   how it says so, is the repo's own (`_shared/project-rules.md` → The factory). Any code in the
   push — the merge of `main` in step 7 included, when `main` moved — takes the full path again.
   Re-run `ci-status.sh` after the last push either way — the carry is CI's optimisation, never
   a licence to skip the settled-verdict read.

4. **Run the review passes, then triage every finding by the rule.**
   - **Readiness, measured first:** `.icm/scripts/env.sh audit --changed` → `RESULT: OK`. `GAPS`
     is stop class 3 with the rows naming the fix (declare the key, add it where it is scoped —
     the value is the operator's). `UNKNOWN` is not `OK`: a surface could not be read — re-run
     once, then stop and say which (`env-check.sh` names a project the token cannot see). A `support.tier` of `basic`/`retainer` with no fail-safe page
     or Sentry key (`setup.sh` section 11) is the same class.
   - **The gate, over the whole branch:** `.icm/scripts/security-check.sh <slug> --branch --audit`
     → `RESULT: OK` — the deterministic input to stop class 2 (a leaked secret, a known-high
     dependency this branch introduced), read before the diff is. `BLOCKED n` is stop class 2 with
     the redacted trace in `error.log`: follow `.icm/skills/security-audit/SKILL.md` → On BLOCKED
     and send back to Build. A `[WARN]` that gitleaks is absent goes in the record, not under it.
     The audit runs on every Release read, whether or not this branch touched the dependency —
     the repo ships what its lockfile pins. A pre-existing advisory that cannot be bumped on
     this branch is the **operator's** call: a chore lane first, or their waiver — `audit
     waived — <advisory>, <why>` in the record's `security` slot — and the re-read is
     `security-check.sh <slug> --branch --no-audit`. The waiver is theirs, never yours.
   - **Code review — always, in-session.** Run **`/code-review`** at the spec's complexity
     (`trivial → low`, `standard → medium`, `complex → high`). There is no CI review job; this
     pass is the review.
   - **`/production-readiness`** — only if the diff touches DB, auth, payments, or env vars.
   - **`/security-review`** — only if the diff touches auth, payments, PII, or route policies.
   - **The triage rule** for every finding, review comments included:
     - Trivial **and** in-ticket → fix now, on this branch.
     - Security-critical or deploy-breaking (the two stop classes above) → **STOP**, report
       exactly what and why, send back to Build.
     - Everything else → one stub in `.icm/intake/triage/`, and move on. Never widen the PR to
       fix it here. **Cap notice:** if the folder then holds more than 60 active stubs
       (`ls .icm/intake/triage/*.md | wc -l`; `intake/CONTEXT.md` → Triage → cap), say so in
       the step 9 report — `triage/ holds N active stubs (cap 60) — run triage report` — and
       name `triage report` as the suggested next command. The stub is still written and
       the merge still proceeds.
5. **Sync the docs (in this PR).** If the change alters documented reality — a page under the
   docs tree (`docs_path` in `.icm/project.json`; `_shared/knowledge-map.md` names them) — update
   the affected page(s) on the branch via the repo's docs sync skill, where it ships one
   (`_shared/project-rules.md` → Capability skills); otherwise edit the page under the docs
   tree's own conventions. Record "no docs impact" when true — and always, for a repo with no
   docs tree.
6. **Write the one announcement file**, where the repo has a changelog
   (`_shared/project-rules.md` → Announcing names where it lives and the skill that owns its
   shape): the entry for today (the merge date) and this slug, with its one-line summary and its
   audience (`public` for user-facing, `internal` for infra/security/perf — internal entries are
   announced but not listed publicly, where the repo makes that distinction). This file is the
   changelog and the ship note in one, and its summary is what the post-merge notification
   (step 9) sends. Truly nothing to announce, or a repo with no changelog → write no page and
   record `announce: none`.
7. **Bring `main` in, then push the record — in two pushes, in this order.**

   **(a) Merge the base branch into the run branch** — a merge commit, never a rebase:

   ```bash
   git fetch origin && git merge --no-edit origin/main     # every repo — main is the only base (D39)
   ```

   This is what lets the close-out's sibling-run check see runs archived on the base branch since
   the branch was cut — without it, an epic whose last sibling merged yesterday looks unfinished and
   stays in `.icm/intake/`. Resolve conflicts if there are any; **a conflict inside
   `.icm/runs/<slug>/` itself is a STOP** — someone else wrote to this run, and you do not guess
   which record is true.

   **Then check the migration order, every time `main` was merged in** — runs are built in
   parallel, and a sibling that merged first can leave this run's migrations stamped *before*
   `main`'s newest, which no diff shows and no merge conflict catches:

   ```bash
   .icm/scripts/check-migrations.sh
   ```

   `RESULT: OK` or `SKIP` → carry on. `RESULT: STALE <n>` (or `MISNAMED <n>` — a migration not in
   the repo's declared stamp form, `migrations.stamp`) → this is the deploy-breaking class
   (stop class 3) with a mechanical, in-ticket fix, so fix it here: re-run with `--apply`, read
   the renames it lists (and anything it says "also mentions" an old stamp — that file is yours
   to correct), and commit them on the branch as their own commit
   (`fix: <slug> — re-stamp migrations after main`). A rename is code — that push takes the full
   CI path. If the repo keeps a persistent preview database that already applied the old stamps,
   reset it the way the repo says (`_shared/project-rules.md` → The factory) before trusting a
   preview again — and the run's own database, where `db-branch.sh` bound one, is dropped and
   re-made (`down`, then `up`; the `database-migration` skill). The script renames and never
   commits; it never touches a migration `main` already has.

   **On a MongoDB repo with `database.isolation: database`, prove the migrations on the head
   that will merge** — after the order check, because a re-stamp is exactly what the proof's
   last step replays:

   ```bash
   .icm/scripts/db-branch.sh <slug> prove
   ```

   `RESULT: PROVEN` or `SKIP` → carry on. `RESULT: UNPROVEN <n>` → stop class 3: a `down` that is
   missing or does not restore the indexes (where `migrations.reversible` is true), an `up` that
   does not reproduce its shape, or an `up` that is not idempotent — the lines above the verdict
   say which file and which. The fix is on this branch, like a re-stamp; the `## Release`
   record's `- migrations:` line says `proven` once it reads `PROVEN`.

   **(b) Run the retrospective, then append the `## Release` record.** First, while the run
   folder is still live:

   ```bash
   .icm/scripts/retrospective.sh <slug>
   ```

   It reads the run's `error.log` (what Build fixed, entry by entry — a `security-check.sh`
   block among them) and the archive's, and names the error classes that earn a rule: one Build
   flagged with `- rule:`, or one that recurred (`--min`, default 2, across this run and the
   archived runs) and carries a `- resolved:` line. `RESULT: SKIP` (no `error.log` — a clean
   run) or `NONE` → carry on. `CANDIDATES n` → read them: they are the session's own words from
   the moment of the fix. Re-run with `--apply` to append them to `_shared/project-rules.md` →
   Learned rules (it appends, never commits); a candidate that reads as a slip rather than a
   constraint is deleted from the file before the commit — that edit is the editorial control,
   and the PR is where the operator sees the rest. (`FAILURE.md`'s own `## Learned rules` — what
   no tool logged — reach the same section through `close-out.sh` in step (c).) Then bring the
   pack to its final state — `status.md` (`phase: release · step: done · ci: GREEN`),
   `handoff.md` ("merged and archived; nothing to pick up"), `FAILURE.md` with any retrospective
   this stage added — and **append the `## Release` record to `notes.md`** (template below) with
   its `- learned:` line, commit it all **with the docs edits, the changelog page and the
   appended rules**, and push. This push is the one the Pipeline workflow's release-completeness
   step reads — it sees `notes.md` at its `.icm/runs/` path, with the record in it, next to the
   docs and changelog files it checks for.

   **(c) Then close the run out, as its own commit and its own push:**

   Record the stage's end first — `.icm/scripts/usage-snapshot.sh <slug> release end` — so the
   line rides in the close-out commit: nothing written after the close-out (or after the merge)
   reaches the run's PR. Then run the close-out:

   ```bash
   .icm/scripts/close-out.sh <slug>
   ```

   It first copies the run's `FAILURE.md` → `## Learned rules` into `_shared/project-rules.md`
   (`run-pack.sh --sync-rules`, appends only — the next run in this repo starts with them), then
   `git mv`s `.icm/runs/<slug>/` into the runs archive (`runs_archive` in `.icm/project.json`;
   `.icm/runs/_done/` by default) — and the intake epic with it, if this stub was the last one it
   had left unshipped — and commits that on the branch. (On a UAT repo nothing else is written:
   the batch is `git log <last published release>..main`, `_shared/promotion.md`.)
   `RESULT: CLOSED` → push. `RESULT: STOP` → read the reason and fix it; do not merge a run you
   could not close out. The move is the last thing written because the record it archives has to
   be complete first, and it travels alone so the push carries **only the move** — the rename
   hides the `.icm/runs/` path from CI, which is why the record went first.

   After the last push, **re-run `ci-status.sh --pr <number>` on the head you just pushed** — one
   settled verdict per push, and the last one is the verdict that authorises the merge. Prefer
   `--pr <number>` here; `<slug>` still works (the script resolves the run from the archive).

8. **Merge.** Re-read the gate (one call — it must still be `[x]`), then `merge_pull_request`,
   `merge_method: "squash"`, attempted **once** (`_shared/github.md`). The squash carries the run
   record, docs, changelog **and the archive move** onto `main` — the merge is what publishes the
   close-out, which is why nothing has to run afterwards to finish the job.
9. **Repoint, read production once, announce, report.** Update the PR body's spec link to its
   `blob/main/` form (`update_pull_request`) — the only post-merge edit. Then:

   **(a) Production, once.** `.icm/scripts/deploy-status.sh --sha <merge-sha>` — it waits,
   bounded, for the merge commit's production deployment(s) and prints the one line the record
   takes: `- production: READY on <sha> — web dpl_… (prev dpl_…) · docs dpl_…`, or
   `ERROR <project> — see the hotfix lane`, or `PENDING` after the bound, or `SKIPPED` when
   every project's ignore step canceled its build (a merge touching no app — production
   unchanged, the live deployment named; one skipped project beside READY ones stays `READY`),
   or `not declared (no deploy block)`. An `ERROR` un-merges nothing and starts nothing: it is a
   line in the record and the operator's call to open `/pipeline hotfix`. **On a UAT repo** the
   merge deployed to the UAT environment, so read that instead — `.icm/scripts/deploy-status.sh
   --sha <merge-sha> --uat` — which prints `- uat: READY on <sha> — web dpl_… · <the fixed UAT
   address>`; production only built a Staged deployment, and is read by the release workflow
   after the promotion.

   Then the application's own word, once: `.icm/scripts/health-check.sh --sha <merge-sha>` —
   one GET per endpoint the repo declares (`health_endpoint` in `.icm/project.json`, or per
   project under `deploy.projects[]`), expecting 200, three attempts with backoff. It prints the
   one `- health:` line the stop message takes: `OK`, `SKIP — no health endpoint declared`, or
   `FAIL <endpoint>` — on which it has already called `report.sh alert` (the repo's channels;
   `SKIPPED` where none is mapped) and parked **one triage stub**
   (`.icm/intake/triage/health-check-<date>-<sha>.md`, `lane: bug`, `complexity: high`) that it
   did **not** commit. A `FAIL` un-merges nothing and starts nothing either: name the stub in
   the report, and the operator opens `/pipeline hotfix` — or commits the stub for the bug lane
   — with the recovery `rollback.sh` prepares. Never re-run it in a loop; one bounded read is
   the whole of the pipeline's post-release health check. **On a UAT repo, skip it here** —
   production did not change; it is read after the promotion.

   **(b) Announce.** On a UAT repo, do not: record `announce: deferred to promotion` — the client
   is told once, when the batch reaches production (the release workflow announces on the
   publish, `_shared/promotion.md`). Otherwise, unless the
   record says `announce: none`: where `reporting.announce_from` is
   `session` (the default), call the repo's hook —
   `.icm/scripts/report.sh announce "<summary>" --slug <slug> --sha <merge-sha> --url <pr-url>
   [--audience internal]` — the summary being the changelog page's one-liner where there is one,
   else the PR's Summary line; it cuts the GitHub Release (idempotent by tag) and whatever else
   the repo mapped, prints `SKIPPED <channel>: <VAR> unset` for a channel it could not reach,
   and exits 0 always. Where `announce_from` is `ci`, do not call it — record
   `announce: deferred to CI` and let the repo's release workflow make the same call. **Never
   wait or poll for that workflow.**

   **(c) The record is already merged — say it in the report instead.** The `- production:` and
   `- health:` lines and the announce outcome go in your stop message (the record on `main`
   cannot take a post-merge line without a second PR, and there is no second PR). Then tell the
   operator: what merged (SHA), production's state and health, what announced where, what was
   parked in triage (by stub name — the health stub, if one was written, is uncommitted and
   waits for them), and that the run is archived — on a UAT repo, that it is now on the UAT
   address and `promote.sh status` shows the batch. The usage `end` line was
   written before the close-out in step 7; nothing else is written after the merge.

## Outputs

**Run-scoped, without exception** (`.icm/_shared/stage-preamble.md` → Run-scoped isolation): Release has no folder of its own — its record is appended
inside the run's folder, on the run's own branch `claude/<slug>`, and anything else it drafts
while working goes under `.icm/runs/<slug>/` too, before the close-out moves the folder.

Appended to `.icm/runs/<slug>/03_build/output/notes.md`:

```md
## Release

- gate: Ready to merge ticked — merge authorised
- ci: GREEN on <sha> (ci-status.sh, after the last push)
- reviews: code <effort> · security <security-check.sh --branch --audit: OK | BLOCKED → sent back | audit waived — <advisory>, <why> (the operator)> <+ /security-review — result | n/a> · readiness <env.sh audit --changed: OK | n/a>
- parked: <triage stub filename(s) | none>
- migrations: <ok | skip — none of this run's own | re-stamped <n> after main (check-migrations.sh --apply)>[ · proven (db-branch.sh prove) — a MongoDB repo with isolation: database]
- learned: <n rule(s) appended to _shared/project-rules.md | none | skip — no error.log>
- docs: <pages updated | no docs impact> · announce: <public | internal | none | deferred to CI | deferred to promotion>
```

Plus `.icm/runs/<slug>/usage.md` gaining the `release start` and `release end` lines (the file
travels with the archive). The post-merge `- production:` and `- health:` lines and the announce
outcome are reported in the stop message (step 9c).

Plus the changelog page, where the repo has one (unless `announce: none`), and any docs edits —
all in the one PR.

## Verify (before declaring released)

- `stage:release` was projected at step 1, before anything else was read or written.
- The gate was ticked **before** the merge and re-read after the last push; you never ticked it.
- The merge rested on a **settled `GREEN` from `ci-status.sh` on the exact head that merged** —
  established after your last push, never inherited, never read off a Vercel event or the
  `Vercel Preview Comments` check. Merged once; never on RED, never on PENDING.
- `security-check.sh <slug> --branch --audit` read `OK` on the branch that merged; a `BLOCKED`
  was never merged around. An audit waiver, where there is one, is in the record in the
  operator's words, not yours.
- `check-migrations.sh` read `OK` or `SKIP` on the head that merged — after the merge of `main`,
  and after any re-stamp it asked for. A `STALE` was fixed on the branch, never merged past.
  On a MongoDB repo with `database.isolation: database`, `db-branch.sh <slug> prove` read
  `PROVEN` or `SKIP` after it; an `UNPROVEN` was fixed on the branch, never merged past.
- `retrospective.sh` ran on the live run folder **before** the close-out moved it; what it
  appended is in the head that merged, and the record's `- learned:` line says how many. A rule
  you judged a slip was deleted from the file, never left for the next run to obey.
- The only holds you applied were the three stop classes. Every other finding is a triage stub
  (named in the record), not an unmerged PR and not a widened diff.
- The conditional passes ran whenever `touches:`/the diff matched — "n/a" is recorded with the
  reason, never silently skipped.
- The `## Release` record and the changelog page (where the repo has one) were **committed
  before the squash** — the merge is what publishes them, so what is in them at merge time is
  what is true and what is sent.
- `close-out.sh` ran on the branch **after `origin/main` was merged in**, reported `CLOSED`,
  and its commit was pushed **on its own** and is in the head that merged. This bullet is the
  whole prevention: a merge without it leaves the run in `.icm/runs/` — a fault the post-merge
  verification, where the repo has one, reports to the project's alert channel
  (`_shared/project-rules.md` → Announcing) — and once merged, nothing can carry the move into
  that PR. There is no recovery PR; the run's own PR is the only vehicle.
- After the merge you touched nothing but the PR body's spec link, made one read of production
  — or of UAT, on a UAT repo — (`deploy-status.sh`), one health read (`health-check.sh` — its stub,
  if it wrote one, left uncommitted and named in the report; skipped on a UAT repo until the
  promotion) and one call to `report.sh announce` (or recorded `deferred to CI` / `deferred to
  promotion`), and reverted nothing by your own decision — a revert is the hotfix lane's,
  prepared by `rollback.sh` and merged by the operator.
- Both usage lines are in `usage.md` — `release start` as the first act, `release end` just before
  the close-out, so the archive commit carries it.
