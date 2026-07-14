"use client";

import Image from "next/image";
import { motion, useReducedMotion } from "framer-motion";
import { gallery } from "@/lib/site";
import { Reveal } from "@/app/components/motion";
import { useInViewOnce } from "@/app/components/use-in-view";

const EASE = [0.16, 1, 0.3, 1] as const;

export function Gallery() {
  const reduce = useReducedMotion();
  const { ref, inView } = useInViewOnce();

  return (
    <section id="gallery" className="relative overflow-hidden bg-pine-900 py-24 sm:py-32">
      <div className="mx-auto max-w-6xl px-5 sm:px-8">
        <Reveal className="max-w-2xl">
          <p className="eyebrow text-amber-soft">Gallery</p>
          <h2 className="mt-4 font-display text-4xl font-light leading-tight text-cream text-balance sm:text-5xl">
            A place that changes with the light
          </h2>
          <p className="mt-5 text-pretty text-base leading-relaxed text-cream/70 sm:text-lg">
            From crisp autumn mornings on the porch to golden hour over the water — a look around the
            grounds.
          </p>
        </Reveal>

        <div ref={ref} className="mt-14 grid grid-cols-2 gap-3 sm:gap-4 lg:grid-cols-4">
          {gallery.map((img, i) => (
            <motion.figure
              key={img.src}
              initial={reduce ? { opacity: 0 } : { opacity: 0, y: 30 }}
              animate={inView ? { opacity: 1, y: 0 } : undefined}
              transition={{ duration: 0.7, ease: EASE, delay: (i % 4) * 0.08 }}
              className={`group relative overflow-hidden rounded-2xl ${
                "span" in img && img.span === "wide"
                  ? "col-span-2 aspect-16/10"
                  : "aspect-square"
              }`}
            >
              <Image
                src={img.src}
                alt={img.alt}
                fill
                quality={80}
                sizes="(max-width: 640px) 50vw, (max-width: 1024px) 50vw, 25vw"
                className="object-cover transition-transform duration-[1.5s] ease-[cubic-bezier(0.16,1,0.3,1)] group-hover:scale-[1.08]"
              />
              <div className="absolute inset-0 bg-gradient-to-t from-pine-900/60 via-transparent to-transparent opacity-0 transition-opacity duration-500 group-hover:opacity-100" />
              <figcaption className="absolute inset-x-0 bottom-0 translate-y-3 p-4 text-xs text-cream/90 opacity-0 transition-all duration-500 group-hover:translate-y-0 group-hover:opacity-100">
                {img.alt}
              </figcaption>
            </motion.figure>
          ))}
        </div>
      </div>
    </section>
  );
}
