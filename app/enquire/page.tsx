import type { Metadata } from "next";
import { Phone } from "lucide-react";
import { Nav } from "@/app/components/nav";
import { Footer } from "@/app/components/footer";
import { site } from "@/lib/site";
import { getActiveSpaces } from "@/lib/db/queries";
import { EnquiryForm } from "./enquiry-form";

export const dynamic = "force-dynamic";

export const metadata: Metadata = {
  title: "Enquire",
  description:
    "Ask us anything about stays, weddings and events at Vine Cliff — we read every enquiry personally.",
  alternates: { canonical: "/enquire" },
};

type Props = { searchParams: Promise<{ space?: string }> };

export default async function EnquirePage({ searchParams }: Props) {
  const { space: defaultSpace } = await searchParams;
  let spaceOptions: Array<{ slug: string; name: string }> = [];
  try {
    spaceOptions = (await getActiveSpaces()).map((s) => ({
      slug: s.slug,
      name: s.name,
    }));
  } catch (error) {
    console.error("Enquiry page: failed to load spaces", error);
  }

  return (
    <>
      <Nav />
      <main className="bg-cream">
        <section className="bg-pine-900 px-5 pb-16 pt-32 text-center sm:pb-20 sm:pt-40">
          <div className="mx-auto max-w-2xl">
            <p className="eyebrow text-amber-soft">Enquiries</p>
            <h1 className="mt-4 font-display text-3xl font-light text-cream sm:text-5xl">
              Tell us what you&apos;re dreaming up
            </h1>
            <p className="mx-auto mt-4 max-w-lg text-pretty text-sm leading-relaxed text-cream/80 sm:text-base">
              Not ready to pick dates, or planning something that doesn&apos;t fit a form? Write
              to us — a real person on the estate reads every message.
            </p>
          </div>
        </section>

        <section className="mx-auto w-full max-w-2xl px-5 py-12 sm:px-8 sm:py-16">
          <EnquiryForm spaceOptions={spaceOptions} defaultSpace={defaultSpace} />
          <p className="mt-8 text-center text-sm text-ink-soft">
            Rather talk?{" "}
            <a
              href={site.phoneHref}
              className="inline-flex items-center gap-1.5 font-medium text-pine-700 hover:text-amber"
            >
              <Phone className="size-3.5" />
              {site.phone}
            </a>
          </p>
        </section>
      </main>
      <Footer />
    </>
  );
}
