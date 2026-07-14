"use client";

import { useEffect, useRef, useState } from "react";

/**
 * Minimal, dependable IntersectionObserver hook.
 * Triggers once when the element scrolls into view.
 */
export function useInViewOnce<T extends HTMLElement = HTMLDivElement>(
  options: { rootMargin?: string; amount?: number } = {}
) {
  const ref = useRef<T>(null);
  const [inView, setInView] = useState(false);

  useEffect(() => {
    const el = ref.current;
    if (!el || inView) return;

    // Fallback: if IntersectionObserver is unavailable, show immediately.
    if (typeof IntersectionObserver === "undefined") {
      setInView(true);
      return;
    }

    const observer = new IntersectionObserver(
      (entries) => {
        for (const entry of entries) {
          if (entry.isIntersecting) {
            setInView(true);
            observer.disconnect();
            break;
          }
        }
      },
      {
        rootMargin: options.rootMargin ?? "0px 0px -12% 0px",
        threshold: options.amount ?? 0.15,
      }
    );

    observer.observe(el);
    return () => observer.disconnect();
  }, [inView, options.rootMargin, options.amount]);

  return { ref, inView };
}
