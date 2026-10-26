# Stub: Jamie hears about an error before the owner does

- feature-slug: error-tracking
- epic: go-live
- sequence: 8 of 9
- depends-on: none
- complexity: low
- priority: P1

## Problem

Nothing tracks errors. A failed booking request is silent. A guest who hits an error sees the default error page.

## Proposed change

Basic Sentry on the server: every unhandled error in a route, a server action or the iCal feed reaches Sentry. A guest who hits an error sees a calm page with the owner's phone number and email.

## Acceptance criteria

- [ ] `@sentry/nextjs` reports server errors in Production and UAT, never in a preview or locally. The environment is tagged.
- [ ] `SENTRY_DSN` is in `.env.example` with its environments. No DSN or token is in git.
- [ ] No guest's email, phone or name is sent to Sentry (`sendDefaultPii: false`, and the request body is not attached).
- [ ] `app/error.tsx` and `app/global-error.tsx` show a calm page in the brand, with the phone and the email from `lib/site.ts`.
- [ ] A test error thrown on UAT appears in Sentry.

## Out of scope

- Browser error tracking, performance tracing and session replay.

## Notes

The Sentry organization is open (breakdown, question 2 for Jamie). Jamie creates the project and sets `SENTRY_DSN`.
