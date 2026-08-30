# AGENTS.md — Layer 0: Repository Identity & Routing

> This is the **first file any agent session reads.** It says what this repo is and where
> to go for a given task. Keep it short; detail lives in `README.md` and the routed files.

## What this repo is

**vinecliff** — the website **and booking platform** for **Vine Cliff Vineyards**, a
170-year-old country estate on the shores of Lake Erie in **Brocton, NY**. It rents a
farmhouse, a carriage house and a barn — weekly, weekend, for events, or the whole estate
at once.

Guests browse each space, check live availability and **request to book**; the owner
reviews, approves and runs the estate from `/admin`. So this is not a brochure site — it
holds real bookings for a real business, and a bug here costs a letting.

Next.js 15 (App Router) + React 19 · TypeScript · Tailwind CSS v4 · Framer Motion ·
shadcn-style primitives with `class-variance-authority` · self-hosted Fraunces + Inter ·
**Drizzle ORM on Neon Postgres**. Deployed on Vercel; `db-migrate.yml` runs migrations.

**Auth:** individual accounts in the `users` table, passwords stored only as scrypt
hashes — the plaintext is never in the repo or the database. `middleware.ts` validates a
signed httpOnly session cookie on the Edge for every `/admin` route without touching the
database. Requires `DATABASE_URL` and `AUTH_SECRET`. The `0001_seed_admin_user` migration
creates the owner's account, so it exists as soon as migrations have run.

## Routing — "if the task is… → go to…"

| The task | Go to |
|---|---|
| Home page, layout, metadata | [`app/page.tsx`](app/page.tsx) · [`app/layout.tsx`](app/layout.tsx) |
| Page sections and shared components | [`app/sections/`](app/sections/) · [`app/components/`](app/components/) |
| The guest-facing spaces | [`app/spaces/`](app/spaces/) + [`lib/spaces.ts`](lib/spaces.ts) + [`lib/space-images.ts`](lib/space-images.ts) |
| Enquiry and booking flow | [`app/enquire/`](app/enquire/) · [`app/bookings/`](app/bookings/) · [`lib/booking/`](lib/booking/) |
| Admin surface and its data | [`app/admin/`](app/admin/) + [`lib/admin.ts`](lib/admin.ts) + [`lib/auth/`](lib/auth/) + [`middleware.ts`](middleware.ts) |
| API routes | [`app/api/`](app/api/) |
| Booking history and audit | [`app/history/`](app/history/) + [`lib/history.ts`](lib/history.ts) |
| Schema, queries, migrations | [`lib/db/`](lib/db/) + [`drizzle/`](drizzle/) + [`drizzle.config.ts`](drizzle.config.ts) |
| Business facts — the estate, contact, settings | [`lib/site.ts`](lib/site.ts) · [`lib/settings.ts`](lib/settings.ts) |
| Transactional email | [`lib/email.ts`](lib/email.ts) |
| SEO, Open Graph, `LodgingBusiness` structured data | the `opengraph-image.*` / `twitter-image.*` files in `app/` + `lib/site.ts` |
| Fonts and theme | [`app/fonts/`](app/fonts/) · [`app/globals.css`](app/globals.css) |
| Migrations and demo data | [`scripts/migrate.ts`](scripts/migrate.ts) · [`scripts/seed-demo.ts`](scripts/seed-demo.ts) |
| CI / migration workflow | [`.github/workflows/db-migrate.yml`](.github/workflows/db-migrate.yml) |
| Plan or track work on this repo | [`.icm/intake/`](.icm/intake/) — epics and stubs, contract in its README |

## Standing rules

- **Real bookings live here.** Never run a destructive migration or a seed script against a
  database you have not confirmed is disposable. `seed-demo.ts` is for demo data, not
  production.
- **Never invent a business fact.** Rates, availability rules, capacities, the estate's
  history and contact details come from `lib/site.ts`/`lib/settings.ts` or from the owner.
- **Passwords are scrypt hashes, never plaintext.** Do not add a bypass, a default, or a
  "temporary" credential to the repo — not in code, not in a migration comment.
- **Motion respects `prefers-reduced-motion`.** The parallax, headline reveals and scroll
  staggers all honour it; keep anything new in line.
- **CI is the source of truth.** Never run `build`/`lint`/`typecheck`/`test` locally — push
  and read the checks.
- **Planning is tickets.** Any plan or backlog becomes stubs in `.icm/intake/`, never a
  loose `TODO.md`. Ticket-only commits go straight to `main`; everything else through a PR
  on a `claude/` branch.
- **Gates are human checkboxes** — read them, never tick them.
- **No secrets in git, ever.** Env vars only (`DATABASE_URL`, `AUTH_SECRET`); flag any
  plaintext credential found.
