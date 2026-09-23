# Lane — Hotfix (contract)

Invoked via `/pipeline hotfix "<what is wrong in production>"` — **by a human, always**: from a
`- production: ERROR` line in a Release record, a Vercel deployment-failed email, or a client
report. No alert carries a command into this lane and nothing parks a stub for it (a failed
`health-check.sh` parks a **bug**-lane stub that names this lane as the operator's option — it
never opens it). Everything
that is not named below is the **bug lane** (`lanes/bug/CONTEXT.md`): no story, no scope, no
spec, no gate checkbox; one invocation, one PR; the operator merges from GitHub; the agent never
merges. If the incident needs a product decision, STOP and route to `/pipeline scope`.

**What makes it a hotfix:** it opens **ready, not draft** — `new-run.sh --lane hotfix` opens the PR
non-draft so the **full gate and the product-app previews run at once**; that first ready push
builds everything, and on an incident that cost is accepted (`_shared/ci.md` → the first ready
push). The slug is `hotfix-<what>`, the label `type:hotfix`, and `notes.md` names the incident
and the recovery. Fix-forward stays the default; a revert is *available*, prepared by
`rollback.sh`, and still the operator's merge. **It bypasses UAT:** where the repo declares a UAT
environment every other PR targets the UAT branch, but a hotfix targets `main` — production is
wrong now — and `.icm/scripts/promote-uat.sh sync` afterwards carries the fix into UAT
(`.icm/uat/CONTEXT.md`).

## Inputs (read only these)

- The report: what is wrong, since when, who saw it — and the Release record's
  `- production:` line and deployment ids where the incident came from one.
- `.icm/scripts/deploy-status.sh --sha <merge-sha>` — production as it is now, once.
- `.icm/scripts/health-check.sh --sha <merge-sha>` — whether it answers, once; the stub it
  parked at Release, if any, is the report's first line.
- `.icm/scripts/rollback.sh --sha <merge-sha> --vercel [--revert]` — the two recoveries, prepared.
- The repo's code rules — the file `_shared/conventions.md` points at — and the subtree
  `AGENTS.md` files, where the repo has them.
- `.icm/_shared/project-rules.md` → **Learned rules** — the constraints earlier runs paid for;
  read them before the first edit, with the same standing as the code rules.
- `.icm/_shared/github.md` · `.icm/_shared/ci.md` — the lane-PR regime; what green means.
- Only the source files the fault implicates.

Context budget: the Inputs table above is the budget (see `.icm/CONTEXT.md` → Layers).

## Process

1. **Usage line first, then establish what is broken.** `usage-snapshot.sh <slug> hotfix start`.
   Read production once (`deploy-status.sh --sha <merge-sha>`, or the record's line). State the
   observed vs expected behaviour in one line each and the merge that introduced it, if known.
2. **Choose the recovery, with the operator.** Three shapes, named in `notes.md` as
   `- recovery:`:
   - `fix-forward` — the fault is small and understood: fix the cause on this lane's branch.
   - `revert <sha>` — the fault is the merge: `rollback.sh --sha <sha> --revert` prepares the
     branch, the lane run folder and opens **this** lane's PR ready (it calls `new-run.sh
     --lane hotfix` itself — do not open a second one). Read its `[WARN]` about migrations:
     with `migrations.reversible: false` the schema moved forward and the reverted code must
     tolerate it — say so in `notes.md`.
   - `vercel rollback dpl_…` — production must be back **now**: `rollback.sh --sha <sha>
     --vercel` prints the previous READY deployment and the exact CLI/REST call. **The operator
     runs it**; the lane records the id and still ships the code fix or revert behind it.
3. **Write `notes.md`** (template below) and, for fix-forward, open the lane PR — after the
   zero-trust gate, since the script commits and pushes: `.icm/scripts/security-check.sh <slug>
   --branch` → `RESULT: OK` (`BLOCKED` is a STOP; `.icm/skills/security-audit/SKILL.md`). An
   incident is exactly when a key gets pasted into a fix.

   ```bash
   .icm/scripts/new-run.sh <slug> --lane hotfix --summary "<what was broken → what's true now>"
   ```

   It commits `.icm/runs/<slug>/`, pushes, opens a **ready** PR (body: Summary with a `- slug:`
   line, Steps to test — **no checklist**), and labels it `type:hotfix`. `--ready` is implied.
4. **Settle the full gate.** `ci-status.sh <slug>` → `GREEN` with the product-app previews
   listed. `RED` → record it in `.icm/runs/<slug>/lane/output/error.log` (the shape in
   `stages/03_build/CONTEXT.md` → Outputs), fix on the branch, add the entry's `- resolved:`
   line, push, re-run. `PENDING` → re-run; nothing-has-failed-yet is not green. The one
   blocking call is the only CI read — never subscribe to the PR.
5. **Finish the run on the branch.** The changelog entry, where the repo has one, is
   `audience: internal` unless the client saw the fault — then `public`. Run
   `.icm/scripts/retrospective.sh <slug>` (`CANDIDATES n` → read, `--apply`, commit the rules
   with `notes.md`), then `usage-snapshot.sh <slug> hotfix end` (so the close-out commit carries
   the line), then `.icm/scripts/close-out.sh <slug>` → `CLOSED`, push, `ci-status.sh`
   once more → `GREEN`.
6. **STOP.** Report the preview URL, the recovery chosen, and — where the operator rolled Vercel
   back — that production is on the previous deployment until this PR merges. "Smoke-test, then
   squash-merge from GitHub." After their merge, Release's rule applies to a lane too: nothing
   watches production; the operator may run `deploy-status.sh --sha <merge-sha>` once, by hand.

## Outputs

**Run-scoped, without exception** (`.icm/_shared/stage-preamble.md` → Run-scoped isolation):
everything this lane writes lands under `.icm/runs/<slug>/lane/`, on the run's own branch.

`.icm/runs/<slug>/run.md` (with `- lane: hotfix`), `.icm/runs/<slug>/usage.md`, and
`.icm/runs/<slug>/lane/output/notes.md` — all archived by step 5:

```md
# Hotfix: <slug>

- incident: <what broke, since when, who reported — one line>
- introduced-by: <merge sha and PR, or unknown>
- recovery: fix-forward | revert <sha> | vercel rollback dpl_… (run by the operator at <time>)
- migration: <none in the merge | carried by the merge — schema moved forward; reversible: false>
- fix: <file/area>: <what changed>
- changelog: <entry added (audience: internal | public) | announce: none>
- learned: <n rule(s) appended to _shared/project-rules.md | none>
```

## Verify

- A human opened this lane; nothing automatic did. The incident and the recovery are named in
  `notes.md` before the PR was mergeable.
- One PR, `type:hotfix`, opened **ready**, no gate checkboxes; you never merged it, never called
  the rollback endpoint, never promoted a deployment. `rollback.sh` prepared; the operator acted.
- The full gate settled `GREEN` on the head the operator will merge — never inherited.
- `retrospective.sh` ran before the close-out; `close-out.sh` reported `CLOSED` and its commit
  is on the PR's head; both usage lines are in `usage.md`.
