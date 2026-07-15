import type { ReactNode } from "react";
import type { LucideIcon } from "lucide-react";

export function PageHeader({
  title,
  description,
  actions,
}: {
  title: string;
  description?: string;
  actions?: ReactNode;
}) {
  return (
    <div className="flex flex-col gap-4 sm:flex-row sm:items-end sm:justify-between">
      <div>
        <h1 className="font-display text-2xl text-ink sm:text-3xl">{title}</h1>
        {description ? (
          <p className="mt-1.5 max-w-2xl text-sm text-ink-soft">{description}</p>
        ) : null}
      </div>
      {actions ? <div className="flex shrink-0 gap-3">{actions}</div> : null}
    </div>
  );
}

/** A soft, bordered surface — the base building block for admin content. */
export function Card({
  children,
  className,
}: {
  children: ReactNode;
  className?: string;
}) {
  return (
    <div
      className={`rounded-2xl border border-pine-100 bg-cream-100 p-5 sm:p-6 ${className ?? ""}`}
    >
      {children}
    </div>
  );
}

/**
 * A friendly "nothing here yet" panel. Used across the section until each page
 * is wired to real data.
 */
export function EmptyState({
  icon: Icon,
  title,
  description,
}: {
  icon: LucideIcon;
  title: string;
  description: string;
}) {
  return (
    <div className="flex flex-col items-center justify-center rounded-2xl border border-dashed border-pine-100 bg-cream-100 px-6 py-16 text-center">
      <div className="flex size-12 items-center justify-center rounded-2xl bg-pine-50 text-pine-600">
        <Icon className="size-6" />
      </div>
      <p className="mt-4 font-display text-lg text-ink">{title}</p>
      <p className="mt-1 max-w-sm text-sm text-ink-soft">{description}</p>
    </div>
  );
}
