---
name: pr-conventions
description: "The git and GitHub mechanics of a ticket in this repo. They are the branch, the commit, the push, the pull request body and the CI read. Use before you commit, cut a branch, push, open or edit a pull request, or read CI. Triggers: commit, branch, push, pull request, PR, CI, checks."
---

# Pull request conventions — the mechanics

The contract is `.icm/intake/CONTEXT.md`. It holds every shape and the loop. This skill adds
the git and GitHub mechanics that the contract does not hold. Where the two disagree, the
contract wins.

Every GitHub call is REST: `gh api`, `gh run` or `gh workflow run`. Never `gh pr`. The contract's
§ The loop says why. `{owner}/{repo}` below is literal: `gh api` fills it from the git remote.

## Branches

- A ticket's branch is `<slug>` or `triage/<slug>`. `.icm/scripts/new-run.sh` cuts it on
  `main`, or keeps the branch of the worktree it runs in. Do not cut a ticket branch by hand
  (why: the script also moves the stub and opens the pull request · 2026-10-27).
- `main` changes by pull request only. Do not commit to `main`. Do not push to `main`.
- Do not rewrite the history of a pushed branch. Do not force push. A wrong commit gets a new
  commit that fixes it.

## Committing

- Stage each path by name. Never `git add -A` or `git add .`. Read `git status` before the
  commit. Leave every file that the ticket did not change (why: another session or a person can
  have work in the same checkout · 2026-10-27).
- The type comes from the contract's § Commit types. The first line says what changed. No
  model name in a commit.
- No secret in git. A token, a key or a password goes in an environment variable. An
  `.env.example` holds names only.
- A plaintext credential found in any file: flag it in the chat first, before any other step.
  Do not commit around it. Do not copy it.

## CI owns verification

- Never run build, lint, typecheck, test, format or dev locally. Push, then read CI. A red
  check is the work. A green check is the proof.
- One blocking read per push: `.icm/scripts/checks.sh <n> --watch`. The wait happens inside the
  script and costs no model turn. Do not loop on a sleep and a read. A new push needs a new read.
- The script reads both surfaces of GitHub: the Actions check runs and the commit statuses.
  Vercel reports on the commit statuses. A read of the check runs only misses the deployments.
- Read the exit code:
  - `0`: every check passed.
  - `8`: a check is still pending after 30 minutes.
  - `1`: a check failed, or no check ran. Read the message.
- Pending is not green. An empty list just after a push is pending too: GitHub has not
  registered the run yet. `--watch` waits for it. Without `--watch`, an empty list exits `1`.
- Read the description, not only the state. The script prints it after the state.
  - A Vercel row `Skipped - Not affected` passed and built nothing. That commit has no preview.
  - `Vercel Preview Comments` is a marker that always passes. It is no verdict.
- Never subscribe to the events of a pull request. One push makes a burst of events:
  deployments, bot comments, job starts. No event is a verdict (why: a subscribed session wakes
  for each one · 2026-10-27).
- Your own pushes come back as events. They are not instructions. Do not act on a deployment
  event or on an edit of a bot comment.
- Narrow reads. One call per question. Name the `--json` fields. Keep `--limit` small. Do not
  read a diff or a comment thread that the ticket does not need.

## The pull request body

- The body follows `.github/pull_request_template.md`. The loop's step 6 says what to fill
  before the flip: the title, the `preview:` line, `What changes`, `How to test` and `Parked`.
- Edit the body from the live body. Do these steps:
  1. Read it into a file: `gh api repos/{owner}/{repo}/pulls/<n> --jq .body > <file>`.
  2. Change only your lines in that file.
  3. Write it back: `gh api -X PATCH repos/{owner}/{repo}/pulls/<n> -F body=@<file>`.

  Never write a body from a local copy (why: Jamie ticks the gates on GitHub, and a stale copy
  removes the ticks · 2026-10-27).
- Set the title: `gh api -X PATCH repos/{owner}/{repo}/pulls/<n> -f title="<title>"`.
- Flip a draft to ready: `gh api -X POST repos/{owner}/{repo}/pulls/<n>/ccr/ready_for_review`. If
  the call fails, say so in the stop report. Then Jamie flips it on GitHub.
- Never tick a gate box. Remove a tick only where the contract's § Revise says so.
- Keep each gate anchor as it is. The desk finds the gates by their anchors.

## Finishing

- The stub is in `_done/` from the first commit of the branch. `new-run.sh` moves it, and the
  merge makes the move true. Do not move it back.
- A finding that is not this ticket's becomes a triage stub in this pull request, listed under
  `Parked`. Do not widen the diff to fix it. `ticket-craft` says how to write the stub.
- A change to a file that the blueprint renders: stop, as each lane says.

## The stop report

The contract's § The stop report holds the shape. Use it at every stop. Name a gate with its
pull request link. Never tick a gate from the chat.
