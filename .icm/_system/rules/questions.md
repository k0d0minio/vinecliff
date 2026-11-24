# Questions

A stage asks the operator a question only when the answer changes what gets built. The
questions of a run are in the body of its pull request. The operator answers them on the
BAXTER HUD, in a form, or in the pull request on GitHub. Do not ask them in the chat. If
the operator answers in the chat anyway, step 4 of the flow writes that answer.

## The format
One entry for each question. Eight questions at most in one run.

```
### Q1. <the question, one sentence>
- type: single | multi | text
- options: <option> | <option> | <option>
- default: <what you will do if the operator gives no answer>
- answer: _waiting_
```

- `single`: one option. `multi`: some options. `text`: a written answer, with no
  `options`.
- Two to six options, each a short phrase with no `|`.
- Plain words, for a person who does not read the code. The question says what changes
  for each option: what the user sees, or what the build does. No file names, no code.
- The operator can add a line `- note:` to an answer.
- When the operator sends the form and leaves a question empty, that question takes its
  default. The note then says "the default, not chosen".

## Where the questions are
| Time | Place |
|---|---|
| The Ticket stage writes a stub | The section `## Questions` of the stub |
| Before `new-run.sh` | `.icm/runs/<id>/questions.md`: the entries only |
| After `new-run.sh` | The pull request body, between `<!-- questions:start -->` and `<!-- questions:end -->` |

After `new-run.sh`, the pull request body is the one home of the answers.
`new-run.sh --refresh-body` keeps the block.

## The flow
1. Write the entries in `.icm/runs/<id>/questions.md` before `new-run.sh`. Take the
   entries of the stub's section Questions first.
2. `new-run.sh` shows the question dialog on the HUD when a question waits. To show it
   again: `~/baxter_live/system/bin/baxter_gate.py questions <number>`, if that file exists.
3. Set `status.md` to `blocked: yes — waits for answers`. Stop. The operator's act:
   answer on the HUD card, then say the command of the stage again.
4. When the run continues: `.icm/_system/scripts/questions.sh <ticket>`. It copies the
   block from the pull request body to `questions.md` and prints it.
   - `RESULT: OK`: all questions have an answer. Use the answers. Continue.
   - `RESULT: WAITING`: stop again. Do not use a default while a question waits.
   - The operator answered in the chat, in plain words: write each answer with
     `questions.sh <ticket> --answer Q1 "<the operator's words>"`. For single and multi,
     give the option that the operator named. Never edit the body with `gh api`, and never
     run `baxter_gate.py answer`: the dashboard runs it.
5. An answer is the operator's decision. Record it in the spec or in `handoff.md`.
