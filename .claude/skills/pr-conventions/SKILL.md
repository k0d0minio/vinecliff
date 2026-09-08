---
name: pr-conventions
description: The estate's git and PR rules — branches, commits, what goes to main, what CI owns. Use before committing, branching, pushing, or opening a PR in any estate repo.
---

# PR conventions — how code ships in this estate

Canonical doctrine: icm-board's `_system/README.md` § House doctrine. This skill is the
working knowledge.

## Branches and what goes where

- Code changes go through a **PR on a `claude/` branch** — never straight to `main`.
- **Ticket-only commits go straight to `main`** (planning is data): only `.icm/` paths,
  message `Plan: <one line>` or `Wrap: <one line>`.
- Never rewrite history on a shared branch; never force-push `main`.

## Committing

- **Stage paths explicitly — never `git add -A`.** Anything dirty that the task didn't
  touch is left strictly alone.
- Commit messages say what changed and why in the first line; no model identifiers.
- **No secrets in git, ever.** Env vars only. A plaintext credential found anywhere is a
  P0 — flag it immediately, do not commit around it.

## CI owns verification

- **CI is the source of truth. Never run `build`/`lint`/`typecheck`/`test` locally** —
  push and read the checks. A red check is the task; a green check is the proof.
- Gates and checkboxes in tickets or pipeline docs are **human checkboxes** — read
  them, never tick them.

## The agent economy — reading a PR without drowning in it

Every repo here deploys on Vercel, so one push produces a burst of events: each deploy
target cycling `pending`→`success`, the deploy bot posting and then re-editing its comment
table, every Actions job starting and finishing. None of them is a verdict, and a
subscribed session wakes for each one.

- **Never subscribe to PR activity** — not to a stub's PR, a chore PR or a one-off fix. If
  you find yourself subscribed because the harness did it for you (some auto-subscribe
  after opening a PR, some instruct you to watch whatever you open), unsubscribe
  immediately and say so. A harness default does not override the repo's rule about its
  own PRs.
- **One blocking read per push: `gh pr checks <number> --watch`.** The waiting happens
  inside `gh`, so it costs wall-clock rather than model turns. Never a sleep-and-re-read
  loop, and never a bare glance at a run that hasn't settled — one glance at an unsettled
  run is worth nothing. A fresh push earns a fresh verdict: re-run the call rather than
  reasoning from the last one.
- **That one call is the whole verdict here.** `gh pr checks` reads *both* of GitHub's
  surfaces — Actions check runs **and** commit statuses, which is where the Vercel deploys
  land. In an estate repo with no workflows at all, the only rows it returns *are* commit
  statuses. That surface is what an agent reading check runs alone misses entirely, and
  why pipeline repos wrap the same question in a script.
- **PENDING is a third value, not a soft green.** `gh pr checks` exits `0` when everything
  passed and `8` while anything is still running — an `8` is the blocking call doing its
  job, not a problem. **Exit `1` is ambiguous: read the message.** It is either a failed
  check or `no checks reported on the '<branch>' branch`, which means GitHub has not
  registered a workflow yet — it takes seconds, and a read fired the moment after
  `git push` finds an empty list. **`--watch` does not wait that out**; it returns at once.
  An empty list on a fresh push is PENDING — not green, and not a failure either. Give it a
  few seconds and re-run the call. Not-yet-red is never green.
- **Read the description, not just the state.** A Vercel row reading `Skipped - Not
  affected` is reported `pass` and built nothing: there is no preview on that commit, so
  it cannot host a smoke and it is not evidence the deploy is green
  (`gh pr checks <n> --json name,bucket,description` when the distinction matters).
  `Vercel Preview Comments` is pure noise — a zero-second, always-`pass` marker that the
  comment bot is wired up. Where there are no workflows it is one of only two rows, so a
  green reading rests on the single real `Vercel` status; never quote the marker as one.
- **Never act on a deploy event or on the bot's comment-table edits.** Deployment-status
  events, the table and its re-edits carry no verdict. Establish the state with the call
  above before touching anything.
- **Your own pushes come back as events.** The stream echoes what you just did — that is
  not a new instruction, and a burst from one push is one occurrence, not one per event.
- **Anything longer-running is a scheduled check-in** — one timed wake that reads the state
  once and re-arms — never a subscription. Watching a PR event-by-event stays a deliberate,
  human-requested act ("babysit this PR"), never something a session opts into for itself.
- **Narrow reads.** One call per question, the smallest page that answers it: name the
  `--json` fields you need, keep `--limit` tight, never page through diffs or comment
  threads the task doesn't need.

Repos on the pipeline profile carry this in `.icm/_shared/github.md` and `.icm/_shared/ci.md`,
gated by `.icm/scripts/ci-status.sh` — read it there rather than here. Each rule lives once.

## Finishing

- The PR that finishes a stub's work `git mv`s the stub to its epic's (or triage's)
  `_done/`. The `wrap-reminder` Stop hook asks about this at session end when a branch
  shipped work matching an open stub it never touched — it asks, it never moves the
  file. Partial work is a legitimate answer: say so and carry on (status is positional;
  there is no field to flip).
- Work discovered mid-PR that doesn't belong in it becomes a new stub, not scope creep —
  park it in `.icm/intake/triage/` (or its epic) and reference it in the PR description.
