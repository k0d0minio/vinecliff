# Git and GitHub

## Transport
The scripts in `.icm/_system/scripts/` talk to GitHub with `gh api` (the REST API). Use the
scripts. Do not open, change or merge a pull request by another route.

| Act | The one way |
|---|---|
| Open the pull request | `new-run.sh` |
| Write the body again after a spec change | `new-run.sh <ticket> --refresh-body` |
| Read the run, the pull request and the gates | `resolve-run.sh <ticket>` |
| Read CI | `ci-status.sh <number> [--watch]` |
| Change draft to ready | `gh pr ready <number>` |
| Close the run and merge | `release.sh <number>` |

`gh pr ready` does not work in a cloud session. There, ask the operator to click "Ready
for review".

## Branches
1. One run has one branch. `new-run.sh` makes it from the default branch, or keeps the
   branch that the session is on.
2. Never commit on the default branch. Never push to it.
3. To take new work from the default branch, merge it into the run's branch. Do not
   rebase and do not force-push.
4. Commit small. Push after each commit that the operator must be able to see.

## The pull request
- One run has one pull request. It starts as a draft.
- The title is `<KEY>: <ticket title>` for a Linear ticket, and the stub title for a
  markdown ticket. `new-run.sh` writes it.
- The body comes from `.icm/_system/templates/pr-body.md`. Do not edit the gate lines.

## CI
- `ci-status.sh` prints `RESULT: GREEN`, `RESULT: RED` or `RESULT: PENDING`.
- With `--watch` it waits in the script, 30 minutes at most. Use it. Do not poll by hand.
- On RED, read the failed check, correct the cause, push, and read again.
- Do not run the same check locally to "save time". CI is the source of truth.
