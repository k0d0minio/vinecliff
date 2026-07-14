import Image from "next/image";
import { ArrowLeft, ArrowRight, BookOpen, ExternalLink } from "lucide-react";
import { Reveal, Stagger, StaggerItem } from "@/app/components/motion";
import { buttonVariants } from "@/app/components/ui/button";
import { cn } from "@/lib/utils";
import { figures, sources, timeline } from "@/lib/history";
import { Cite } from "./cite";

/* ------------------------------------------------------------------ */
/*  Hero                                                               */
/* ------------------------------------------------------------------ */

export function HistoryHero() {
  return (
    <section className="relative flex h-[82svh] min-h-[560px] w-full items-end overflow-hidden">
      <Image
        src="/img/full-view.jpg"
        alt="The Vine Cliff estate at dusk, on the site of the 19th-century Salem-on-Erie colony"
        fill
        priority
        quality={88}
        sizes="100vw"
        className="object-cover object-center"
      />
      <div className="absolute inset-0 bg-gradient-to-b from-pine-900/70 via-pine-900/45 to-pine-900/92" />
      <div className="absolute inset-0 bg-gradient-to-t from-cream via-transparent to-transparent opacity-95" />

      <div className="relative z-10 mx-auto w-full max-w-6xl px-5 pb-16 sm:px-8 sm:pb-24">
        <Reveal>
          <p className="eyebrow text-amber-soft">The History · Salem-on-Erie, est. 1867</p>
          <h1 className="mt-5 max-w-3xl font-display text-[2.6rem] font-light leading-[1.03] text-cream text-balance sm:text-6xl lg:text-7xl">
            The mystics who
            <br className="hidden sm:block" />{" "}
            <span className="italic text-amber-soft">planted these vines</span>
          </h1>
          <p className="mt-6 max-w-xl text-pretty text-base leading-relaxed text-cream/85 sm:text-lg">
            Long before it was a country retreat, this land above Lake Erie was the
            heart of a utopian colony — its farms devoted to vineyards, its story
            entwining an English prophet, a British aristocrat, and a samurai from Satsuma.
          </p>
        </Reveal>
      </div>
    </section>
  );
}

/* ------------------------------------------------------------------ */
/*  Lede / overview                                                    */
/* ------------------------------------------------------------------ */

export function HistoryLede() {
  return (
    <section className="relative bg-cream py-20 sm:py-28">
      <div className="mx-auto max-w-3xl px-5 sm:px-8">
        <Reveal>
          <p className="eyebrow text-amber">A brief history</p>
          <h2 className="mt-4 font-display text-3xl font-light leading-tight text-pine-900 text-balance sm:text-4xl">
            From “Salem-on-Erie” to Vine Cliff
          </h2>
        </Reveal>
        <Reveal delay={0.1}>
          <div className="mt-7 space-y-5 text-pretty text-lg leading-relaxed text-ink-soft">
            <p>
              In October 1867 the visionary preacher Thomas Lake Harris moved his
              Brotherhood of the New Life to Brocton, on the cliffs above Lake Erie,
              and named the settlement <em>Salem-on-Erie</em>.
              <Cite n={[1, 8]} /> The colony’s farms — which at their height spanned
              more than <strong className="font-medium text-pine-900">2,000 acres</strong> —
              were given over to grape-growing and wine-making, and the Brocton property is
              the land now known as <strong className="font-medium text-pine-900">Vine Cliff</strong>.
              <Cite n={9} />
            </p>
            <p>
              What followed reads like a novel: a British Member of Parliament who gave up
              his seat to labour in these fields; young men smuggled out of feudal Japan to
              learn the vine here; and a wine-making enterprise that carried the estate’s
              disciples all the way to the hills of Sonoma County, California.
              <Cite n={[3, 6]} />
            </p>
          </div>
        </Reveal>

        <Reveal delay={0.15}>
          <figure className="mt-12 border-l-2 border-amber/60 pl-6">
            <blockquote className="font-display text-2xl font-light italic leading-snug text-pine-700 sm:text-3xl">
              “Various farms here … were devoted to vine-growing and wine-making.”
            </blockquote>
            <figcaption className="mt-3 text-sm text-stone">
              — Dictionary of National Biography, on the Brocton colony
              <Cite n={1} />
            </figcaption>
          </figure>
        </Reveal>
      </div>
    </section>
  );
}

/* ------------------------------------------------------------------ */
/*  Timeline                                                           */
/* ------------------------------------------------------------------ */

