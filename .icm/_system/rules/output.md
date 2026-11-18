# What a session says in chat

These rules are for the chat only. A file is as full as its own contract asks.

## While you work
Write one short line at each change of phase, and one line when something happens that
the operator must know before the stop: a decision, a surprise, a finding, a STOP. Do not
narrate tool calls. Do not paste a file, a diff or command output. Name the file.

## At a stop
Use this shape:

```
**<stage or lane> <ticket> <outcome>** · CI <GREEN | RED | PENDING | not read> · <pull request link>

- <2 to 5 short bullets: what the operator needs to steer>

Operator:
1. <an act that only a person can do, and where to do it>

Unverified: <what was skipped, assumed or not proven>
```

- **The bullets:** a decision, a difference from the spec, a surprise, a finding. Not a
  list of files. Omit the bullets when the first line says it all.
- **`Operator:`** is a numbered list. Name a gate with its pull request link: "tick **Spec
  approved** on <link>". Omit the heading when there is nothing to do.
- **`Unverified:`** only when there is something to say.

An act of the operator that blocks the run also goes in `handoff.md`, under Blockers.

## Always said in full
- A STOP and its reason.
- A red check.
- Each thing that was skipped, assumed or not verified.
- A plaintext credential that you found.

Do not shorten these to keep the report small.
