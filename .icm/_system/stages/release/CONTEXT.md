# Stage — Release

Language: en

## Purpose
Close one run and merge its pull request, after the operator's Ready to merge tick.
Release is the end of a spine run and of a lane run.

Release is one script, `.icm/_system/scripts/release.sh <number>`. Two things start it:
- the command `release <ticket>` in a session, or
- the button "Merge now" on the gate card of the BAXTER HUD.

## Inputs
- `.icm/runs/<id>/run.md`, `status.md`, `handoff.md`.
- `.icm/_system/rules/gates.md` and `.icm/_system/rules/github.md`.

Release does not read the product code. It does not change the product.

## Process
In a session:
1. `.icm/_system/scripts/resolve-run.sh <ticket>`. Continue only on `RESULT: OK`.
2. Read `ready_to_merge` in its output. If the value is not `yes`, stop. Tell the
   operator to tick Ready to merge, and give the pull request link.
3. For each client request in `- requests:` of the spec: when the newest checktest run
   shows `passed` for each of its AC lines, set its status to `verified`, commit and
   push (`features/requests.md`). Never set `accepted`.
4. `.icm/_system/scripts/release.sh <number>`. It does these steps, and each step can
   stop it:
   - It reads the tick, and waits for green checks.
   - `close-out.sh`: it moves the run to `.icm/archive/<id>/` and the ticket stub to
     `_done/`, in one commit. It pushes.
   - It waits for green checks on the new commit. The job `code` does not run again for a
     commit of records only (`ci/icm-only.sh`).
   - `merge.sh`: it checks the tick, the checks and the conflicts again. Then it merges.
5. On `RESULT: STOP` with a conflict: merge the default branch into the run's branch,
   push, and run step 4 again. On each other `RESULT: STOP`: stop and give the reason.
6. Stop with the stop report: the merge commit, and each act that is left for the
   operator.

Only three things can stop a merge: no tick, a check that is not green, and a conflict.
Do not add a fourth.

## Outputs
- The pull request merged into the default branch, and its branch deleted.
- `.icm/archive/<id>/` with `run.md`, `handoff.md`, and `spec.md` and `findings.md` when
  they exist.
- The ticket stub in `_done/`.

## Gates
- Ready to merge: the operator ticks the box in the pull request after the operator
  tested the change. `release.sh` refuses without the tick. You do not tick it.
