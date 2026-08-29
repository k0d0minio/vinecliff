---
title: How the booking site should work
intro: >
  The booking site is built — these answers turn it from a demo into the real thing.
  Most questions are a single tap, and nothing here is set in stone: we can change any
  of it later.
---

## When a guest requests dates, what should happen?

- type: select
- options: I approve every booking before it's confirmed | It confirms automatically if the dates are free | Not sure — recommend something
- key: booking-approval

## How should guests pay for a stay?

- type: select
- options: By card online when they book | A deposit online, the rest in person | I'll handle payment myself to start (invoice, check, cash) | Not sure — recommend something
- key: guest-payment
- hint: Card payments online are handled by Stripe — I set all of that up.

## Who changes the prices on the site?

- type: select
- options: We set them together and they stay put — I ask Jamie for changes | I want to change prices myself from the admin, any time
- key: price-editing

## How far ahead should guests be able to book?

- type: select
- options: Up to 6 months out | Up to a year out | 18 months or more — weddings book far ahead
- key: booking-horizon

## How last-minute is too last-minute?

- type: select
- options: Same-day is fine | At least 2 days ahead | At least a week ahead
- key: booking-cutoff

## Is there a minimum stay?

- type: select
- options: No minimum — one night is fine | 2 nights minimum | 2 nights on weekends only | A week at a time in high season | It varies by building — I'll explain below
- key: minimum-stay

## Anything different per building?

- type: textarea
- optional: yes
- key: minimum-stay-notes
- hint: Only if a rule above works differently for the Farmhouse, Carriage House, Barn or the whole estate.

## How many people can stay overnight in each space?

- type: textarea
- key: guest-caps
- hint: Farmhouse, Carriage House, Barn, whole estate — rough numbers are fine.

## Should weddings and big events be bookable through the site?

- type: select
- options: Yes — people can request event dates online | No — events stay with me by phone and email | Not sure — recommend something
- key: events-online

## When the Barn hosts an event, what happens to the rest of the estate?

- type: select
- options: The whole estate is blocked off for the event | The houses can still be rented separately | It depends on the event — I'll explain below
- key: event-blocking

## What's the biggest event you'd host?

- type: text
- key: event-max-guests
- hint: A rough maximum guest count is enough.

## What are the rules for events?

- type: textarea
- key: event-rules
- hint: Music cut-off, quiet hours, parking — and anything you won't host at all.

## Where should new bookings and enquiries reach you?

- type: select
- options: Email | Text message | Both
- key: booking-alerts

## Anything the site must do that I haven't asked about?

- type: textarea
- optional: yes
- key: features-missing
