// Calendar-date helpers for the booking system.
//
// All booking dates are plain "YYYY-MM-DD" strings in the estate's local
// calendar (America/New_York) — never Date objects with timezones attached.
// Every helper anchors math at UTC midnight so a date is the same date
// everywhere, and ISO strings compare correctly with plain `<`/`>`.
//
// Ranges are half-open [startDate, endDate): endDate is the checkout day, so
// a stay that ends on the 8th and one that starts on the 8th do not overlap.

export type ISODate = string;

const DAY_MS = 86_400_000;

export function isValidISODate(value: unknown): value is ISODate {
  if (typeof value !== "string" || !/^\d{4}-\d{2}-\d{2}$/.test(value)) {
    return false;
  }
  const parsed = new Date(`${value}T00:00:00Z`);
  // Round-trip to reject impossible dates like 2026-02-31.
  return !Number.isNaN(parsed.getTime()) && parsed.toISOString().slice(0, 10) === value;
}

export function parseISO(date: ISODate): Date {
  return new Date(`${date}T00:00:00Z`);
}

export function toISO(date: Date): ISODate {
  return date.toISOString().slice(0, 10);
}

export function addDays(date: ISODate, days: number): ISODate {
  return toISO(new Date(parseISO(date).getTime() + days * DAY_MS));
}

/** Add calendar months, clamping to the last day of the target month. */
export function addMonths(date: ISODate, months: number): ISODate {
  const d = parseISO(date);
  const target = new Date(
    Date.UTC(d.getUTCFullYear(), d.getUTCMonth() + months, d.getUTCDate())
  );
  if (target.getUTCDate() !== d.getUTCDate()) target.setUTCDate(0);
  return toISO(target);
}

/** Whole days from `a` to `b` — the number of nights in a stay [a, b). */
export function diffDays(a: ISODate, b: ISODate): number {
  return Math.round((parseISO(b).getTime() - parseISO(a).getTime()) / DAY_MS);
}

/** Half-open range overlap: [aStart, aEnd) ∩ [bStart, bEnd) ≠ ∅. */
export function rangesOverlap(
  aStart: ISODate,
  aEnd: ISODate,
  bStart: ISODate,
  bEnd: ISODate
): boolean {
  return aStart < bEnd && bStart < aEnd;
}

/** Today as a calendar date at the estate (America/New_York). */
export function todayAtEstate(): ISODate {
  // en-CA formats as YYYY-MM-DD.
  return new Intl.DateTimeFormat("en-CA", {
    timeZone: "America/New_York",
  }).format(new Date());
}

/** "Fri, Jun 5, 2026" */
export function formatDate(date: ISODate): string {
  return new Intl.DateTimeFormat("en-US", {
    weekday: "short",
    month: "short",
    day: "numeric",
    year: "numeric",
    timeZone: "UTC",
  }).format(parseISO(date));
}

/** "Jun 5" — compact, for calendars and dense lists. */
export function formatDayMonth(date: ISODate): string {
  return new Intl.DateTimeFormat("en-US", {
    month: "short",
    day: "numeric",
    timeZone: "UTC",
  }).format(parseISO(date));
}

/** "June 2026" — month headings. */
export function formatMonth(date: ISODate): string {
  return new Intl.DateTimeFormat("en-US", {
    month: "long",
    year: "numeric",
    timeZone: "UTC",
  }).format(parseISO(date));
}

/**
 * Display a stay range. The half-open endDate is shown as-is because guests
 * read it as their checkout day ("Jun 5 – Jun 8" = arrive the 5th, leave the
 * 8th). For event spaces the last *included* day is endDate − 1.
 */
export function formatRange(startDate: ISODate, endDate: ISODate): string {
  return `${formatDate(startDate)} → ${formatDate(endDate)}`;
}
