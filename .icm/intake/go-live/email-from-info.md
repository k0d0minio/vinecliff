# Stub: Every email comes from info@vinecliffvineyard.com

- feature-slug: email-from-info
- epic: go-live
- sequence: 7 of 9
- depends-on: site-on-the-domain
- complexity: low
- priority: P1

## Problem

The booking emails send from `onboarding@resend.dev`, which reaches only the Resend account owner. The owner wants every email to come from the business, not from his personal Gmail (demo call, 2026-10-22).

## Proposed change

The site sends every email from "Vine Cliff Vineyard <info@vinecliffvineyard.com>". A guest's reply reaches the owner.

## Acceptance criteria

- [ ] `RESEND_FROM` is "Vine Cliff Vineyard <info@vinecliffvineyard.com>" in Production and UAT. `.env.example` says so.
- [ ] Every email sets `Reply-To` to the notification address in the admin settings.
- [ ] The guest emails and the owner alerts name the site by its domain.
- [ ] A booking request on UAT sends the guest's email and the owner's alert, and both arrive.

## Out of scope

- A mailbox on the domain. The owner keeps his Gmail (breakdown, question 4 for the owner).

## Notes

Jamie's acts: verify `vinecliffvineyard.com` in Resend (the SPF, DKIM and return-path records at GoDaddy), and set the forward of `info@` to the owner's Gmail at GoDaddy.
