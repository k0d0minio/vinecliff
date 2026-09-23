# Plan: <slug>

Build's execution plan in passes — each pass one layer of the change, in the order it lands, so
a session that resumes mid-build sees where it is. Written by the advisor pass (Define, or
Build's first act on `sonnet` after reading the spec), executed pass by pass, and rewritten when
reality disagrees with it — never left describing a plan that was abandoned.

## Passes

1. **<pass 1 — the layer, e.g. the schema and its migration>** — <files or areas> — done when:
   <one observable>
2. **<pass 2 — the next layer>** — … — done when: …

## Risks

- <what could go wrong, and the signal that it did>
