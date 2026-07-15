import { Nav } from "./components/nav";
import { Footer } from "./components/footer";
import { Hero } from "./sections/hero";
import { Estate } from "./sections/estate";
import { Spaces } from "./sections/spaces";
import { Gallery } from "./sections/gallery";
import { Location } from "./sections/location";
import { BookingCta } from "./sections/booking-cta";
import { getActiveSpaces } from "@/lib/db/queries";
import { fallbackSpaceCards, toSpaceCard, type SpaceCardData } from "@/lib/spaces";

// Refresh the landing page every few minutes so admin edits to spaces and
// rates show up without a redeploy.
export const revalidate = 300;

// The landing page must never go down with the database: fall back to the
// static space content (sans live pricing) if the query fails — e.g. during a
// local build with no DATABASE_URL.
async function loadSpaceCards(): Promise<SpaceCardData[]> {
  try {
    const rows = await getActiveSpaces();
    if (rows.length > 0) return rows.map(toSpaceCard);
  } catch (error) {
    console.error("Falling back to static space content:", error);
  }
  return fallbackSpaceCards;
}

export default async function Home() {
  const spaceCards = await loadSpaceCards();
  return (
    <>
      <Nav />
      <main>
        <Hero />
        <Estate />
        <Spaces spaces={spaceCards} />
        <Gallery />
        <Location />
        <BookingCta />
      </main>
      <Footer />
    </>
  );
}
