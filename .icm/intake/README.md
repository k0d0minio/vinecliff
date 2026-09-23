# Intake — the work, as epics and stubs

> This folder follows the estate-wide intake standard (canonical spec:
> `_system/contracts/TICKETS.md` in the icm-board estate). Tickets are **stubs** that
> never live alone: related work is an **epic** — `intake/<epic-slug>/` with a
> `breakdown.md` (what was understood + the build order) and one stub per unit of work,
> each `- sequence: <n> of <m>` with `- depends-on:` naming any in-epic prerequisite —
> and one-off findings are **triage** stubs in `intake/triage/` tagged
> `- lane: bug | tweak | chore`. Identity is the path (`<epic>/<slug>`, feature-slug
> matching the filename); there are no ticket numbers.
>
> **Status is positional.** Open = the stub is here; done = `git mv` into the epic's
> `_done/` (dropped work too, with a `> Dropped: <reason, date>` line — nothing is
> deleted). A completed epic moves whole into `intake/_done/`. Priority is an optional
> `- priority: P0|P1|P2` line; external blockage an optional `- blocked: <reason>` line.
> Each stub's `## Prompt` must stand alone pasted into a fresh agent session at the
> repo root — it is the brief Define reads. The admin dashboard's Tickets board reads
> this folder from `main` and sends the pick-up verb (`/pipeline new <epic>/<slug>`, or
> the lane verb for a triage stub) where this repo carries the `/pipeline` router, the
> `## Prompt` body where it does not.

Any plan, backlog, or task list for this repo becomes stubs here — never a loose
`TODO.md` or `BACKLOG.md` at the root.
