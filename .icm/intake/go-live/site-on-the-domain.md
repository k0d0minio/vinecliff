# Stub: The site answers on vinecliffvineyard.com

- feature-slug: site-on-the-domain
- epic: go-live
- sequence: 6 of 9
- depends-on: none
- complexity: low
- priority: P1

## Problem

The site lives at `vinecliff.vercel.app`. `lib/site.ts` names that URL and the email `hello@vinecliff.com`, which is not the owner's domain. The owner has held `vinecliffvineyard.com` at GoDaddy since 2019 with no site on it.

## Proposed change

Production answers on `vinecliffvineyard.com`. `www` redirects to the apex. Every absolute link, the canonical URL, the sitemap and the structured data use the domain.

## Acceptance criteria

- [ ] `lib/site.ts` names `https://vinecliffvineyard.com` and `info@vinecliffvineyard.com`.
- [ ] `NEXT_PUBLIC_SITE_URL` is listed in `.env.example` with the environments it reaches.
- [ ] The metadata, the Open Graph URLs, the JSON-LD and the iCal feed URLs use the domain.
- [ ] `app/sitemap.ts` and `app/robots.ts` exist and name the domain. UAT and the previews are `noindex`.
- [ ] The README names the production URL.

## Out of scope

- The DNS records and the Vercel domain settings. They are Jamie's acts (Notes).

## Notes

Jamie's acts: add `vinecliffvineyard.com` and `www.vinecliffvineyard.com` to the Vercel project `kodominio/vinecliff`, set the records at GoDaddy, set `NEXT_PUBLIC_SITE_URL` in Production. The owner holds the domain. Jamie is a delegate and never holds the owner's password.
