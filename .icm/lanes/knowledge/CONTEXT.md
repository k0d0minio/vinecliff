# Lane — Knowledge (contract)

Invoked via `/pipeline knowledge add|edit|remove "<what>"` — or the bare form without the prefix.
The **one sanctioned way to change project knowledge outside a Release**: the pages of the docs
tree (`docs_path` in `.icm/project.json`) are the source of truth every stage loads through
`.icm/_shared/knowledge-map.md`, and Release keeps them current for shipped changes. Everything
else — a stale slice a stage noticed, a quarter's OKR page that does not exist yet, a runbook that
moved, a persona description that no longer matches what the product does — comes through here.
No scope, no spec, no run folder, no gate checkbox: **one invocation, one docs-only PR** that the
operator merges from GitHub. Nothing is left for a second invocation.

Not for: a doc change that belongs to a code change in flight (Release's docs step owns that, in
the feature PR); a page outside the docs tree the map routes (the changelog is the Announcing
rule's — `_shared/project-rules.md` — and the archive is `close-out.sh`'s); code, the repo's
code rules, an `AGENTS.md`, or a pipeline contract (those are `chore`). A request that turns out
to need a product decision — "what _should_ the roles page say?" — is not knowledge maintenance;
route it to `scope`.

## Inputs (read only these)

- The verb and the request: `add` (a page that does not exist), `edit` (a page that does),
  `remove` (a page that should not), and `"<what>"` — which page, and what changes.
- `.icm/_shared/knowledge-map.md` — the router. It names every routed page; the request resolves
  to exactly one of them (or, for `add`, to the section it belongs in).
- The one `<docs_path>/<section>/<page>` the request names — after routing, never before; for
  `add`, the sibling page you will match the shape of.
- The repo's docs skill, where it ships one (`_shared/project-rules.md` → Capability skills) —
  the format rules, the copy register per section, and the verify-by-reading checklist; where it
  ships none, the docs tree's own format rules. This lane writes the page under those rules.
- `.icm/_shared/github.md` — the PR-events rule (no PR is ever subscribed) and the GitHub MCP
  calls.

Context budget: the Inputs table above is the budget (see `.icm/CONTEXT.md` → Layers). Do not
open the rest of the docs tree "for consistency"; the map plus one page is the whole read.

## Process

1. **Route.** Find the page in the map. Say which path you resolved and why in one line. `add`
   with no obvious section, or `edit`/`remove` that matches two pages or none → `AskUserQuestion`;
   never guess a page. `remove` also needs the reason the page is wrong, not just unwanted — if
   the request is "it's out of date", that is an `edit`.
2. **Branch.** From `origin/main`: `git checkout -b knowledge/<slug>` (a short kebab-case name
   for the change — `okrs-2026-q3`, `roles-escalations`). Never on a run's branch: a
   knowledge PR carries no code, and a run's PR carries no unrelated docs.
3. **Change the page** under the repo's docs skill where it ships one (its format rules and copy
   register), otherwise under the docs tree's own format rules. The page reflects **what is true
   today** — the repo, the product, the team's decision as the request states it. Nothing
   planned, nothing invented.
   - `add` — the page at `<docs_path>/<section>/<page>`, shaped like its siblings (frontmatter
     only where they have it, a nav/meta entry only where the folder already keeps one); link it
     from the section's index page where the siblings are linked.
   - `edit` — only the part the request names. Do not rewrite the page.
   - `remove` — delete the page and its folder (where nav is folder-derived), its nav/meta entry
     where the folder keeps one, and every internal link to it
     (`grep -rn '/<section>/<page>' <docs_path>`).
4. **Update the map when the routing changed** — a page added or removed is added to or dropped
   from `.icm/_shared/knowledge-map.md` (the section list and, if a stage should read it, the
   stage table). An `edit` leaves the map alone unless the request itself is about the map (a
   stale pointer, a wrong description). Then prove it:

   ```bash
   .icm/scripts/validate-knowledge-map.sh   # → RESULT: OK (not a repo check; reads the tree only)
   ```

   `RESULT: STALE` lists the dead paths — fix the map, re-run. Read the `notice:` lines too: a
   page you added must appear as routed or as a deliberate exclusion, not as unrouted.

5. **Verify by reading** — the docs skill's checklist where the repo ships one, as written:
   frontmatter shape, no line-range fences, every internal link resolves (`ls`, not memory), the
   nav/meta entries untouched outside the folders that keep one. There is no docs preview on a
   working branch; the read-through is the whole pre-merge gate, and the merge build on `main`
   is the proof.
6. **One commit, one PR.** Commit (`docs(knowledge): <verb> <page> — <one line>`), push
   `knowledge/<slug>`, and open the PR with `create_pull_request` (the repo's owner/repo —
   derived from `origin`; `GITHUB_REPO` overrides — `base: "main"`, `draft: false` — a docs-only
   diff builds no preview, so there is nothing a draft would hide). Body:

   ```md
   ## Summary

   <verb> `<section>/<page>` — <what changed and why, two sentences at most>

   ## Pages

   - `<docs_path>/<section>/<page>` — <added | edited: which part | removed>
   - `.icm/_shared/knowledge-map.md` — <routing updated | unchanged>

   ## Check

   <the last line of validate-knowledge-map.sh, and any notice: lines>
   ```

   No `- slug:` line, no gate checkboxes, no labels, no `usage.md` — this is not a run (the
   usage line lives in a run folder, and this lane has none). Do not call
   `subscribe_pr_activity` (`_shared/github.md` → PR events). Read CI once,
   `.icm/scripts/ci-status.sh --pr <number>` → `GREEN` (a markdown-only diff settles in about a
   minute; a CI knowledge-map step, where the repo runs one, is advisory and cannot red it), fix
   and push on `RED`, then **stop** and hand the PR URL to the operator. The merge is theirs,
   from GitHub. **On a UAT repo** the page reaches UAT on the merge and production with the
   next promotion (`_shared/promotion.md`); nothing else is owed.

## Outputs

- One or two files changed: the page (and its nav/meta entry / index link where the folder has
  them), plus the map when a page was added or removed.
- One open, ready PR on `knowledge/<slug>` with the body above. No run, no archive, no changelog
  page: knowledge maintenance is not a shipped change and is never announced.

## Verify (before handing off)

- The request resolved to exactly one page through the map, and only that page changed.
- `validate-knowledge-map.sh` → `RESULT: OK`, and the added page (if any) is routed.
- The read-through (the docs skill's checklist where the repo ships one) done twice: links
  resolve, no invented frontmatter, no line-range fence, the copy register matches the section.
- The diff is docs-only: the one page under the docs tree (`docs_path` in `.icm/project.json`)
  and `.icm/_shared/knowledge-map.md` — nothing else. Anything else in the diff means this was
  not a `knowledge` change.
- You stopped after the PR was green — you did not merge, subscribe, or open a second PR.
