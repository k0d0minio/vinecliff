# Stub: The site looks like the owner's logo

- feature-slug: brand-from-the-logo
- epic: go-live
- sequence: 4 of 9
- depends-on: none
- complexity: medium
- priority: P1

## Problem

The site uses a pine, cream and amber palette with Fraunces. The owner's logo is blue and green, set in Bodoni. On the demo call of 2026-10-22 the owner kept his logo and asked the site to change around it.

## Proposed change

Restyle the site and the admin to `.icm/docs/brand.md`: the colors, the type, the shapes, and where the logo shows.

## Acceptance criteria

- [ ] `app/globals.css` defines the tokens of `.icm/docs/brand.md` (`blue`, `green`, `white`, `blue-900`, `blue-50`, `stone`). No pine, cream, parchment, amber or lake token is left.
- [ ] Bodoni Moda (regular and italic) is self-hosted in `app/fonts/` and is the heading font. Fraunces is removed. Inter stays the body font.
- [ ] `public/brand/vinecliff-logo.svg` and `vinecliff-logo-white.svg` are copies of the files in `.icm/docs/brand/`. The navigation shows the full-color logo. The footer has the `blue` background and the white logo.
- [ ] The favicon, the apple icon and the Open Graph and Twitter images follow the guide's "Where the brand shows".
- [ ] Green is never text on white. Every text color pair passes WCAG AA.
- [ ] The guest emails show the full-color logo and `blue` links.
- [ ] The admin uses the same tokens.

## Out of scope

- A change to the logo.
- New photos.

## Notes

Shared files: `app/globals.css`, `app/layout.tsx`, `app/fonts/`, the navigation and the footer. This stub goes before `legal-pages`, which adds links to the footer. The logo masters stay in Jamie's Drive. The SVGs in `.icm/docs/brand/` are the web copies, with the spec's hex fills.
