"use client";

import { useEffect, useState } from "react";
import { usePathname } from "next/navigation";
import { AnimatePresence, motion } from "framer-motion";
import { Menu, X, Phone } from "lucide-react";
import { cn } from "@/lib/utils";
import { site } from "@/lib/site";
import { buttonVariants } from "./ui/button";

// Section anchors live on the home page. `hash` is prefixed with "/" when the
// nav is rendered on a sub-page so the links jump back to the landing page.
const sectionLinks = [
  { hash: "#spaces", label: "The Spaces" },
  { hash: "#estate", label: "The Estate" },
  { hash: "#gallery", label: "Gallery" },
  { hash: "#location", label: "Location" },
];

export function Nav() {
  const [scrolled, setScrolled] = useState(false);
  const [open, setOpen] = useState(false);
  const pathname = usePathname();
  const onHome = pathname === "/";

  const sectionHref = (hash: string) => (onHome ? hash : `/${hash}`);
  const links = [
    ...sectionLinks.map((l) => ({ href: sectionHref(l.hash), label: l.label })),
    { href: "/history", label: "History" },
  ];
  const homeHref = onHome ? "#top" : "/";

  useEffect(() => {
    const onScroll = () => setScrolled(window.scrollY > 24);
    onScroll();
    window.addEventListener("scroll", onScroll, { passive: true });
    return () => window.removeEventListener("scroll", onScroll);
  }, []);

  useEffect(() => {
    document.body.style.overflow = open ? "hidden" : "";
    return () => {
      document.body.style.overflow = "";
    };
  }, [open]);

  return (
    <motion.header
      initial={{ y: -80, opacity: 0 }}
      animate={{ y: 0, opacity: 1 }}
      transition={{ duration: 0.8, ease: [0.16, 1, 0.3, 1], delay: 0.2 }}
      className="fixed inset-x-0 top-0 z-50"
    >
      <div
        className={cn(
          "transition-all duration-500",
          scrolled
            ? "bg-cream/85 backdrop-blur-md shadow-[0_1px_0_rgba(35,39,29,0.08)]"
            : "bg-transparent"
        )}
      >
        <nav className="mx-auto flex h-16 max-w-6xl items-center justify-between px-5 sm:h-20 sm:px-8">
          <a
            href={homeHref}
            className={cn(
              "font-display text-xl font-medium tracking-tight transition-colors sm:text-2xl",
              scrolled ? "text-pine-900" : "text-cream"
            )}
          >
            Vine&nbsp;Cliff
            <span
              className={cn(
                "ml-2 hidden align-middle text-[0.6rem] uppercase tracking-[0.28em] sm:inline",
                scrolled ? "text-stone" : "text-cream/70"
              )}
            >
              Est. 1850
            </span>
          </a>

          <div className="hidden items-center gap-8 md:flex">
            {links.map((l) => (
              <a
                key={l.href}
                href={l.href}
                className={cn(
                  "group relative text-sm font-medium transition-colors",
                  scrolled ? "text-ink-soft hover:text-pine-700" : "text-cream/85 hover:text-cream"
                )}
              >
                {l.label}
                <span className="absolute -bottom-1 left-0 h-px w-0 bg-current transition-all duration-300 group-hover:w-full" />
              </a>
            ))}
            <a
              href={site.phoneHref}
              className={cn(
                buttonVariants({ variant: scrolled ? "primary" : "light", size: "sm" })
              )}
            >
              <Phone className="size-3.5" />
              Enquire
            </a>
          </div>

          <button
            aria-label="Open menu"
            onClick={() => setOpen(true)}
            className={cn(
              "md:hidden",
              scrolled ? "text-pine-900" : "text-cream"
            )}
          >
            <Menu className="size-6" />
          </button>
        </nav>
      </div>

      <AnimatePresence>
        {open && (
          <motion.div
            initial={{ opacity: 0 }}
            animate={{ opacity: 1 }}
            exit={{ opacity: 0 }}
            transition={{ duration: 0.3 }}
            className="fixed inset-0 z-50 bg-pine-900/98 backdrop-blur-sm md:hidden"
          >
            <div className="flex h-16 items-center justify-between px-5 sm:h-20">
              <span className="font-display text-xl text-cream">Vine Cliff</span>
              <button aria-label="Close menu" onClick={() => setOpen(false)} className="text-cream">
                <X className="size-6" />
              </button>
            </div>
            <motion.ul
              initial="hidden"
              animate="show"
              variants={{ show: { transition: { staggerChildren: 0.08, delayChildren: 0.1 } } }}
              className="flex flex-col gap-2 px-6 pt-8"
            >
              {links.map((l) => (
                <motion.li
                  key={l.href}
                  variants={{
                    hidden: { opacity: 0, x: -20 },
                    show: { opacity: 1, x: 0, transition: { duration: 0.5, ease: [0.16, 1, 0.3, 1] } },
                  }}
                >
                  <a
                    href={l.href}
                    onClick={() => setOpen(false)}
                    className="block border-b border-cream/10 py-4 font-display text-3xl text-cream"
                  >
                    {l.label}
                  </a>
                </motion.li>
              ))}
            </motion.ul>
            <div className="px-6 pt-10">
              <a
                href={site.phoneHref}
                onClick={() => setOpen(false)}
                className={cn(buttonVariants({ variant: "amber", size: "lg" }), "w-full")}
              >
                <Phone className="size-4" />
                Call to enquire
              </a>
            </div>
          </motion.div>
        )}
      </AnimatePresence>
    </motion.header>
  );
}
