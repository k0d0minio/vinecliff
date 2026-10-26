# Vine Cliff Vineyard: brand guide

Derived on 2026-10-26 from the logo files in Jamie's Drive folder `vinecliff`:
`VineCliff_logo_specs.pdf` (Julie Zack, 8 May 2019), `VineCliff_logo_CMYK.pdf`,
`VineCliff_logo_RGB_transparent.png` and `VineCliff_logo_specs.ai`. The owner's words come from
the demo call of 2026-10-22: he keeps the logo his sister made, he likes "basic" and
minimalist, and his kit is "blue and white with a splash of green". The site changes around
the logo. The logo does not change.

## The logo

- `brand/vinecliff-logo.svg`: the full-color logo, blue and green, for a white or light
  background. Converted from `VineCliff_logo_CMYK.pdf`. The fills are the spec's hex values.
- `brand/vinecliff-logo-white.svg`: the same logo with white letters and the green kept, for
  the blue background.
- The spec also gives a black logo. Use it only where the medium has one color (a print in
  black, a fax, an engraving).
- Never redraw, stretch, recolor or re-set the logo in a web font. Use the files.
- Keep clear space around the logo equal to the height of the word "VINEYARD" or more.
- The smallest width on screen is 140 px. Under that width the ornament and "VINEYARD" are too
  small to read.

## Colors

| Token | Hex | From the spec | Use |
|---|---|---|---|
| `blue` | `#14467C` | C100 M80 Y25 K10, R20 G70 B124 | The brand color. Headings, links, buttons, the footer background. |
| `green` | `#A6CE39` | C40 M0 Y100 K0, R166 G206 B57 | The splash. The logo's dots and ornament, a rule, an icon, a focus ring on blue. Never text on white. |
| `white` | `#FFFFFF` | — | The page. |
| `blue-900` | `#0C2C4F` | derived: `blue` darker | Body text, and the hover state of a blue button. |
| `blue-50` | `#EEF3F8` | derived: `blue` at 8 % on white | A quiet section background, a card, a table stripe. |
| `stone` | `#6B7280` | derived: a neutral gray | Secondary text, captions, borders at 30 %. |

Rules for color:

- White is the ground. Blue carries the identity. Green is a splash: about one green element per
  screen (why: "blue and white with a splash of green" · the owner, 2026-10-22).
- Contrast: `blue` on white is 9.6 : 1, and white on `blue` is the same. Both pass WCAG AA for
  all text. `green` on white is 1.8 : 1, so green is never text and never the only signal of a
  state. Green on `blue` is 5.2 : 1: use it for a focus ring or an icon on the footer. `stone`
  on white is 4.8 : 1, and on `blue-50` only 4.3 : 1, so secondary text on `blue-50` uses
  `blue-900`.
- The photographs bring the warm colors (the lake, the sunsets, the vines). The interface stays
  blue, white and gray.

## Type

The spec sets the logo in Bodoni 72 Book ("Vine", "VINEYARD") and Bodoni 72 Book Italic
("Cliff", the ornament). Bodoni 72 is a licensed desktop font with no web license, so the site
uses the open Bodoni Moda (SIL Open Font License), self-hosted like the current fonts.

| Role | Font | Notes |
|---|---|---|
| Headings | Bodoni Moda, regular | Sentence case. Large sizes only (24 px and up): a Bodoni loses its thin strokes when small. |
| The accent | Bodoni Moda, italic | One word or a short phrase in a heading, as "Cliff" is in the logo. Not a whole heading. |
| Small caps labels | Bodoni Moda, regular, uppercase, letter spacing 0.2 em | An eyebrow over a heading, as "VINEYARD" sits under the name. |
| Body, forms, the admin | Inter (already self-hosted) | 16 px and up for body text. |

Fraunces leaves the site. Inter stays.

## Shape and motion

- Minimal: plenty of white space, thin rules (1 px, `stone` at 30 %, or `green` for one
  accent rule), square or slightly rounded corners (4 px).
- Buttons: solid `blue` with white text, or a `blue` outline on white. No gradients and no
  shadows heavier than a soft 1-step elevation.
- The current motion (reveals, parallax) stays, slower and quieter. It respects
  `prefers-reduced-motion`.

## Where the brand shows

- The navigation: the full-color logo on white.
- The footer: `blue` background, the white logo, white text, green for one rule or the icons.
- The favicon and the app icon: the italic "C" of "Cliff" in `blue` on white, or the green dot,
  cut from the SVG.
- The Open Graph image: a photograph of the estate with the white logo on a `blue` band.
- Emails to guests: the full-color logo at the top, `blue` links, Inter or the system sans.
