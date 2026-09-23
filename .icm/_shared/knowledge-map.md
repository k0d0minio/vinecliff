# Knowledge map — what each stage reads, and where (Layer 3 reference, project-owned)

The router every stage loads to find its slice of this repo's knowledge. Project knowledge — what
the product is, who it serves, how it is built — is canonical in the docs tree named by
`docs_path` in `.icm/project.json` (or, for a repo without one, in `README.md` and the `AGENTS.md`
files); the pipeline never copies it into a contract, it reads it from here on demand. This file is
project-owned: it names this repo's pages, and the sync never touches it. Validate it with
`.icm/scripts/validate-knowledge-map.sh` whenever a page moves.

Paths below are relative to `docs_path`. A page named here must exist; a page that does not exist
here is not part of any stage's context budget.

## Where the knowledge lives

`docs_path` (`.icm/docs`) is empty today; the knowledge is at the root and in the onboarding
forms, so the paths below are repo-relative.

- The site as built — `README.md` (root): the stack, the scripts, how to run it.
  `AGENTS.md` (root): identity, the routing table (where every surface lives), the standing
  rules — real bookings live here, never invent a business fact, scrypt hashes only.
- The business facts and the booking domain logic — in code, routed by `AGENTS.md`'s table
  (the site and settings modules, the booking library and its unit tests).
- The owner's answers — `.icm/onboarding/business-details.md` (rates, seasons, policies) and
  `.icm/onboarding/functionality-features.md` (approval, payment, the booking flow): the
  questionnaires the dashboard serves; the answers are snapshotted by the dashboard, never
  written here by hand.
- The deal — outside this repo, in icm-board under workspaces/deals/vinecliff. No stage reads it.

## What each stage reads

| Stage | Reads | Writes |
| --- | --- | --- |
| **Scope** (incl. the cut) | may read everything, to check requirements are clear, nothing breaks, and the feature fits what exists; prefers `AGENTS.md` first, then the onboarding form the story touches | — (its artifacts are `.icm/runs/<slug>/01_scope/**` + `.icm/intake/<slug>/`) |
| **Define** | `AGENTS.md` for the routing and standing rules; the personas (guest, owner) and business facts from the modules `AGENTS.md` routes to and the onboarding forms | — |
| **Build** | `AGENTS.md` (the code rules `_shared/conventions.md` redirects to) and `README.md` | — |
| **Release** | `README.md` and `AGENTS.md` when a shipped change moves a file or a rule | those pages |
| **Knowledge lane** | exactly the one page the request names | that page; this map when a page is added or removed |
