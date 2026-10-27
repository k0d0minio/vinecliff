# Stub: A guest books one side of the farmhouse

- feature-slug: farmhouse-two-units
- epic: go-live
- sequence: 3 of 9
- depends-on: none
- complexity: medium
- priority: P1

## Problem

The farmhouse is two separate rental units. The site and the admin show it as one space, `farmhouse`. The owner asked for the split on the demo call of 2026-10-22.

## Proposed change

The space `farmhouse` becomes two spaces, one per unit, with their own page, calendar, rates, rules and guest cap. The carriage house, the barn and the whole estate stay as they are. A booking of the whole estate, or of a space that blocks the estate, blocks both units.

## Acceptance criteria

- [ ] The spaces list on the home page and in the admin shows the two units in place of "The Farmhouse". The carriage house, the barn and the whole estate follow.
- [ ] Each unit has a page at `/spaces/<slug>` with its own calendar and booking form.
- [ ] A Drizzle migration creates the two units and moves each booking, blackout and enquiry of `farmhouse` to a unit, by the rule in Notes. The old slug redirects to the first unit's page.
- [ ] An approved booking of the whole estate or the barn blocks both units. A booking of one unit blocks only that unit and the whole estate.
- [ ] The admin's spaces editor edits each unit on its own.
- [ ] The unit tests for availability cover the two units.

## Out of scope

- The units' rates, guest caps and copy. The owner enters them in the admin.
- The photos of each unit.

## Notes

The owner's names are open (breakdown, question 1 for the owner). Until he answers, use "Farmhouse, Side One" (`farmhouse-side-one`) and "Farmhouse, Side Two" (`farmhouse-side-two`). The owner can rename each unit in the admin. The migration rule for existing rows is a default, and the spec step confirms it with Jamie: a blackout of `farmhouse` becomes one blackout per unit, a booking of `farmhouse` goes to side one and blocks both units, and an enquiry goes to side one. Production holds real bookings: the migration runs on UAT first, never by hand on production.
