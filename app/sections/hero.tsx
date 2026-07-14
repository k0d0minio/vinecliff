"use client";

import Image from "next/image";
import { useRef } from "react";
import { motion, useScroll, useTransform, useReducedMotion } from "framer-motion";
import { ArrowRight, ChevronDown } from "lucide-react";
import { AnimatedWords } from "@/app/components/motion";
import { buttonVariants } from "@/app/components/ui/button";
import { cn } from "@/lib/utils";

export function Hero() {
  const ref = useRef<HTMLDivElement>(null);
  const reduce = useReducedMotion();
  const { scrollYProgress } = useScroll({
    target: ref,
    offset: ["start start", "end start"],
  });
  const y = useTransform(scrollYProgress, [0, 1], ["0%", reduce ? "0%" : "22%"]);
  const scale = useTransform(scrollYProgress, [0, 1], [1, reduce ? 1 : 1.12]);
  const overlayOpacity = useTransform(scrollYProgress, [0, 1], [1, 0.4]);
  const contentY = useTransform(scrollYProgress, [0, 1], ["0%", reduce ? "0%" : "40%"]);
  const contentOpacity = useTransform(scrollYProgress, [0, 0.6], [1, 0]);

  return (
    <section ref={ref} id="top" className="relative h-[100svh] min-h-[640px] w-full overflow-hidden">
      <motion.div style={{ y, scale }} className="absolute inset-0 will-change-transform">
        <Image
          src="/img/aerial-shot.jpg"
          alt="Aerial view of the Vine Cliff estate on the cliffs above the turquoise waters of Lake Erie"
          fill
          priority
          quality={90}
          sizes="100vw"
          className="object-cover object-center"
        />
      </motion.div>

      {/* Layered gradients for depth + legibility */}
      <motion.div
        style={{ opacity: overlayOpacity }}
        className="absolute inset-0 bg-gradient-to-b from-pine-900/55 via-pine-900/25 to-pine-900/80"
      />
      <div className="absolute inset-0 bg-gradient-to-t from-cream via-transparent to-transparent opacity-90" />

      <motion.div
        style={{ y: contentY, opacity: contentOpacity }}
        className="relative z-10 mx-auto flex h-full max-w-6xl flex-col items-start justify-center px-5 sm:px-8"
      >
        <motion.p
          initial={{ opacity: 0, y: 12 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ duration: 0.8, delay: 0.3 }}
          className="eyebrow text-cream/85"
        >
          On the shores of Lake Erie · New York
        </motion.p>

        <h1 className="mt-5 max-w-3xl font-display text-[2.75rem] font-light leading-[1.02] text-cream text-balance sm:text-6xl lg:text-7xl">
          <AnimatedWords text="A country estate" delay={0.4} />{" "}
          <br className="hidden sm:block" />
          <span className="italic text-amber-soft">
            <AnimatedWords text="made for gathering" delay={0.7} />
          </span>
        </h1>

        <motion.p
          initial={{ opacity: 0, y: 16 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ duration: 0.9, delay: 1.1 }}
          className="mt-6 max-w-xl text-pretty text-base leading-relaxed text-cream/85 sm:text-lg"
        >
          Weekly, weekend and event stays across a farmhouse, carriage house and barn — each
          over 170 years old — set amid vineyards and cliff-top sunsets.
        </motion.p>

        <motion.div
          initial={{ opacity: 0, y: 16 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ duration: 0.9, delay: 1.3 }}
          className="mt-9 flex flex-col gap-3 sm:flex-row sm:items-center"
        >
          <a href="#spaces" className={cn(buttonVariants({ variant: "amber", size: "lg" }))}>
            Explore the spaces
            <ArrowRight className="size-4" />
          </a>
          <a href="#location" className={cn(buttonVariants({ variant: "light", size: "lg" }))}>
            Plan an event
          </a>
        </motion.div>
      </motion.div>

      <motion.a
        href="#estate"
        aria-label="Scroll to explore"
        initial={{ opacity: 0 }}
        animate={{ opacity: 1 }}
        transition={{ delay: 1.6, duration: 1 }}
        className="absolute bottom-7 left-1/2 z-10 -translate-x-1/2 text-cream/70"
      >
        <motion.span
          animate={{ y: [0, 8, 0] }}
          transition={{ duration: 2, repeat: Infinity, ease: "easeInOut" }}
          className="block"
        >
          <ChevronDown className="size-6" />
        </motion.span>
      </motion.a>
    </section>
  );
}
