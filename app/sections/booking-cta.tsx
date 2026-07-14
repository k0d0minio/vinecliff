"use client";

import Image from "next/image";
import { useRef } from "react";
import { motion, useScroll, useTransform, useReducedMotion } from "framer-motion";
import { Phone, CalendarHeart } from "lucide-react";
import { site } from "@/lib/site";
import { buttonVariants } from "@/app/components/ui/button";
import { Reveal } from "@/app/components/motion";
import { cn } from "@/lib/utils";

export function BookingCta() {
  const ref = useRef<HTMLDivElement>(null);
  const reduce = useReducedMotion();
  const { scrollYProgress } = useScroll({
    target: ref,
    offset: ["start end", "end start"],
  });
  const y = useTransform(scrollYProgress, [0, 1], [reduce ? "0%" : "-12%", reduce ? "0%" : "12%"]);

  return (
    <section ref={ref} id="book" className="relative overflow-hidden">
      <motion.div style={{ y }} className="absolute inset-0 scale-110 will-change-transform">
        <Image
          src="/img/vinecliff-sign.jpg"
          alt="The Vine Cliff roadside sign against a Lake Erie sunset"
          fill
          quality={85}
          sizes="100vw"
          className="object-cover object-center"
        />
      </motion.div>
      <div className="absolute inset-0 bg-pine-900/70" />
      <div className="absolute inset-0 bg-gradient-to-b from-pine-900/40 via-transparent to-pine-900/70" />

      <div className="relative z-10 mx-auto flex max-w-3xl flex-col items-center px-5 py-28 text-center sm:px-8 sm:py-36">
        <Reveal>
          <span className="inline-flex items-center gap-2 rounded-full border border-cream/25 bg-cream/10 px-4 py-1.5 text-xs font-medium uppercase tracking-[0.2em] text-cream backdrop-blur">
            <CalendarHeart className="size-3.5" />
            Online booking coming soon
          </span>
        </Reveal>
        <Reveal delay={0.1}>
          <h2 className="mt-7 font-display text-4xl font-light leading-[1.05] text-cream text-balance sm:text-6xl">
            Reserve your season by the lake
          </h2>
        </Reveal>
        <Reveal delay={0.2}>
          <p className="mx-auto mt-6 max-w-xl text-pretty text-base leading-relaxed text-cream/85 sm:text-lg">
            Weeks and weekends fill quickly, and event dates even faster. Get in touch to check
            availability and hold your dates at Vine Cliff.
          </p>
        </Reveal>
        <Reveal delay={0.3}>
          <div className="mt-10 flex flex-col items-center gap-3 sm:flex-row">
            <a href={site.phoneHref} className={cn(buttonVariants({ variant: "amber", size: "lg" }))}>
              <Phone className="size-4" />
              {site.phone}
            </a>
            <a
              href={`mailto:${site.email}`}
              className={cn(buttonVariants({ variant: "light", size: "lg" }))}
            >
              Send an enquiry
            </a>
          </div>
        </Reveal>
      </div>
    </section>
  );
}
