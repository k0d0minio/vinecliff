// Quote calculation. Money is integer cents throughout; formatting happens at
// the edge. Weekly rates apply per full 7-night block with the remainder at
// the nightly rate — the standard vacation-rental convention.
import { diffDays, type ISODate } from "./dates";

export type SpacePricing = {
  isEvent: boolean;
  nightlyRateCents: number;
  weeklyRateCents: number | null;
  cleaningFeeCents: number;
};

export type QuoteLine = { label: string; amountCents: number };

export type Quote = {
  /** Nights for stays; event days for event spaces. */
  nights: number;
  lines: QuoteLine[];
  totalCents: number;
};

export function formatMoney(cents: number): string {
  const dollars = cents / 100;
  return new Intl.NumberFormat("en-US", {
    style: "currency",
    currency: "USD",
    minimumFractionDigits: Number.isInteger(dollars) ? 0 : 2,
    maximumFractionDigits: 2,
  }).format(dollars);
}

/** "night" / "nights" for stays, "day" / "days" for event spaces. */
export function unitLabel(space: { isEvent: boolean }, count: number): string {
  const unit = space.isEvent ? "day" : "night";
  return count === 1 ? unit : `${unit}s`;
}

export function computeQuote(
  space: SpacePricing,
  startDate: ISODate,
  endDate: ISODate
): Quote {
  const nights = Math.max(0, diffDays(startDate, endDate));
  const lines: QuoteLine[] = [];

  if (space.weeklyRateCents && nights >= 7) {
    const weeks = Math.floor(nights / 7);
    const remainder = nights % 7;
    lines.push({
      label: `${weeks} ${weeks === 1 ? "week" : "weeks"} × ${formatMoney(space.weeklyRateCents)}`,
      amountCents: weeks * space.weeklyRateCents,
    });
    if (remainder > 0) {
      lines.push({
        label: `${remainder} ${unitLabel(space, remainder)} × ${formatMoney(space.nightlyRateCents)}`,
        amountCents: remainder * space.nightlyRateCents,
      });
    }
  } else if (nights > 0) {
    lines.push({
      label: `${nights} ${unitLabel(space, nights)} × ${formatMoney(space.nightlyRateCents)}`,
      amountCents: nights * space.nightlyRateCents,
    });
  }

  if (nights > 0 && space.cleaningFeeCents > 0) {
    lines.push({ label: "Cleaning & turnover", amountCents: space.cleaningFeeCents });
  }

  return {
    nights,
    lines,
    totalCents: lines.reduce((sum, line) => sum + line.amountCents, 0),
  };
}
