<!-- PIPELINE RUN — do not delete the markers; the pipeline reads them. -->

## Summary

<!-- one plain sentence: what a user can now do that they couldn't before -->

## Spec

| Field          | Value                                                                                                    |
| -------------- | -------------------------------------------------------------------------------------------------------- |
| **Slug**       | `<slug>`                                                                                                 |
| **Personas**   | <persona(s)>                                                                                             |
| **Complexity** | trivial \| standard \| complex                                                                           |
| **Full spec**  | spec.md — canonical, read it there: `<link to .icm/runs/<slug>/02_define/output/spec.md on this branch>` |

## Acceptance criteria

<!-- text mirrored from spec.md — edit the spec, not these lines; the PR tracks tick state only -->

_<n> criteria_

- [ ] <criterion 1>
- [ ] <criterion 2>

## Steps to test

1. Wait for Build to flip the PR ready — the affected product-app previews build on the post-flip push (drafts build no previews)
2. Open those previews and <concrete steps to exercise the change>

---

### Gates

<!-- gate:spec-approved -->

- [ ] **Spec approved** — _Define gate: a human ticks this before Build starts._

<!-- gate:ready-to-merge -->

- [ ] **Ready to merge** — _Release gate: a human ticks this to authorise the squash-merge; the tick attests your own preview smoke-test._

---
