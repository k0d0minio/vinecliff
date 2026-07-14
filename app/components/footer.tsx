import { MapPin, Phone, Mail } from "lucide-react";
import { site } from "@/lib/site";
import { Reveal } from "./motion";

export function Footer() {
  return (
    <footer className="relative overflow-hidden bg-pine-900 text-cream/80">
      <div className="mx-auto max-w-6xl px-5 py-16 sm:px-8 sm:py-20">
        <Reveal>
          <div className="grid gap-12 sm:grid-cols-2 lg:grid-cols-4">
            <div className="lg:col-span-2">
              <p className="font-display text-3xl text-cream">Vine Cliff</p>
              <p className="mt-1 eyebrow text-amber-soft">Vineyards · Est. 1850</p>
              <p className="mt-6 max-w-sm text-pretty text-sm leading-relaxed text-cream/70">
                {site.tagline}. A short drive from Chautauqua, SUNY Fredonia and Dunkirk.
              </p>
            </div>

            <div>
              <h3 className="eyebrow text-cream/50">Visit</h3>
              <a
                href={site.mapUrl}
                target="_blank"
                rel="noopener noreferrer"
                className="mt-4 flex items-start gap-3 text-sm leading-relaxed transition-colors hover:text-cream"
              >
                <MapPin className="mt-0.5 size-4 shrink-0 text-amber-soft" />
                <span>
                  {site.address.line1}
                  <br />
                  {site.address.city}, {site.address.region} {site.address.postalCode}
                </span>
              </a>
            </div>

            <div>
              <h3 className="eyebrow text-cream/50">Enquire</h3>
              <div className="mt-4 space-y-3 text-sm">
                <a
                  href={site.phoneHref}
                  className="flex items-center gap-3 transition-colors hover:text-cream"
                >
                  <Phone className="size-4 shrink-0 text-amber-soft" />
                  {site.phone}
                </a>
                <a
                  href={`mailto:${site.email}`}
                  className="flex items-center gap-3 transition-colors hover:text-cream"
                >
                  <Mail className="size-4 shrink-0 text-amber-soft" />
                  {site.email}
                </a>
              </div>
            </div>
          </div>
        </Reveal>

        <div className="mt-16 flex flex-col gap-4 border-t border-cream/10 pt-8 text-xs text-cream/50 sm:flex-row sm:items-center sm:justify-between">
          <p>© {new Date().getFullYear()} Vine Cliff Vineyards. All rights reserved.</p>
          <p className="text-cream/40">On the shores of Lake Erie, New York.</p>
        </div>
      </div>
    </footer>
  );
}
