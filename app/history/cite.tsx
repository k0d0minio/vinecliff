import { cn } from "@/lib/utils";

/**
 * Inline footnote marker. Renders one or more superscript numbers that link
 * down to the matching entries in the Sources section. Server-safe.
 */
export function Cite({ n, className }: { n: number | number[]; className?: string }) {
  const nums = Array.isArray(n) ? n : [n];
  return (
    <sup className={cn("ml-0.5 inline-flex gap-0.5 align-super text-[0.6em]", className)}>
      {nums.map((num, i) => (
        <span key={num}>
          <a
            href={`#source-${num}`}
            id={`ref-${num}`}
            className="font-medium text-amber underline-offset-2 hover:underline"
            aria-label={`Jump to source ${num}`}
          >
            {num}
          </a>
          {i < nums.length - 1 && <span className="text-stone">,</span>}
        </span>
      ))}
    </sup>
  );
}
