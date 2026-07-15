# Vine Cliff

Marketing landing page for **Vine Cliff Vineyards** — an elegant 170-year-old
country estate on the shores of Lake Erie in Brocton, NY, offering weekly,
weekend and event rentals across a farmhouse, carriage house and barn.

This is the foundation for a future booking platform.

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
- `npm run db:generate` — generate SQL migrations from `lib/db/schema.ts`
- `npm run db:migrate` — apply pending migrations to `DATABASE_URL`
- `npm run db:studio` — open Drizzle Studio against the database

## Structure

```
app/
  components/     Nav, Footer, motion primitives, UI, in-view hook
  sections/       Hero, Estate, Spaces, Gallery, Location, Booking CTA
  admin/          Password-gated admin section (login + dashboard shell)
  fonts/          Self-hosted variable fonts
  layout.tsx      Metadata, SEO, JSON-LD, fonts
  page.tsx        Landing page composition
lib/
  site.ts         Business info, spaces, gallery & nearby data
  admin.ts        Admin navigation config
  db/             Drizzle schema (schema.ts) and client (index.ts)
  auth/           Password hashing (password.ts) & session tokens (session.ts)
  utils.ts        cn() helper
scripts/
  migrate.ts      Applies pending migrations (used by CI and `db:migrate`)
drizzle/          Generated SQL migrations + seed
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
