# Output doctrine — what a session says in chat (Layer 3 reference, D40)

**This governs the chat, and only the chat.** The PR body, the spec, `notes.md`, a stub,
`handoff.md`, a stage's record — every file is as full as its own contract asks, and is never
trimmed to match the chat or moved into it. Every **gate checkbox lives in the PR body**, where
the operator can tick it; the chat names the gate and links the PR, and never reproduces the box.

The chat is the one surface the operator reads with their own eyes; an agent or a cloud session
picking up later reads files, never chat. So anything a later session needs is written to a file
(`handoff.md`, `status.md`, `notes.md`, the PR body) — never only said. The aim is **valuable
information in as restrained a format as possible**: easy to parse at a glance, not empty.
What follows governs every stage, every lane and the canonical skills alike.

## While working

A short line at each phase change — `CI red on lint — fixing`, `spec approved — starting Build`
— and a line whenever something happens the operator would want to know before the stop: a
decision taken, a surprise, a finding parked, a STOP. No narration of tool calls, and no pasting a
file, a diff or a command's output: name the file or link it instead.

## At a stop

One shape, everywhere — a stage, a lane, a skill:

```
**<stage/lane> <outcome>** · CI <verdict> · <PR link>

- <what matters from this pass — 2 to 5 short bullets>

Operator:
1. <a human-only act, with where to do it>

Unverified: <skipped, unproven, assumed>   ← only when non-empty
```

- **The bullets** are what a human needs to steer: a decision taken, anything that differs from
  the plan, a surprise, what was parked and why, what the next pass should know. Not a file list
  and not a replay of the diff — the PR body carries the full account. Leave them out when the
  outcome line says it all.
- **`Operator:`** is a numbered list, not `- [ ]` boxes — nothing can be ticked in a chat. A gate
  is named with its PR link (`tick **Spec approved** on <PR link>`); the box is in the PR body.
  Omit the heading when there is nothing to do.

## Split by actor

Two lists, never one fact in both:

- **`handoff.md`** — what the next session, human or agent, needs: the next action, blockers,
  what not to touch. Rewritten at every stop, per `_shared/run-pack/handoff.md`.
- **`Operator:`** — human-only acts that never land in git: tick a gate, merge a PR, a Vercel
  dashboard or environment change, rotate a leaked secret, a DNS record. Plain words, not estate
  shorthand — the item must be actionable from the line alone (where to click, what to set); no
  decision number without what it means.

The one exception: an operator act that **blocks the run** is also a `handoff.md` → Blockers
line (`blocked on operator: <act>`) — a chat-only list dies with the session, and naming who
unblocks it is already that section's job.

## Never trimmed

Brevity never outranks reporting outcomes faithfully. Always said in full:

- a STOP and its reason
- a red check
- anything skipped, assumed or left unverified
- a plaintext credential found

## What this does not cover

Files — see the top: this doctrine never shortens a PR body, a spec, a record or a stub.
icm-board's own commands (`/client`, `/project`, `/day`, `/icm-check`) and the global
`~/.claude/CLAUDE.md` sit outside it — it governs the pipeline (stages, lanes, `/pipeline`,
`/setup`) and the canonical `.claude` skills (`pr-conventions`, `ticket-craft`) synced into every
estate repo. No Claude Code output style, no Stop-hook lint: harness-neutral (Claude Code and
OpenCode read the same stage contracts), and a mechanical gate on prose is brittle where a
sentence is the honest answer.
