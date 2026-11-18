# Lane — knowledge

Language: en

## Purpose
Change one page of the project docs to say what is true today: add a page, edit a
part of a page, or remove a wrong page.

## Inputs
- The ticket (`.icm/_system/rules/ticket.md`). It names the verb (`add`, `edit` or
  `remove`), the page and the change.
- `.icm/_system/rules/lane.md` — the flow.
- `.icm/project-rules.md`. It names the docs folder and its format rules. If it names
  none, the docs folder is `docs/`.
- The one page. For `add`, one page next to it, as the example.

## Process
Follow the flow in `rules/lane.md` with the lane name `knowledge`. These points are specific:
1. Find the one page. If the ticket matches no page or two pages, ask the operator
   (`rules/questions.md`). Do not guess a page.
2. Write only what is true today: the product, or the decision in the ticket.
   Write no plan. A decision about the product is a question.
3. `edit`: change only the part that the ticket names. A page that is out of date is an
   `edit`. `remove`: write the reason in `handoff.md`, and remove each link to the page in
   the docs folder. `add`: use the form and the links of the pages next to it.
4. Change only files of the docs folder. A change of code, `.icm/` or CI is a `chore`.
5. Before the push, read the page again: each link goes to a file that exists.
6. In `handoff.md`, write the page and what changed on it.

## Outputs
- The page, pushed, in a ready pull request with CI green.
- `run.md`, `status.md` (`phase: release`) and `handoff.md`.

## Gates
- Ready to merge: the operator ticks it. Release merges. You do not tick it.
