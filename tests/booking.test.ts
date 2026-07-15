// Unit tests for the booking domain logic (dates, pricing, availability).
// Run with: npm test
import assert from "node:assert/strict";
import { describe, it } from "node:test";
import {
  addDays,
  addMonths,
  diffDays,
  isValidISODate,
  rangesOverlap,
} from "../lib/booking/dates";
import { computeQuote, formatMoney } from "../lib/booking/pricing";
import {
  blockedRanges,
  bookingWindow,
  isDateBlocked,
  validateRequest,
  type BlackoutBlock,
  type BookingBlock,
  type SpaceRules,
} from "../lib/booking/availability";

describe("dates", () => {
  it("validates ISO dates including impossible calendar days", () => {
    assert.equal(isValidISODate("2026-06-05"), true);
    assert.equal(isValidISODate("2026-02-31"), false);
    assert.equal(isValidISODate("2026-6-5"), false);
    assert.equal(isValidISODate("nonsense"), false);
  });

  it("adds days across month and year boundaries", () => {
    assert.equal(addDays("2026-12-30", 3), "2027-01-02");
    assert.equal(addDays("2026-03-01", -1), "2026-02-28");
  });

  it("adds months with end-of-month clamping", () => {
    assert.equal(addMonths("2026-01-31", 1), "2026-02-28");
    assert.equal(addMonths("2026-07-15", 18), "2028-01-15");
  });

  it("counts nights as half-open ranges", () => {
    assert.equal(diffDays("2026-06-05", "2026-06-08"), 3);
    assert.equal(diffDays("2026-06-05", "2026-06-05"), 0);
  });

  it("treats back-to-back half-open ranges as non-overlapping", () => {
    assert.equal(rangesOverlap("2026-06-05", "2026-06-08", "2026-06-08", "2026-06-10"), false);
    assert.equal(rangesOverlap("2026-06-05", "2026-06-08", "2026-06-07", "2026-06-10"), true);
    assert.equal(rangesOverlap("2026-06-05", "2026-06-08", "2026-06-01", "2026-06-06"), true);
  });
});

describe("pricing", () => {
  const farmhouse = {
    isEvent: false,
    nightlyRateCents: 45000,
    weeklyRateCents: 275000,
    cleaningFeeCents: 15000,
  };

  it("prices a short stay at the nightly rate plus cleaning", () => {
    const quote = computeQuote(farmhouse, "2026-06-05", "2026-06-08");
    assert.equal(quote.nights, 3);
    assert.equal(quote.totalCents, 3 * 45000 + 15000);
    assert.equal(quote.lines.length, 2);
    assert.match(quote.lines[0].label, /3 nights × \$450/);
  });

  it("applies the weekly rate per full week with nightly remainder", () => {
    const quote = computeQuote(farmhouse, "2026-06-01", "2026-06-11");
    assert.equal(quote.nights, 10);
    assert.equal(quote.totalCents, 275000 + 3 * 45000 + 15000);
    assert.match(quote.lines[0].label, /1 week × \$2,750/);
    assert.match(quote.lines[1].label, /3 nights/);
  });

  it("speaks in days for event spaces and skips absent fees", () => {
    const barn = {
      isEvent: true,
      nightlyRateCents: 250000,
      weeklyRateCents: null,
      cleaningFeeCents: 0,
    };
    const quote = computeQuote(barn, "2026-09-04", "2026-09-05");
    assert.equal(quote.nights, 1);
    assert.equal(quote.totalCents, 250000);
    assert.equal(quote.lines.length, 1);
    assert.match(quote.lines[0].label, /1 day × \$2,500/);
  });

  it("formats money without cents when whole", () => {
    assert.equal(formatMoney(275000), "$2,750");
    assert.equal(formatMoney(123456), "$1,234.56");
  });
});

const farmhouseRules: SpaceRules = {
  id: "farmhouse-id",
  isEvent: false,
  blocksEstate: false,
  minNights: 2,
  maxGuests: 10,
  bufferDays: 1,
  minLeadDays: 2,
  maxHorizonMonths: 18,
};

const barnRules: SpaceRules = {
  ...farmhouseRules,
  id: "barn-id",
  isEvent: true,
  blocksEstate: true,
  minNights: 1,
  maxGuests: 150,
  minLeadDays: 14,
};

