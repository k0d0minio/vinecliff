# Feature — Client requests

Language: en

A client request is what the client asked, in the client's words, with acceptance
criteria that a test can check. The request is the client's. A convention never replaces it.

## The store
One triage ticket in the Linear team `requests.linear_team` of `.icm/project.json` (and the
project `requests.linear_project` when it has a value), with the label
`requests.linear_label`. The key of the ticket is the id of the request. The description
has the field lines `- <field>: <value>` and the sections of
`.icm/_system/templates/request.md`. The request button makes the ticket, with the
capture and the screenshot as uploads.

## The record
- Fields: `id`, `source` (`button`, `mail`, `meeting` or `call`), `date`, `page_url`,
  `status`, `linear` (a key, optional), `conflicts` (the name of a convention, optional).
- `## Client words`: from the button, the text as the client typed it, as a quote. Do not
  change it. From a mail, a meeting or a call: a paraphrase. Never copy the text of a
  client mail.
- `## Acceptance criteria`: lines of one form only, with no other text:
  `AC-<n>: WHEN <trigger> [WHILE <state>] THE <page or element> SHALL <observable result>`.
  `WHEN`, `WHILE`, `THE` and `SHALL` are upper case. One line is one result that a test
  can see. The button writes `AC-1` from the form. At `specified`, make each line exact.
- The check: `.icm/_system/scripts/check-request.sh <file>`. For a Linear request, give
  the description on stdin: `baxter_tool run linear get_issue ... | jq -r .result.description | check-request.sh -`. Obey each `fault:` line.

## One request, no second confirmation
One client ask is one request. Do not ask the client to confirm each ticket again. When a
gap changes what gets built, write the question for the client in
`.icm/runs/<id>/client-mail.md`: a draft mail in plain words, with your default for each
question. The operator sends it. A session never sends a mail.

## Conventions and client requests
A convention is a design deck, a default of the blueprint, a default of a UI library, or
a habit of the code. When a convention and a request do not agree:
1. Do not change the request. Do not apply the convention in its place.
2. Write the name of the convention in `conflicts:` of the request.
3. Ask the operator one question (`.icm/_system/rules/questions.md`): the request, the
   convention, and your default. The default keeps the request.

The request applies until the operator answers.

## Specs and tickets
- Each spec has the line `- requests:` with the ids of its requests, or `none` when no
  client asked for the work.
- The spec keeps each AC line of each request as it is, with the id in front:
  `- [ ] <id>#AC-<n>: WHEN ... (verify: agent)`. Add other criteria below them. To change an
  AC line, change the request first, with the operator's yes.
- A stub or a ticket of client work names its requests in the same way.
- `validate-spec.sh` refuses a spec that drops or changes an AC line of a request file.
- A checktest step names what it covers: `covers: [<id>]` or `covers: [<id>#AC-<n>]`.

## The status
| Status | Who sets it | When |
|---|---|---|
| `received` | The button, or the session that writes the record | The record exists |
| `specified` | Define | The spec cites the request, and the AC lines are exact |
| `built` | Build | The pull request of the run is ready |
| `verified` | Release, before `release.sh` | The newest checktest run shows `passed` for each AC of the request |
| `accepted` | The operator only | The client said yes: `accepted` with the operator's words and the date in the record |

A session never sets `accepted`. The checktest engine writes evidence only. It sets no
status.
Change the field line `- status:` of the description with the BAXTER Linear tool when
`linear.writes` permits a write. Else put the change in `findings.md`.

## The request button
One component and one API route, in `.icm/_system/request-button/`. A repo adds them as
`.icm/setup/request-button.md` says. The capture shape `baxter.capture/1` is in
`.icm/_system/request-button/CAPTURE.md`. The button shows on a local dev server and on
UAT. Production needs the operator's choice.
