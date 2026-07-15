// The availability engine — pure functions, no database access, so the same
// rules run in server actions, route handlers, unit tests and (for calendar
// rendering) client components.
//
// The model: spaces are open by default. A date is unavailable when it falls
// inside a blocked range, which come from two sources:
//
//   1. Approved bookings. A booking blocks its own space (padded by the
//      space's turnover buffer on both sides), and — when it has
//      `blocksEstate` (weddings, whole-estate hire) — every other space too.
//      Symmetrically, a space with `blocksEstate` (the barn, the estate
//      package) needs the entire property free, so *any* approved booking
//      anywhere blocks it.
//   2. Blackouts. A blackout blocks its own space, or every space when its
//      spaceId is null. Estate-wide spaces are blocked by any blackout —
//      you can't promise the whole property while a building is closed.
//
// Pending requests never block anything; only approval claims dates.
import {
  addDays,
  addMonths,
  diffDays,
  isValidISODate,
  rangesOverlap,
  type ISODate,
} from "./dates";

export type SpaceRules = {
  id: string;
  isEvent: boolean;
  blocksEstate: boolean;
  minNights: number;
  maxGuests: number;
  bufferDays: number;
  minLeadDays: number;
  maxHorizonMonths: number;
};

export type BookingBlock = {
  spaceId: string;
  startDate: ISODate;
  endDate: ISODate;
  blocksEstate: boolean;
};

export type BlackoutBlock = {
  /** null = blocks every space. */
  spaceId: string | null;
  startDate: ISODate;
  endDate: ISODate;
};

export type DateRange = { startDate: ISODate; endDate: ISODate };

/** All ranges within which `space` cannot be booked. Not merged or sorted. */
export function blockedRanges(
  space: SpaceRules,
  bookings: BookingBlock[],
  blackouts: BlackoutBlock[]
): DateRange[] {
  const ranges: DateRange[] = [];

  for (const booking of bookings) {
    const ownBooking = booking.spaceId === space.id;
    if (!ownBooking && !booking.blocksEstate && !space.blocksEstate) continue;
    // Turnover buffer is a per-unit cleaning concern, so it only pads
    // same-space bookings; estate-wide blocks use their exact range.
    const buffer = ownBooking ? space.bufferDays : 0;
    ranges.push({
      startDate: addDays(booking.startDate, -buffer),
      endDate: addDays(booking.endDate, buffer),
    });
  }

  for (const blackout of blackouts) {
    const applies =
      blackout.spaceId === null ||
      blackout.spaceId === space.id ||
      space.blocksEstate;
    if (!applies) continue;
    ranges.push({ startDate: blackout.startDate, endDate: blackout.endDate });
  }

  return ranges;
}

/**
 * The window of bookable start days given lead time and horizon.
 * `firstStart` is the earliest allowed check-in; `lastEnd` the latest allowed
 * checkout (exclusive bound of the whole window).
 */
export function bookingWindow(
  space: Pick<SpaceRules, "minLeadDays" | "maxHorizonMonths">,
  today: ISODate
): { firstStart: ISODate; lastEnd: ISODate } {
  return {
    firstStart: addDays(today, space.minLeadDays),
    lastEnd: addMonths(today, space.maxHorizonMonths),
  };
}

export function isDateBlocked(date: ISODate, ranges: DateRange[]): boolean {
  return ranges.some((r) => date >= r.startDate && date < r.endDate);
}

export type ValidationResult = { ok: true } | { ok: false; error: string };

/**
 * Full server-side validation of a booking request. The client enforces the
 * same rules for UX, but this is the authority — it runs again inside the
 * server action with fresh data before anything is written.
 */
export function validateRequest(options: {
  space: SpaceRules;
  startDate: ISODate;
  endDate: ISODate;
  partySize: number;
  today: ISODate;
  bookings: BookingBlock[];
  blackouts: BlackoutBlock[];
}): ValidationResult {
  const { space, startDate, endDate, partySize, today } = options;
  const noun = space.isEvent ? "day" : "night";

  if (!isValidISODate(startDate) || !isValidISODate(endDate)) {
    return { ok: false, error: "Please pick valid dates." };
  }
  if (endDate <= startDate) {
    return {
      ok: false,
      error: space.isEvent
        ? "The last day must be on or after the first day."
        : "Checkout must be after check-in.",
    };
  }

  const nights = diffDays(startDate, endDate);
  if (nights < space.minNights) {
    return {
      ok: false,
      error: `This space has a ${space.minNights}-${noun} minimum.`,
    };
  }

  if (!Number.isInteger(partySize) || partySize < 1) {
    return { ok: false, error: "Please tell us how many guests are coming." };
  }
  if (partySize > space.maxGuests) {
    return {
      ok: false,
      error: `This space hosts up to ${space.maxGuests} guests.`,
    };
  }

  const window = bookingWindow(space, today);
  if (startDate < window.firstStart) {
    return {
      ok: false,
      error: `Requests need at least ${space.minLeadDays} days' notice — call us for last-minute dates.`,
    };
  }
  if (endDate > window.lastEnd) {
    return {
      ok: false,
      error: `We're taking requests up to ${space.maxHorizonMonths} months out for now.`,
    };
  }

  const blocked = blockedRanges(space, options.bookings, options.blackouts);
  const conflict = blocked.some((r) =>
    rangesOverlap(startDate, endDate, r.startDate, r.endDate)
  );
  if (conflict) {
    return {
      ok: false,
      error:
        "Some of those dates are no longer available — please pick different dates.",
    };
  }

  return { ok: true };
}
