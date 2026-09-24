# Lane — Handover (contract)

Invoked via `/pipeline handover` — **by the operator, when the build is finished**: the last
lane of an engagement, the one that turns a repository into something the client (or any
developer) can run without its author. The bug lane's economy: draft, the cheap tier, one PR,
the operator merges from GitHub; the agent never merges. It records; it invoices nothing,
creates no account, sends nothing.

## Inputs (read only these)

- `.icm/project.json` — `support` (the tier the deal agreed), `deploy`, `reporting`; and
  `_shared/project-rules.md` → People and gates · Support.
- `.icm/scripts/env.sh doc` · `env.sh audit` — the keys the app reads, and where each lives.
- `.icm/scripts/setup.sh` — the repo, complete and current.
- `.icm/_shared/github.md` · `.icm/_shared/ci.md` — the lane-PR regime; what green means.
- The deal folder, **where the operator's checkout has it on disk** — the one place a lane
  names icm-board, and only as "where the operator's deal folder lives", never as a path a
  script reads.

Context budget: the Inputs table above is the budget (see `.icm/CONTEXT.md` → Layers).

## Process

1. **Usage line first**: `usage-snapshot.sh <slug> handover start` (slug `handover-<date>`).
2. **Accounts, per the ownership pattern.** Read the pattern from `project-rules.md`
   (client-owned or operator-hosted). For each account the build runs on — hosting, database,
   email, domain, error tracker, payments — record in `notes.md` **that it exists and in whose
   name**, never a value, never a credential. A transfer still owed is a line with an owner,
   not something this lane does.
3. **The environment, documented.** For every key the app reads: `env.sh audit` → `RESULT: OK`,
   or `env.sh doc <KEY>` printed into `notes.md` for each gap. Keys and notes and surfaces —
   never values.
4. **The repo, complete.** `setup.sh --report` → `RESULT: OK`. `GAPS` are named in `notes.md`
   with their owner; none is fixed by editing a template-owned file.
5. **The money line — a checklist line, not a call.** Per the deal's shape: "final invoice
   draft to raise in the dashboard" (one-off), or "retainer starts <date> — the dashboard
   row's `billing_type` says monthly" (retainer), or "support line €<n>/month from <date>"
   (one-off + support). The operator raises it; the lane writes the line.
6. **`notes.md`** carries `- handover: <date>` and `- support: none | basic | retainer`
   matching `project.json → support.tier`, then open the lane PR:

   ```bash
   .icm/scripts/new-run.sh <slug> --lane handover --summary "Handover: <what the client now owns and runs>"
   ```

   Draft, `type:handover`, Summary with a `- slug:` line, Steps to test — no checklist. (On a UAT
   repo the merge reaches UAT like every lane and production with the batch's promotion —
   `_shared/promotion.md`; a handover normally follows the last promotion.)
7. **The gate, then settle**: `.icm/scripts/security-check.sh <slug> --branch --audit` →
   `OK` (a handover that ships a known-high dependency or a pasted key is not a handover), the
   cheap tier, `usage-snapshot.sh <slug> handover end` (so the close-out commit carries the
   line), `close-out.sh <slug>` → `CLOSED`, push, `ci-status.sh` → `GREEN`.
8. **The record step — local only.** Where the operator's checkout has the deal folder on
   disk, write `08-handover.md` into the engagement folder there (icm-board,
   `workspaces/deals/<client>/<engagement>/`): the date, the support tier, the accounts table,
   the env keys documented, the money line, the repo's `setup.sh` verdict, the PR link. Where
   it is **not** on disk — a cloud session, a client's own machine — write nothing and carry the
   pointer to the stop report as an `Operator:` item (step 9). Nothing here reads or writes a
   path outside the repo to find it.
9. **STOP.** (The usage `end` line was written before the close-out.) Report per
   `.icm/_shared/output.md` — the transfers still owed and the money line are human acts that
   never land in git, so they are `Operator:` items:

   ```
   **handover <slug> ready** · CI GREEN · <PR link>

   - support <tier> · setup.sh <verdict> · record <at <deal-folder path>/08-handover.md | not written — no deal folder on disk>
   - <any env key or account the audit could not document>

   Operator:
   1. <per transfer still owed> <the account> — <the transfer>, owner <who>
   2. <the money line>
   3. <where the deal folder was not on disk> write 08-handover.md into the deal folder (icm-board workspaces/deals/<client>/<engagement>/) from notes.md
   4. smoke-test, then squash-merge the PR from GitHub
   ```

## Outputs

**Run-scoped, without exception** (`.icm/_shared/stage-preamble.md` → Run-scoped isolation).

`.icm/runs/<slug>/run.md` (`- lane: handover`), `usage.md`, and
`.icm/runs/<slug>/lane/output/notes.md` — archived by step 7:

```md
# Handover: <slug>

- handover: <YYYY-MM-DD>
- support: none | basic | retainer
- ownership: client-owned | operator-hosted (per project-rules.md)
- money: <final invoice draft to raise | retainer starts <date> | support €<n>/month from <date>>

## Accounts

| Account | In whose name | Transferred | Owed |
|---|---|---|---|

## Environment

<`env.sh audit` last line; the `env.sh doc` blocks for any gap — keys, notes, surfaces; no values>

## Repo

<`setup.sh --report` last line; gaps with owners>
```

Plus, where the deal folder is on disk, `08-handover.md` in the engagement folder (icm-board).

## Verify

- Nothing was invoiced, created, transferred or sent by this lane; every such item is a line
  with an owner.
- `notes.md`'s `- support:` equals `project.json → support.tier`; a `basic`/`retainer` tier has
  the fail-safe page and the Sentry key declared (`setup.sh` section 11).
- One PR, `type:handover`, draft, no gate checkboxes; `close-out.sh` `CLOSED` on its head.
- The record went into the deal folder **or** the stop report's `Operator:` list says where it must go — never
  a path outside the repo assumed, never a write outside the repo from a session that could
  not see the folder.
