# Tasks: <slug>

The queue, with a definition of done per item. Ticked by the stage that finishes the item —
a human checkbox, never a script's. The definition of done is seeded from the spec's
acceptance criteria when the run is opened; the queue is Build's own, one line per commit-sized
step, so a resuming session can pick up the first unticked line.

## Definition of done

- [ ] <criterion — observable, testable; mirrors the spec's Acceptance criteria>

## Queue

- [ ] <task — small enough for one commit; name the file or area>
