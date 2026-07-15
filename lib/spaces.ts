// Display shapes for spaces on the public site, plus a static fallback so the
// marketing landing page still renders if the database is unreachable (or at
// build time before DATABASE_URL exists). The fallback mirrors the seeded
// content minus live pricing.
import type { Space } from "@/lib/db/schema";
import { formatMoney } from "@/lib/booking/pricing";
import { spaces as staticSpaces } from "@/lib/site";

export type SpaceCardData = {
  slug: string;
  name: string;
  kind: string;
  age: string;
  image: string;
  blurb: string;
  features: string[];
  /** e.g. "From $450 / night" — null when pricing isn't available. */
  fromLabel: string | null;
  /** The whole-estate package renders as a banner, not a card. */
  isEstate: boolean;
};

export function toSpaceCard(space: Space): SpaceCardData {
  return {
    slug: space.slug,
    name: space.name,
    kind: space.kind,
    age: space.age,
    image: space.image,
    blurb: space.blurb,
    features: space.features,
    fromLabel: `From ${formatMoney(space.nightlyRateCents)} / ${space.isEvent ? "day" : "night"}`,
    isEstate: space.slug === "estate",
  };
}

export const fallbackSpaceCards: SpaceCardData[] = staticSpaces.map((s) => ({
  slug: s.id,
  name: s.name,
  kind: s.kind,
  age: s.age,
  image: s.image,
  blurb: s.blurb,
  features: [...s.features],
  fromLabel: null,
  isEstate: false,
}));
