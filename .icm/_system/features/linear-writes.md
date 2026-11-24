# Linear writes — the session makes its own ticket acts in Linear

Language: en

## Purpose

The session makes the Linear acts of its run itself, with the BAXTER Linear tool. A write
needs no yes of the operator. `findings.md` stays the record of each act.

## Inputs

- The entries of `findings.md` of the run.
- The key of the run's ticket. The team key is `JAM`. The org is `kodominio`.

| Kind | The act | The text |
|---|---|---|
| Test site | `add_comment` on the run's ticket | The address of the preview and what to test |
| Question | `add_comment` on the run's ticket | One question that only the business can answer |
| Spike summary | `add_comment` on the run's ticket | The result and the proposed next step |
| Finding or follow-up | `create_issue` in Triage of `JAM`, then `relate_issues` to the run's ticket | A title and the four headings |

No other act. A session does not change a state, a title, a description, a label, an
assignee, a priority or an estimate of a ticket that exists. `icm-linear`, the gate scan of
BAXTER or the operator moves a state. No write to a ticket of another team. No write of a
secret, a token or the text of a client mail.

## Process

1. Write the entry in `findings.md` first, with the exact text.
2. Before the first write of the run, read the team one time:
   `~/baxter_live/system/bin/baxter_tool run linear get_team '{"org":"kodominio","team":"JAM"}'`.
   Use only the names that it gives: the state of Triage and the labels.
3. A comment: `baxter_tool run linear add_comment` with `org`, `key` (the run's ticket) and `body`.
4. A new issue:
   - First `baxter_tool run linear list_issues` with `org`, `team` and `"limit": 200`. Read the
     titles. An open issue that covers the finding is a duplicate: make no issue. Relate it to
     the run's ticket (`relate_issues`, type `related`) and record its key.
   - Else `create_issue` with `org`, `team`, `title`, `state` (the Triage state) and a
     `description` with the four headings: Problem, Proposed changes, Acceptance criteria,
     Outcome. No priority and no estimate: the operator sets them at the triage. Add the
     label `source/baxter` when the team has it.
   - Then `relate_issues` with `key` (the new issue), `type` `related` and `to` (the run's ticket).
   - Write in the language of the run's ticket.
5. After each act, add `- filed: <the link of the comment, the new key, or the key of the
   duplicate>` to the entry.
6. The tool refuses or fails: do not try the act again, and use no other route (no MCP tool,
   no API call). Add `- filed: no, <the error>` to the entry, and name it in the stop report.
7. A question stops the run, as rule 3 of `rules/ticket.md` says. The question stays in the
   stop report.

## Outputs

- The Linear acts of the run: comments on its ticket, and Triage issues related to it.
- The line `filed:` in each entry of `findings.md`.

## Gates

- None for a write. The gates of the pull request stay the operator's.