export function HistoryTimeline() {
  return (
    <section className="relative overflow-hidden bg-parchment py-20 sm:py-28">
      <div className="mx-auto max-w-4xl px-5 sm:px-8">
        <Reveal className="max-w-2xl">
          <p className="eyebrow text-amber">The story, year by year</p>
          <h2 className="mt-4 font-display text-3xl font-light leading-tight text-pine-900 text-balance sm:text-4xl">
            A timeline of the estate
          </h2>
        </Reveal>

        <Stagger className="mt-14 space-y-0">
          {timeline.map((e, i) => (
            <StaggerItem key={e.year}>
              <div className="group relative grid grid-cols-[4.5rem_1fr] gap-4 sm:grid-cols-[7rem_1fr] sm:gap-8">
                {/* year rail */}
                <div className="text-right">
                  <span className="font-display text-lg text-pine-700 sm:text-xl">{e.year}</span>
                </div>
                {/* line + node */}
                <div className="relative pb-10">
                  <span className="absolute -left-4 top-1.5 size-3 rounded-full border-2 border-amber bg-cream sm:-left-[2.05rem]" />
                  {i < timeline.length - 1 && (
                    <span className="absolute -left-[0.7rem] top-4 h-full w-px bg-pine-900/15 sm:-left-[1.55rem]" />
                  )}
                  <h3 className="font-display text-xl text-pine-900">{e.title}</h3>
                  <p className="mt-2 text-pretty leading-relaxed text-ink-soft">
                    {e.body}
                    <Cite n={e.cites} />
                  </p>
                </div>
              </div>
            </StaggerItem>
          ))}
        </Stagger>
      </div>
    </section>
  );
}

/* ------------------------------------------------------------------ */
/*  The people                                                         */
/* ------------------------------------------------------------------ */

export function HistoryFigures() {
  return (
    <section className="relative bg-cream py-20 sm:py-28">
      <div className="mx-auto max-w-6xl px-5 sm:px-8">
        <Reveal className="max-w-2xl">
          <p className="eyebrow text-amber">The people</p>
          <h2 className="mt-4 font-display text-3xl font-light leading-tight text-pine-900 text-balance sm:text-4xl">
            Three lives bound to this land
          </h2>
        </Reveal>

        <div className="mt-14 space-y-16 sm:space-y-24">
          {figures.map((f, i) => (
            <Reveal key={f.id} delay={0.05}>
              <article
                className={cn(
                  "grid items-center gap-8 lg:grid-cols-5 lg:gap-14",
                  i % 2 === 1 && "lg:[&>figure]:order-2"
                )}
              >
                <figure className="lg:col-span-2">
                  <div className="relative mx-auto aspect-4/5 w-full max-w-xs overflow-hidden rounded-3xl bg-pine-900/5 shadow-lift sm:max-w-sm">
                    <Image
                      src={f.image}
                      alt={f.alt}
                      fill
                      quality={85}
                      sizes="(max-width: 1024px) 80vw, 40vw"
                      className="object-cover object-top sepia-[0.15]"
                    />
                    <div className="absolute inset-x-0 bottom-0 bg-gradient-to-t from-pine-900/85 to-transparent p-5 pt-12">
                      <p className="font-display text-xl text-cream">{f.name}</p>
                      <p className="text-xs text-cream/70">{f.life} · {f.role}</p>
                    </div>
                  </div>
                </figure>

                <div className="lg:col-span-3">
                  <p className="eyebrow text-stone">{f.role}</p>
                  <h3 className="mt-2 font-display text-2xl font-light text-pine-900 sm:text-3xl">
                    {f.name}
                  </h3>
                  <div className="mt-5 space-y-4 text-pretty leading-relaxed text-ink-soft">
                    {f.paragraphs.map((p, j) => (
                      <p key={j}>
                        {p.text}
                        <Cite n={p.cites} />
                      </p>
                    ))}
                  </div>
                </div>
              </article>
            </Reveal>
          ))}
        </div>
      </div>
    </section>
  );
}

/* ------------------------------------------------------------------ */
/*  The vineyards (scale)                                              */
/* ------------------------------------------------------------------ */

const scaleStats = [
  { value: "2,000+", label: "Acres at Salem-on-Erie", cite: 9 },
  { value: "1867", label: "Vineyards first planted", cite: 8 },
  { value: "15", label: "Satsuma students to the West", cite: 6 },
] as const;

export function HistoryVineyards() {
  return (
    <section className="relative overflow-hidden bg-pine-900 py-20 text-cream sm:py-28">
      <div className="mx-auto max-w-5xl px-5 sm:px-8">
        <Reveal className="max-w-3xl">
          <p className="eyebrow text-amber-soft">A wine estate of the first rank</p>
          <h2 className="mt-4 font-display text-3xl font-light leading-tight text-cream text-balance sm:text-4xl">
            One of the great vineyards of Lake Erie
          </h2>
          <p className="mt-6 text-pretty text-lg leading-relaxed text-cream/80">
            The Brotherhood built a stone winery and turned the slopes above the lake into
            a working vineyard. Period accounts record the colony holding more than 2,000
            acres at Brocton — an agricultural enterprise of remarkable scale for its day —
            with its farms “devoted to vine-growing and wine-making.”
            <Cite n={[1, 9]} /> The estate sits within what remains the largest
            grape-growing region east of the Rocky Mountains.
          </p>
        </Reveal>

        <Stagger className="mt-14 grid grid-cols-1 gap-6 border-t border-cream/15 pt-10 sm:grid-cols-3">
          {scaleStats.map((s) => (
            <StaggerItem key={s.label}>
              <p className="font-display text-4xl font-light text-amber-soft sm:text-5xl">
                {s.value}
              </p>
              <p className="mt-2 text-sm leading-snug text-cream/70">
                {s.label}
                <Cite n={s.cite} className="text-amber-soft/80" />
              </p>
            </StaggerItem>
          ))}
        </Stagger>
      </div>
    </section>
  );
}

