# Stub: The old onboarding forms and info.txt leave the repo

- feature-slug: drop-legacy-files
- epic: go-live
- sequence: 1 of 9
- depends-on: none
- complexity: low
- priority: P2

## Problem

`.icm/onboarding/business-details.md` and `functionality-features.md` are the questionnaires of the old pipeline. `info.txt` holds the address, the phone and one paragraph of copy. The house kickoff replaced all three on 2026-10-26.

## Proposed change

Delete the three files.

## Acceptance criteria

- [ ] `.icm/onboarding/` and `info.txt` are not in the repo.
- [ ] No file in the repo reads `info.txt` or `.icm/onboarding/`.

## Out of scope

- The answers. They are in the house, `clients/vinecliff/kickoff/`.
