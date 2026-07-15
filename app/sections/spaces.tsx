"use client";

import Image from "next/image";
import Link from "next/link";
import { motion, useReducedMotion } from "framer-motion";
import { ArrowUpRight, Check, KeyRound } from "lucide-react";
import type { SpaceCardData } from "@/lib/spaces";
import { buttonVariants } from "@/app/components/ui/button";
import { Reveal } from "@/app/components/motion";
import { useInViewOnce } from "@/app/components/use-in-view";
import { cn } from "@/lib/utils";

const EASE = [0.16, 1, 0.3, 1] as const;

export function Spaces({ spaces }: { spaces: SpaceCardData[] }) {
  const reduce = useReducedMotion();
  const { ref, inView } = useInViewOnce();

  const cards = spaces.filter((s) => !s.isEstate);
  const estate = spaces.find((s) => s.isEstate);

  return (
    <section id="spaces" className="relative bg-parchment/60 py-24 sm:py-32">
      <div className="mx-auto max-w-6xl px-5 sm:px-8">
        <Reveal className="max-w-2xl">
          <p className="eyebrow text-amber">Stay & Celebrate</p>
          <h2 className="mt-4 font-display text-4xl font-light leading-tight text-pine-900 text-balance sm:text-5xl">
            Three spaces, one storied estate
          </h2>
          <p className="mt-5 text-pretty text-base leading-relaxed text-ink-soft sm:text-lg">
            Each building carries its own character. Check live availability and request your
            dates online — or take the whole grounds for a wedding, reunion or retreat.
          </p>
        </Reveal>

        <div ref={ref} className="mt-14 grid gap-6 md:grid-cols-3">
          {cards.map((space, i) => (
            <motion.article
              key={space.slug}
              id={space.slug}
              initial={reduce ? { opacity: 0 } : { opacity: 0, y: 40 }}
              animate={inView ? { opacity: 1, y: 0 } : undefined}
              transition={{ duration: 0.8, ease: EASE, delay: i * 0.12 }}
              className="group relative flex flex-col overflow-hidden rounded-3xl bg-cream-100 shadow-soft transition-all duration-500 hover:shadow-lift hover:-translate-y-1.5"
            >
              <Link
                href={`/spaces/${space.slug}`}
                className="relative block aspect-4/3 overflow-hidden"
              >
                <Image
                  src={space.image}
                  alt={space.name}
                  fill
                  quality={82}
                  sizes="(max-width: 768px) 100vw, 33vw"
                  className="object-cover transition-transform duration-[1.4s] ease-[cubic-bezier(0.16,1,0.3,1)] group-hover:scale-110"
                />
                <div className="absolute inset-0 bg-gradient-to-t from-pine-900/50 to-transparent opacity-70" />
                <span className="absolute left-4 top-4 rounded-full bg-cream-100/90 px-3 py-1 text-[0.68rem] font-medium uppercase tracking-wider text-pine-700 backdrop-blur">
                  {space.age}
                </span>
                <div className="absolute bottom-4 left-5 right-5">
                  <p className="text-xs font-medium uppercase tracking-[0.2em] text-cream/80">
                    {space.kind}
                  </p>
                  <h3 className="font-display text-2xl text-cream">{space.name}</h3>
                </div>
              </Link>

              <div className="flex flex-1 flex-col p-6">
                <p className="text-pretty text-sm leading-relaxed text-ink-soft">{space.blurb}</p>
                <ul className="mt-5 grid grid-cols-2 gap-x-3 gap-y-2">
                  {space.features.map((f) => (
                    <li key={f} className="flex items-center gap-2 text-xs text-stone">
                      <Check className="size-3.5 shrink-0 text-lake" />
                      {f}
                    </li>
                  ))}
                </ul>
                <div className="mt-6 flex flex-1 items-end justify-between gap-3">
                  {space.fromLabel ? (
                    <p className="text-sm font-medium text-pine-700">{space.fromLabel}</p>
                  ) : (
                    <span />
                  )}
                  <Link
                    href={`/spaces/${space.slug}`}
                    className="inline-flex items-center gap-1.5 text-sm font-medium text-pine-700 transition-colors hover:text-amber"
                  >
                    View & book
                    <ArrowUpRight className="size-4 transition-transform duration-300 group-hover:translate-x-0.5 group-hover:-translate-y-0.5" />
                  </Link>
                </div>
              </div>
            </motion.article>
          ))}
        </div>

        {estate ? (
          <Reveal className="mt-6">
            <Link
              href={`/spaces/${estate.slug}`}
              className="group relative block overflow-hidden rounded-3xl shadow-soft transition-all duration-500 hover:shadow-lift hover:-translate-y-1"
            >
              <div className="relative min-h-64">
                <Image
                  src={estate.image}
                  alt={estate.name}
                  fill
                  quality={82}
                  sizes="(max-width: 1152px) 100vw, 1152px"
                  className="object-cover transition-transform duration-[1.4s] ease-[cubic-bezier(0.16,1,0.3,1)] group-hover:scale-105"
                />
                <div className="absolute inset-0 bg-pine-900/65" />
                <div className="absolute inset-0 bg-gradient-to-r from-pine-900/60 to-transparent" />
                <div className="relative z-10 flex flex-col gap-5 p-8 sm:p-10 lg:flex-row lg:items-center lg:justify-between">
                  <div className="max-w-2xl">
                    <p className="inline-flex items-center gap-2 eyebrow text-amber-soft">
                      <KeyRound className="size-3.5" />
                      {estate.kind}
                    </p>
                    <h3 className="mt-3 font-display text-3xl font-light text-cream sm:text-4xl">
                      Take the whole estate
                    </h3>
                    <p className="mt-3 text-pretty text-sm leading-relaxed text-cream/85 sm:text-base">
                      {estate.blurb}
                    </p>
                  </div>
                  <span
                    className={cn(
                      buttonVariants({ variant: "light", size: "lg" }),
                      "shrink-0 self-start lg:self-center"
                    )}
                  >
                    {estate.fromLabel ? `${estate.fromLabel} · ` : ""}View & book
                    <ArrowUpRight className="size-4" />
                  </span>
                </div>
              </div>
            </Link>
          </Reveal>
        ) : null}
      </div>
    </section>
  );
}
