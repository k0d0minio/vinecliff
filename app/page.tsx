import { Nav } from "./components/nav";
import { Footer } from "./components/footer";
import { Hero } from "./sections/hero";
import { Estate } from "./sections/estate";
import { Spaces } from "./sections/spaces";
import { Gallery } from "./sections/gallery";
import { Location } from "./sections/location";
import { BookingCta } from "./sections/booking-cta";

export default function Home() {
  return (
    <>
      <Nav />
      <main>
        <Hero />
        <Estate />
        <Spaces />
        <Gallery />
        <Location />
        <BookingCta />
      </main>
      <Footer />
    </>
  );
}