describe("availability", () => {
  const farmhouseBooking: BookingBlock = {
    spaceId: "farmhouse-id",
    startDate: "2026-06-05",
    endDate: "2026-06-08",
    blocksEstate: false,
  };
  const wedding: BookingBlock = {
    spaceId: "barn-id",
    startDate: "2026-07-10",
    endDate: "2026-07-12",
    blocksEstate: true,
  };

  it("pads same-space bookings with the turnover buffer", () => {
    const ranges = blockedRanges(farmhouseRules, [farmhouseBooking], []);
    assert.deepEqual(ranges, [{ startDate: "2026-06-04", endDate: "2026-06-09" }]);
  });

  it("blocks every space during estate-blocking bookings, unbuffered", () => {
    const ranges = blockedRanges(farmhouseRules, [wedding], []);
    assert.deepEqual(ranges, [{ startDate: "2026-07-10", endDate: "2026-07-12" }]);
  });

  it("blocks estate-wide spaces whenever anything is booked", () => {
    const ranges = blockedRanges(barnRules, [farmhouseBooking], []);
    assert.deepEqual(ranges, [{ startDate: "2026-06-05", endDate: "2026-06-08" }]);
  });

  it("ignores unrelated bookings for independent spaces", () => {
    const carriage: BookingBlock = { ...farmhouseBooking, spaceId: "carriage-id" };
    assert.deepEqual(blockedRanges(farmhouseRules, [carriage], []), []);
  });

  it("applies blackouts to their space, estate-wide when spaceId is null", () => {
    const own: BlackoutBlock = { spaceId: "farmhouse-id", startDate: "2026-08-01", endDate: "2026-08-05" };
    const estateWide: BlackoutBlock = { spaceId: null, startDate: "2026-11-01", endDate: "2027-04-01" };
    const other: BlackoutBlock = { spaceId: "carriage-id", startDate: "2026-09-01", endDate: "2026-09-03" };
    const ranges = blockedRanges(farmhouseRules, [], [own, estateWide, other]);
    assert.equal(ranges.length, 2);
    // ...but an estate-wide space is blocked by any building's blackout.
    assert.equal(blockedRanges(barnRules, [], [other]).length, 1);
  });

  it("computes the bookable window from lead time and horizon", () => {
    const window = bookingWindow(farmhouseRules, "2026-07-15");
    assert.equal(window.firstStart, "2026-07-17");
    assert.equal(window.lastEnd, "2028-01-15");
  });

  it("flags blocked days for calendars", () => {
    const ranges = blockedRanges(farmhouseRules, [farmhouseBooking], []);
    assert.equal(isDateBlocked("2026-06-04", ranges), true); // buffer day
    assert.equal(isDateBlocked("2026-06-09", ranges), false);
  });
});

describe("validateRequest", () => {
  const base = {
    space: farmhouseRules,
    today: "2026-07-15",
    bookings: [] as BookingBlock[],
    blackouts: [] as BlackoutBlock[],
    partySize: 4,
  };

  it("accepts a clean request", () => {
    const result = validateRequest({ ...base, startDate: "2026-08-10", endDate: "2026-08-14" });
    assert.deepEqual(result, { ok: true });
  });

  it("rejects inverted and too-short stays", () => {
    assert.equal(
      validateRequest({ ...base, startDate: "2026-08-14", endDate: "2026-08-10" }).ok,
      false
    );
    const short = validateRequest({ ...base, startDate: "2026-08-10", endDate: "2026-08-11" });
    assert.equal(short.ok, false);
    assert.match((short as { error: string }).error, /2-night minimum/);
  });

  it("rejects oversized parties", () => {
    const result = validateRequest({
      ...base,
      partySize: 12,
      startDate: "2026-08-10",
      endDate: "2026-08-14",
    });
    assert.equal(result.ok, false);
    assert.match((result as { error: string }).error, /up to 10 guests/);
  });

  it("enforces lead time and horizon", () => {
    assert.equal(
      validateRequest({ ...base, startDate: "2026-07-16", endDate: "2026-07-20" }).ok,
      false
    );
    assert.equal(
      validateRequest({ ...base, startDate: "2028-01-10", endDate: "2028-01-20" }).ok,
      false
    );
  });

  it("rejects conflicts including the turnover buffer, allows the day after", () => {
    const bookings = [
      {
        spaceId: "farmhouse-id",
        startDate: "2026-08-05",
        endDate: "2026-08-08",
        blocksEstate: false,
      },
    ];
    // 2026-08-08 is checkout day but the 1-day buffer keeps it blocked.
    assert.equal(
      validateRequest({ ...base, bookings, startDate: "2026-08-08", endDate: "2026-08-11" }).ok,
      false
    );
    assert.equal(
      validateRequest({ ...base, bookings, startDate: "2026-08-09", endDate: "2026-08-12" }).ok,
      true
    );
  });
});
