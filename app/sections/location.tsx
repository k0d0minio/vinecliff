import Image from "next/image";
import { MapPin, Navigation } from "lucide-react";
import { nearby, site } from "@/lib/site";
import { Reveal, Stagger, StaggerItem } from "@/app/components/motion";
import { buttonVariants } from "@/app/components/ui/button";
import { cn } from "@/lib/utils";

export function Location() {
  return (
    <section id="location" className="relative bg-cream py-24 sm:py-32">
      <div className="mx-auto max-w-6xl px-5 sm:px-8">
        <div className="grid gap-12 lg:grid-cols-2 lg:gap-16">
          <Reveal className="relative order-2 lg:order-1">
            <div className="relative aspect-square overflow-hidden rounded-3xl shadow-lift sm:aspect-4/3 lg:aspect-square">
              <Image
                src="/img/sunset.jpg"
                alt="Sunset breaking through the trees over the estate grounds and driveway"
                fill
                quality={85}
                sizes="(max-width: 1024px) 100vw, 50vw"
                className="object-cover"
              />
              <a
                href={site.mapUrl}
                target="_blank"
                rel="noopener noreferrer"
                className="absolute bottom-5 left-5 right-5 flex items-center gap-3 rounded-2xl bg-cream-100/95 p-4 backdrop-blur transition-transform duration-300 hover:-translate-y-1"
              >
                <span className="grid size-10 shrink-0 place-items-center rounded-full bg-pine-700 text-cream">
                  <MapPin className="size-5" />
                </span>
                <span className="min-w-0">
                  <span className="block text-sm font-medium text-pine-900">{site.address.line1}</span>
                  <span className="block truncate text-xs text-stone">
                    {site.address.city}, {site.address.region} {site.address.postalCode}
                  </span>
                </span>
                <Navigation className="ml-auto size-4 shrink-0 text-amber" />
              </a>
            </div>
          </Reveal>

          <div className="order-1 lg:order-2">
            <Reveal>
              <p className="eyebrow text-amber">The Setting</p>
              <h2 className="mt-4 font-display text-4xl font-light leading-tight text-pine-900 text-balance sm:text-5xl">
                In the heart of Lake Erie wine country
              </h2>
              <p className="mt-5 text-pretty text-base leading-relaxed text-ink-soft sm:text-lg">
                Tucked into the cliffs near Brocton, the estate is a short, scenic drive from some of
                Western New York&apos;s best-loved destinations.
              </p>
            </Reveal>

            <Stagger className="mt-10 space-y-3">
              {nearby.map((n) => (
                <StaggerItem key={n.name}>
                  <div className="group flex items-start gap-4 rounded-2xl border border-pine-900/8 bg-cream-100 p-5 transition-all duration-300 hover:border-pine-700/25 hover:shadow-soft">
                    <span className="mt-1 size-2 shrink-0 rounded-full bg-amber transition-transform duration-300 group-hover:scale-150" />
                    <div>
                      <h3 className="font-display text-lg text-pine-900">{n.name}</h3>
                      <p className="text-sm text-stone">{n.note}</p>
                    </div>
                  </div>
                </StaggerItem>
              ))}
            </Stagger>

            <Reveal delay={0.1}>
              <a
                href={site.mapUrl}
                target="_blank"
                rel="noopener noreferrer"
                className={cn(buttonVariants({ variant: "outline", size: "md" }), "mt-8")}
              >
                <Navigation className="size-4" />
                Get directions
              </a>
            </Reveal>
          </div>
        </div>
      </div>
    </section>
  );
}
