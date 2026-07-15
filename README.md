# Vine Cliff

Website and booking platform for **Vine Cliff Vineyards** — an elegant
170-year-old country estate on the shores of Lake Erie in Brocton, NY,
offering weekly, weekend and event rentals across a farmhouse, carriage house
and barn (or the whole estate at once).

Guests browse each space, check live availability and **request to book**
online; the owner reviews, approves and runs the whole estate from `/admin`.

## Stack

- [Next.js 15](https://nextjs.org/) (App Router) + React 19
- TypeScript
- [Tailwind CSS v4](https://tailwindcss.com/)
- [Framer Motion](https://www.framer.com/motion/) for scroll & entrance animations
- shadcn-style UI primitives (Button) with `class-variance-authority`
- Self-hosted variable fonts (Fraunces + Inter) via `next/font/local`
- [Drizzle ORM](https://orm.drizzle.team/) on [Neon](https://neon.tech/) Postgres

## Getting started

```bash
npm install
cp .env.example .env.local   # then fill in DATABASE_URL and AUTH_SECRET
npm run dev
```

Open [http://localhost:3000](http://localhost:3000).

## Scripts

- `npm run dev` — start the dev server
- `npm run build` — production build
- `npm run start` — serve the production build
- `npm run lint` — lint
- `npm test` — unit tests for the booking domain logic (dates, pricing, availability)
- `npm run db:generate` — generate SQL migrations from `lib/db/schema.ts`
- `npm run db:migrate` — apply pending migrations to `DATABASE_URL`
- `npm run db:studio` — open Drizzle Studio against the database

## The booking platform

**Models** (`lib/db/schema.ts`): `spaces` (content, rates, rules — the source
of truth for the public site), `guests` (deduplicated by email; doubles as a
CRM), `bookings` (request-to-book with statuses `pending → approved/declined`,
plus `cancelled`), `blackouts` (owner-blocked dates; spaces are open by
default), `enquiries`, and `settings` (notification email, cancellation
policy).

**How booking works**

1. Each space has a public page at `/spaces/<slug>` with a live availability
   calendar and a booking form. Guests pick dates, see an auto-computed
   estimate (nightly/weekly rates + cleaning fee) and submit a request —
   nothing is charged online.
2. Requests arrive as `pending`; only **approved** bookings block the
   calendar. The owner approves (optionally adjusting the final price and
   deposit), declines, or cancels from `/admin/bookings`; guests are emailed
   at every step and get a private status page (`/bookings/<token>`) where
   they can withdraw a pending request or ask to cancel a confirmed one.
3. Availability rules are per-space and editable in the admin: minimum stay,
   turnover buffer days between bookings, minimum lead time, booking horizon,
   and party-size caps. The barn and the whole-estate package **reserve the
   entire property**: their bookings block every space, and they're only
   available when everything is free (overridable per booking at approval).
4. Payments are tracked manually for now (quoted vs final total, deposit,
   unpaid/deposit-paid/paid/refunded) — the schema is ready for Stripe later.

**Admin** (`/admin`): dashboard with live stats, booking pipeline with search
and tabs, manual bookings for phone requests, a month calendar across all
spaces with blackout management, a guests CRM with notes and history, a
spaces editor (copy, photos, rates, rules), an enquiries inbox with one-click
convert-to-booking, and settings.

**Email** (`lib/email.ts`): transactional email via Resend's HTTP API. With
no `RESEND_API_KEY` set, sends become logged no-ops — the site works fine
without email. Set `RESEND_FROM` to a verified sender for production.

**iCal feeds**: every space has a private feed at `/api/ical/<token>` (URL
shown in the space editor) — subscribe from Google Calendar or paste into
Airbnb/VRBO so external listings block dates booked here.

## Structure

```
app/
  components/     Nav, Footer, motion primitives, UI primitives, in-view hook
  sections/       Hero, Estate, Spaces, Gallery, Location, Booking CTA
  spaces/[slug]/  Space detail pages: availability calendar + booking form
  bookings/[token]/ Guest booking status page (private tokenized link)
  enquire/        General enquiry form
  api/ical/[token]/ Private iCal availability feed per space
  admin/          Account-gated admin: dashboard, bookings, calendar,
                  guests, spaces editor, enquiries, gallery, settings
  fonts/          Self-hosted variable fonts
  layout.tsx      Metadata, SEO, JSON-LD, fonts
  page.tsx        Landing page composition
lib/
  site.ts         Business info + static space fallback, gallery & nearby data
  spaces.ts       Space display shapes for the public site
  admin.ts        Admin navigation config
  booking/        Domain logic: dates, pricing, availability, tokens
  email.ts        Resend transactional email + templates
  settings.ts     Estate-wide settings (notification email, policy)
  db/             Drizzle schema (schema.ts), client (index.ts), queries
  auth/           Password hashing, session tokens, admin action guard
  utils.ts        cn() helper
tests/            Unit tests for the booking domain (node:test via tsx)
scripts/
  migrate.ts      Applies pending migrations (used by CI and `db:migrate`)
drizzle/          Generated SQL migrations + seeds
middleware.ts     Protects /admin routes behind the login cookie
public/img/       Estate photography
```

## Database (Drizzle + Neon)

The schema lives in `lib/db/schema.ts`. After changing it, generate a migration
and commit the result:

```bash
npm run db:generate
```

Migrations are applied by `scripts/migrate.ts` (Neon's HTTP driver), which runs
locally via `npm run db:migrate` and automatically in CI — see below.

### Automatic migrations on merge to main

`.github/workflows/db-migrate.yml` runs `npm run db:migrate` against production
every time changes land on `main` (i.e. when a PR merges). It requires one
repository secret:

- `DATABASE_URL` — the Neon connection string (same value Vercel uses for
  production).

Add it under **Settings → Secrets and variables → Actions**. The job is
idempotent (Drizzle skips already-applied migrations) and serialised so two
runs never touch the database at once. Preview deployments do **not** run
migrations; they read whatever schema production is currently on.

## Admin section

A private, mobile-responsive admin area lives at `/admin`. It's the foundation
for managing bookings, enquiries and site content — the pages are scaffolded
now and will be wired to real data later.

Access is tied to individual accounts, each signing in with their own **email
and password**. Accounts live in the `users` table; passwords are stored only
as scrypt hashes. Two environment variables are required:

- `DATABASE_URL` — Neon Postgres connection string (provisioned by the Vercel +
  Neon integration).
- `AUTH_SECRET` — a long random string used to sign session cookies. Generate
  one with:

  ```bash
  node -e "console.log(require('node:crypto').randomBytes(32).toString('base64url'))"
  ```

Set both in `.env.local` for development and in the Vercel project's
environment variables for production. Every `/admin` route is protected by
`middleware.ts`, which validates a signed, httpOnly session cookie on the Edge
without hitting the database; visitors are redirected to `/admin/login` until
they sign in.

The initial admin account (`wpcarlson@gmail.com`) is created by the
`0001_seed_admin_user` migration, so it exists as soon as migrations have run.

## Design notes

- **Mobile-first** throughout, with a full-screen mobile nav.
- Warm heritage-estate palette (pine green, cream, sunset amber, lake teal).
- Subtle, tasteful motion: parallax hero, word-by-word headline reveal,
  staggered scroll reveals, image hover zoom. Respects `prefers-reduced-motion`.
- SEO: Open Graph, Twitter cards, and `LodgingBusiness` structured data.
