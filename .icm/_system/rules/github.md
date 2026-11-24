# Git and GitHub

## Transport
The scripts in `.icm/_system/scripts/` talk to GitHub with `gh api` (the REST API). Use the
scripts. Do not open, change or merge a pull request by another route.

| Act | The one way |
|---|---|
| Open the pull request | `new-run.sh` |
| Write the body again after a spec change | `new-run.sh <ticket> --refresh-body` |
| Read the run, the pull request and the gates | `resolve-run.sh <ticket>` |
| Read CI | `ci-status.sh <number or ticket> [--watch]` |
| Write an answer that the operator gave in the chat | `questions.sh <ticket> --answer Q1 "<words>"` |
| Change draft to ready | `gh pr ready <number>` |
| Close the run and merge | `release.sh <number>` |

`gh pr ready` does not work in a cloud session. There, ask the operator to click "Ready
for review".

## Branches
1. One run has one branch. `new-run.sh` makes it from the default branch, or keeps the
   branch that the session is on. In a worktree of the Claude application it renames the
   worktree's branch to the branch of the ticket. Do not rename it by hand.
2. Never commit on the default branch. Never push to it.
3. To take new work from the default branch, merge it into the run's branch. Do not
   rebase and do not force-push.
4. Commit small. Push after each commit that the operator must be able to see.

## Runs in parallel
Other runs merge into the default branch while this run works or waits.
1. `resolve-run.sh` and `ci-status.sh` say when the default branch moved and the branch
   conflicts with it. Then merge the default branch into the run's branch (`git fetch
   origin && git merge origin/<default>`, not a rebase), resolve, commit, push, and read CI.
2. A run that waits for the operator merges the default branch in when another run merged,
   before it shows its gate card again.
3. `merge.sh` brings a branch that is only behind up to date, and waits for its checks.
4. Numbered migration files (`0035_<name>.sql`): when the merge brings a file with the
   number of this run's migration, give this run's file the next free number, correct
   each reference to it, and write the old and the new number in `handoff.md`.

## The pull request
- One run has one pull request. It starts as a draft.
- The title is `<KEY>: <ticket title>` for a Linear ticket, and the stub title for a
  markdown ticket. `new-run.sh` writes it.
- The body comes from `.icm/_system/templates/pr-body.md`. Do not edit the gate lines.

## CI
- `ci-status.sh` prints `RESULT: GREEN`, `RESULT: RED` or `RESULT: PENDING`.
- With `--watch` it waits in the script, 30 minutes at most. Give it one time, in the
  background if the session permits, and wait for its last line. Do not poll by hand, do
  not put a loop around it, and do not use `gh run watch` or `gh pr checks --watch`.
- `RESULT: STOP GitHub rate limit, resets at HH:MM`: stop and say that time. Read again
  after it, one time.
- On RED, read the failed check, correct the cause, push, and read again.
- A script that stops says why on its `RESULT: STOP` line. Correct that cause and give the
  same command again. Never delete or edit a run file by hand to get past a stop.
- Do not run the same check locally to "save time". CI is the source of truth.
