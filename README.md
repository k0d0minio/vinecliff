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

## Getting started

```bash
npm install
npm run dev
```

Open [http://localhost:3000](http://localhost:3000).

## Scripts

- `npm run dev` — start the dev server
- `npm run build` — production build
- `npm run start` — serve the production build
- `npm run lint` — lint

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
  admin-auth.ts   Session-token helpers for the admin password gate
  utils.ts        cn() helper
middleware.ts     Protects /admin routes behind the login cookie
public/img/       Estate photography
```

## Admin section

A private, mobile-responsive admin area lives at `/admin`. It's the foundation
for managing bookings, enquiries and site content — the pages are scaffolded
now and will be wired to real data later.

Access is gated by a single shared password. Set it before running:

```bash
ADMIN_PASSWORD="choose-a-strong-password"
```

Add it to `.env.local` for development and to the hosting provider's
environment variables in production. Every `/admin` route is protected by
`middleware.ts`; visitors are redirected to `/admin/login` until they sign in.
The session is stored in an httpOnly cookie derived from the password, so
changing (or unsetting) `ADMIN_PASSWORD` immediately ends all sessions.

## Design notes

- **Mobile-first** throughout, with a full-screen mobile nav.
- Warm heritage-estate palette (pine green, cream, sunset amber, lake teal).
- Subtle, tasteful motion: parallax hero, word-by-word headline reveal,
  staggered scroll reveals, image hover zoom. Respects `prefers-reduced-motion`.
- SEO: Open Graph, Twitter cards, and `LodgingBusiness` structured data.
