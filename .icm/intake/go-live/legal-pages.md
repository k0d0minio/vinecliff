# Stub: A guest reads the terms and the privacy policy

- feature-slug: legal-pages
- epic: go-live
- sequence: 9 of 9
- depends-on: brand-from-the-logo
- complexity: medium
- priority: P1

## Problem

The site collects guests' names, emails, phones and stay dates, and has no terms and no privacy policy.

## Proposed change

Two pages, `/terms` and `/privacy`, drafted from US defaults for a short-term rental in New York State, linked from the footer and from the booking and enquiry forms. The owner reads and approves them before go-live.

## Acceptance criteria

- [ ] `/terms` says: a request is not a booking until the owner approves it; the deposit and the balance are paid off the site as the owner states; the house rules, the guest cap and the check-in and check-out times are on each space's page; the cancellation policy is the one in the admin settings; New York law applies.
- [ ] `/privacy` says: what the site collects (name, email, phone, dates, party size, messages), why, who processes it (Vercel, Neon, Resend, Sentry), how long it stays, how a guest asks to see or delete it, and the contact address.
- [ ] The site sets no tracking cookie, so it shows no cookie banner. `/privacy` says which cookies exist (the admin session only).
- [ ] The footer links both pages. The booking and enquiry forms say "By sending this request you accept the terms" with a link.
- [ ] Each page shows its last-updated date.

## Out of scope

- Legal advice. The owner reads the texts and may give them to a lawyer.

## Notes

"American defaults": Jamie, 2026-10-26. The business's legal name is open (breakdown, question 3 for the owner).
