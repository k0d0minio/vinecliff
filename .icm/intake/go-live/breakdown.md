# Breakdown: Vine Cliff goes live on vinecliffvineyard.com

- epic-slug: go-live
- source: the kickoff of 2026-10-26 (Jamie's answers after his calls with the owner, in the house at `clients/vinecliff/kickoff/kickoff-2026-10-26.md`); the demo call of 2026-10-22 with Billy Carlson ("Vinecliff Demo – 2026/10/22 21:00 WEST – Notes by Gemini", Jamie's Drive); the offer "Vine Cliff, booked direct" of 2026-10-12 (Jamie's Drive, folder `vinecliff`); the logo files in the same folder

## What I understood

The site and the admin work today on `vinecliff.vercel.app` with placeholder rates and photos. This epic takes the site live on the owner's domain by the end of December 2026. The owner, Billy Carlson, decides and tests. He sends feedback by email. The site speaks en-US only.

The epic does six things. It splits the farmhouse into two bookable units, as the owner asked on 2026-10-22. It restyles the site around the owner's logo, which does not change (`.icm/docs/brand.md`). It lets an admin change their own password, so that the owner replaces the seeded one. It moves the site to `vinecliffvineyard.com` and sends every email from `info@vinecliffvineyard.com`. It adds basic error tracking with Sentry. It adds the terms and the privacy policy, written from US defaults.

The owner tests each batch on a UAT environment before production (`uat: yes`). The repo is not yet updated to the blueprint version that renders UAT, so `uat-environment` is blocked until that update.

The site takes no payment online. A guest requests dates, the owner approves, and the owner collects the deposit off the site, as the build does today. Airbnb and VRBO calendar sync is not in this epic.

### Questions for the owner

1. What are the names of the two farmhouse units? Default: "Farmhouse, Side One" and "Farmhouse, Side Two".
2. How many guests does each unit sleep, and can a guest book the whole farmhouse as one unit? Default: the owner enters the numbers in the admin. The whole farmhouse is booked as the whole estate.
3. What is the legal name of the business for the terms? Default: Vine Cliff Vineyard, owned by William Patrick Carlson.
4. Does a reply to `info@vinecliffvineyard.com` reach the owner's Gmail? Default: yes, by a forward that Jamie sets at GoDaddy.
5. When do the photos arrive? Default: before 1 December 2026. They replace the placeholders through the admin or by Jamie.

### Questions for Jamie

1. The offer of 2026-10-12 also lists one calendar with Airbnb and VRBO, card deposits through Stripe, taxes shown on the total, the owner's videos, a password reset by email, a login for Margaret, and a help page with a walkthrough. None is in this epic. Do they become a second epic after go-live? Default: yes.
2. Which Sentry organization holds the project? Default: Jamie's own, under the monthly hosting line.
3. Which Resend account sends the mail? Default: Jamie's, with `vinecliffvineyard.com` verified as a sending domain.

## Build order

1. drop-legacy-files — the old onboarding forms and `info.txt` leave the repo — depends-on: none
2. farmhouse-two-units — the farmhouse becomes two bookable units — depends-on: none
3. brand-from-the-logo — the site restyled around the owner's logo — depends-on: none
4. admin-password-change — an admin changes their own password — depends-on: none
5. uat-environment — the owner tests each batch at the UAT address — depends-on: none
6. site-on-the-domain — the site answers on vinecliffvineyard.com — depends-on: none
7. email-from-info — every email comes from info@vinecliffvineyard.com — depends-on: site-on-the-domain
8. error-tracking — Sentry sees each server error, and a guest sees a calm page — depends-on: none
9. legal-pages — the terms and the privacy policy, linked from the footer — depends-on: brand-from-the-logo

## Out of scope

- Airbnb and VRBO calendar sync, card deposits, taxes on the total, the owner's videos, a password reset by email, a second admin login, the help page and the walkthrough (question 1 for Jamie).
- The update of this repo to the latest blueprint with `release: yes` and `uat: yes`. Conformance does it, from the house.
- The owner's rates, rules and texts. The owner types them in the admin.
- Photography and copywriting (the offer, "Not included").
