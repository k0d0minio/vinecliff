"use client";

import Image from "next/image";
import { motion, useReducedMotion } from "framer-motion";
import { ArrowUpRight, Check } from "lucide-react";
import { spaces } from "@/lib/site";
import { Reveal } from "@/app/components/motion";
import { useInViewOnce } from "@/app/components/use-in-view";

const EASE = [0.16, 1, 0.3, 1] as const;

export function Spaces() {
  const reduce = useReducedMotion();
  const { ref, inView } = useInViewOnce();

  return (
    <section id="spaces" className="relative bg-parchment/60 py-24 sm:py-32">
      <div className="mx-auto max-w-6xl px-5 sm:px-8">
        <Reveal className="max-w-2xl">
          <p className="eyebrow text-amber">Stay & Celebrate</p>
          <h2 className="mt-4 font-display text-4xl font-light leading-tight text-pine-900 text-balance sm:text-5xl">
            Three spaces, one storied estate
          </h2>
          <p className="mt-5 text-pretty text-base leading-relaxed text-ink-soft sm:text-lg">
            Each building carries its own character. Book one for an intimate escape — or the whole
            grounds for a wedding, reunion or retreat.
          </p>
        </Reveal>

        <div ref={ref} className="mt-14 grid gap-6 md:grid-cols-3">
          {spaces.map((space, i) => (
            <motion.article
              key={space.id}
              id={space.id}
              initial={reduce ? { opacity: 0 } : { opacity: 0, y: 40 }}
              animate={inView ? { opacity: 1, y: 0 } : undefined}
              transition={{ duration: 0.8, ease: EASE, delay: i * 0.12 }}
              className="group relative flex flex-col overflow-hidden rounded-3xl bg-cream-100 shadow-soft transition-all duration-500 hover:shadow-lift hover:-translate-y-1.5"
            >
              <div className="relative aspect-4/3 overflow-hidden">
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
              </div>

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
                <a
                  href="#location"
                  className="mt-6 inline-flex items-center gap-1.5 text-sm font-medium text-pine-700 transition-colors hover:text-amber"
                >
                  Enquire about {space.name.replace("The ", "")}
                  <ArrowUpRight className="size-4 transition-transform duration-300 group-hover:translate-x-0.5 group-hover:-translate-y-0.5" />
                </a>
              </div>
            </motion.article>
          ))}
        </div>
      </div>
    </section>
  );
}