/* ------------------------------------------------------------------ */
/*  The estate today                                                   */
/* ------------------------------------------------------------------ */

export function HistoryToday() {
  return (
    <section className="relative bg-cream py-20 sm:py-28">
      <div className="mx-auto max-w-6xl px-5 sm:px-8">
        <div className="grid items-center gap-12 lg:grid-cols-2 lg:gap-16">
          <Reveal className="relative">
            <div className="relative aspect-4/3 overflow-hidden rounded-3xl shadow-lift">
              <Image
                src="/img/house.jpg"
                alt="The historic white farmhouse at Vine Cliff today"
                fill
                quality={85}
                sizes="(max-width: 1024px) 100vw, 50vw"
                className="object-cover"
              />
            </div>
          </Reveal>
          <div>
            <Reveal>
              <p className="eyebrow text-amber">The estate today</p>
              <h2 className="mt-4 font-display text-3xl font-light leading-tight text-pine-900 text-balance sm:text-4xl">
                History you can stay in
              </h2>
            </Reveal>
            <Reveal delay={0.1}>
              <div className="mt-6 space-y-5 text-pretty text-lg leading-relaxed text-ink-soft">
                <p>
                  The colony was sold after the Oliphants’ suit against Harris around 1881,
                  and Salem-on-Erie passed into private hands.<Cite n={3} /> The farmhouse,
                  carriage house and barn — each more than 170 years old — still stand on the
                  cliffs where the Brotherhood once tended its vines.
                </p>
                <p>
                  Today Vine Cliff welcomes guests for weekly stays, weekend escapes and
                  celebrations — a chance to walk the same grounds that drew dreamers,
                  aristocrats and wanderers from across the world.
                </p>
              </div>
            </Reveal>
            <Reveal delay={0.15}>
              <a
                href="/#spaces"
                className={cn(buttonVariants({ variant: "primary", size: "md" }), "mt-8")}
              >
                Explore the spaces
                <ArrowRight className="size-4" />
              </a>
            </Reveal>
          </div>
        </div>
      </div>
    </section>
  );
}

/* ------------------------------------------------------------------ */
/*  Sources                                                            */
/* ------------------------------------------------------------------ */

export function HistorySources() {
  return (
    <section className="relative border-t border-pine-900/10 bg-parchment py-20 sm:py-24">
      <div className="mx-auto max-w-3xl px-5 sm:px-8">
        <Reveal>
          <div className="flex items-center gap-3">
            <BookOpen className="size-5 text-amber" />
            <p className="eyebrow text-amber">Sources & further reading</p>
          </div>
          <h2 className="mt-4 font-display text-3xl font-light leading-tight text-pine-900 text-balance sm:text-4xl">
            Where this history comes from
          </h2>
          <p className="mt-5 text-pretty leading-relaxed text-ink-soft">
            The account above is drawn from period reference works, modern encyclopaedias and
            local Chautauqua County and Sonoma County history. Each footnote in the text links
            to its source below.
          </p>
        </Reveal>

        <Reveal delay={0.1}>
          <ol className="mt-10 space-y-4">
            {sources.map((s) => (
              <li
                key={s.id}
                id={`source-${s.id}`}
                className="scroll-mt-24 grid grid-cols-[2rem_1fr] gap-3 border-b border-pine-900/8 pb-4 text-sm leading-relaxed"
              >
                <span className="font-display text-base text-amber">{s.id}.</span>
                <div>
                  <span className="text-ink-soft">{s.citation}</span>
                  <a
                    href={s.url}
                    target="_blank"
                    rel="noopener noreferrer"
                    className="mt-1 inline-flex items-center gap-1 break-all text-pine-700 underline-offset-2 hover:underline"
                  >
                    <ExternalLink className="size-3 shrink-0" />
                    <span className="break-all">{s.url}</span>
                  </a>
                </div>
              </li>
            ))}
          </ol>
        </Reveal>

        <Reveal delay={0.15}>
          <p className="mt-8 text-xs leading-relaxed text-stone">
            A note on accuracy: nineteenth-century figures for acreage and membership vary
            between sources, and some colourful colony legends are hard to verify. Where
            accounts differ we have followed the most authoritative period and reference
            sources and noted them here so readers can judge for themselves.
          </p>
        </Reveal>

        <Reveal delay={0.2}>
          <a
            href="/"
            className={cn(buttonVariants({ variant: "outline", size: "md" }), "mt-10")}
          >
            <ArrowLeft className="size-4" />
            Back to Vine Cliff
          </a>
        </Reveal>
      </div>
    </section>
  );
}
