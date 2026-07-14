import Image from "next/image";
import { Reveal, Stagger, StaggerItem } from "@/app/components/motion";

const stats = [
  { value: "170+", label: "Years of history" },
  { value: "3", label: "Distinct spaces" },
  { value: "1", label: "Cliff-top on Lake Erie" },
];

export function Estate() {
  return (
    <section id="estate" className="relative bg-cream py-24 sm:py-32">
      <div className="mx-auto max-w-6xl px-5 sm:px-8">
        <div className="grid items-center gap-12 lg:grid-cols-2 lg:gap-20">
          <div>
            <Reveal>
              <p className="eyebrow text-amber">The Estate</p>
              <h2 className="mt-4 font-display text-4xl font-light leading-tight text-pine-900 text-balance sm:text-5xl">
                Elegant, unhurried, and steeped in history
              </h2>
            </Reveal>
            <Reveal delay={0.1}>
              <div className="mt-6 space-y-5 text-pretty text-base leading-relaxed text-ink-soft sm:text-lg">
                <p>
                  On the beautiful shores of Lake Erie, Vine Cliff Vineyards offers refined country
                  rental space — a farmhouse, a carriage house and a barn, each built more than 170
                  years ago and lovingly kept ever since.
                </p>
                <p>
                  Wander the vineyards, take the porch for the afternoon, and watch the sun fall into
                  the lake. Whether it&apos;s a quiet week away or a celebration to remember, the estate
                  is yours.
                </p>
              </div>
            </Reveal>

            <Stagger className="mt-12 grid grid-cols-3 gap-6 border-t border-pine-900/10 pt-8">
              {stats.map((s) => (
                <StaggerItem key={s.label}>
                  <p className="font-display text-3xl text-pine-700 sm:text-4xl">{s.value}</p>
                  <p className="mt-1 text-xs leading-snug text-stone sm:text-sm">{s.label}</p>
                </StaggerItem>
              ))}
            </Stagger>
          </div>

          <Reveal delay={0.15} className="relative">
            <div className="relative aspect-4/5 overflow-hidden rounded-3xl shadow-lift">
              <Image
                src="/img/full-view.jpg"
                alt="The historic white farmhouse across open lawns in the golden light of evening"
                fill
                quality={85}
                sizes="(max-width: 1024px) 100vw, 50vw"
                className="object-cover"
              />
            </div>
            {/* floating accent card */}
            <div className="absolute -bottom-6 -left-4 max-w-[15rem] rounded-2xl bg-cream-100 p-5 shadow-lift sm:-left-8">
              <p className="font-display text-lg italic text-pine-700">
                &ldquo;Elegant country rental on the shores of Lake Erie.&rdquo;
              </p>
              <p className="mt-2 eyebrow text-stone">Farmhouse · Carriage House · Barn</p>
            </div>
          </Reveal>
        </div>
      </div>
    </section>
  );
}
