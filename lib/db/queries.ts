// Shared data-access helpers for the booking platform (server-only).
import { and, asc, desc, eq, gt, gte, ilike, lt, lte, or, sql } from "drizzle-orm";
import { db } from "@/lib/db";
import {
  blackouts,
  bookings,
  enquiries,
  guests,
  spaces,
  type Blackout,
  type Booking,
  type Enquiry,
  type Guest,
  type Space,
} from "@/lib/db/schema";
import { addDays, addMonths, type ISODate } from "@/lib/booking/dates";
import type {
  BlackoutBlock,
  BookingBlock,
} from "@/lib/booking/availability";

export type BookingWithRelations = {
  booking: Booking;
  space: Space;
  guest: Guest;
};

export async function getBookingByManageToken(
  token: string
): Promise<BookingWithRelations | null> {
  const [row] = await db
    .select({ booking: bookings, space: spaces, guest: guests })
    .from(bookings)
    .innerJoin(spaces, eq(bookings.spaceId, spaces.id))
    .innerJoin(guests, eq(bookings.guestId, guests.id))
    .where(eq(bookings.manageToken, token))
    .limit(1);
  return row ?? null;
}

export async function getBookingWithRelations(
  id: string
): Promise<BookingWithRelations | null> {
  const [row] = await db
    .select({ booking: bookings, space: spaces, guest: guests })
    .from(bookings)
    .innerJoin(spaces, eq(bookings.spaceId, spaces.id))
    .innerJoin(guests, eq(bookings.guestId, guests.id))
    .where(eq(bookings.id, id))
    .limit(1);
  return row ?? null;
}

export async function getActiveSpaces(): Promise<Space[]> {
  return db
    .select()
    .from(spaces)
    .where(eq(spaces.active, true))
    .orderBy(asc(spaces.sortOrder));
}

export async function getAllSpaces(): Promise<Space[]> {
  return db.select().from(spaces).orderBy(asc(spaces.sortOrder));
}

export async function getSpaceBySlug(slug: string): Promise<Space | null> {
  const [row] = await db
    .select()
    .from(spaces)
    .where(eq(spaces.slug, slug))
    .limit(1);
  return row ?? null;
}

export async function getSpaceById(id: string): Promise<Space | null> {
  const [row] = await db.select().from(spaces).where(eq(spaces.id, id)).limit(1);
  return row ?? null;
}

export async function getSpaceByIcalToken(token: string): Promise<Space | null> {
  const [row] = await db
    .select()
    .from(spaces)
    .where(eq(spaces.icalToken, token))
    .limit(1);
  return row ?? null;
}

export type AvailabilityData = {
  bookings: BookingBlock[];
  blackouts: BlackoutBlock[];
};

/**
 * Everything that can block dates in [from, to): approved bookings across all
 * spaces (estate-blocking rules are cross-space, so callers always need the
 * full picture) and all blackouts. The query window is padded so bookings
 * just outside it still contribute their turnover buffer inside it.
 */
export async function getAvailabilityData(
  from: ISODate,
  to: ISODate
): Promise<AvailabilityData> {
  const paddedFrom = addDays(from, -31);
  const paddedTo = addDays(to, 31);
  const [bookingRows, blackoutRows] = await Promise.all([
    db
      .select({
        spaceId: bookings.spaceId,
        startDate: bookings.startDate,
        endDate: bookings.endDate,
        blocksEstate: bookings.blocksEstate,
      })
      .from(bookings)
      .where(
        and(
          eq(bookings.status, "approved"),
          lt(bookings.startDate, paddedTo),
          gt(bookings.endDate, paddedFrom)
        )
      ),
    db
      .select({
        spaceId: blackouts.spaceId,
        startDate: blackouts.startDate,
        endDate: blackouts.endDate,
      })
      .from(blackouts)
      .where(and(lt(blackouts.startDate, paddedTo), gt(blackouts.endDate, paddedFrom))),
  ]);
  return { bookings: bookingRows, blackouts: blackoutRows };
}

// ---------------------------------------------------------------------------
// Admin queries
// ---------------------------------------------------------------------------

export type BookingTab = "pending" | "upcoming" | "past" | "archive" | "all";

export async function listBookingsForAdmin(options: {
  tab: BookingTab;
  q?: string;
  today: ISODate;
  limit?: number;
}): Promise<BookingWithRelations[]> {
  const { tab, q, today, limit = 200 } = options;
  const conditions = [];
  if (tab === "pending") conditions.push(eq(bookings.status, "pending"));
  if (tab === "upcoming") {
    conditions.push(eq(bookings.status, "approved"), gt(bookings.endDate, today));
  }
  if (tab === "past") {
    conditions.push(eq(bookings.status, "approved"), lte(bookings.endDate, today));
  }
  if (tab === "archive") {
    conditions.push(
      or(eq(bookings.status, "declined"), eq(bookings.status, "cancelled"))!
    );
  }
  if (q) {
    const like = `%${q}%`;
    conditions.push(
      or(
        ilike(bookings.reference, like),
        ilike(guests.email, like),
        ilike(guests.firstName, like),
        ilike(guests.lastName, like)
      )!
    );
  }
  const order =
    tab === "pending" || tab === "upcoming"
      ? asc(bookings.startDate)
      : desc(bookings.createdAt);
  return db
    .select({ booking: bookings, space: spaces, guest: guests })
    .from(bookings)
    .innerJoin(spaces, eq(bookings.spaceId, spaces.id))
    .innerJoin(guests, eq(bookings.guestId, guests.id))
    .where(conditions.length ? and(...conditions) : undefined)
    .orderBy(order)
    .limit(limit);
}

export type GuestListRow = {
  guest: Guest;
  bookingCount: number;
  lastStart: ISODate | null;
};

export async function listGuestsWithStats(q?: string): Promise<GuestListRow[]> {
  const like = q ? `%${q}%` : null;
  return db
    .select({
      guest: guests,
      bookingCount: sql<number>`count(${bookings.id})::int`,
      lastStart: sql<ISODate | null>`max(${bookings.startDate})`,
    })
    .from(guests)
    .leftJoin(bookings, eq(bookings.guestId, guests.id))
    .where(
      like
        ? or(
            ilike(guests.email, like),
            ilike(guests.firstName, like),
            ilike(guests.lastName, like)
          )
        : undefined
    )
    .groupBy(guests.id)
    .orderBy(desc(guests.createdAt))
    .limit(500);
}

export async function getGuestWithBookings(id: string): Promise<{
  guest: Guest;
  bookings: Array<{ booking: Booking; space: Space }>;
} | null> {
  const [guest] = await db.select().from(guests).where(eq(guests.id, id)).limit(1);
  if (!guest) return null;
  const history = await db
    .select({ booking: bookings, space: spaces })
    .from(bookings)
    .innerJoin(spaces, eq(bookings.spaceId, spaces.id))
    .where(eq(bookings.guestId, id))
    .orderBy(desc(bookings.startDate));
  return { guest, bookings: history };
}

export type EnquiryRow = { enquiry: Enquiry; spaceName: string | null };

export async function listEnquiries(status?: Enquiry["status"]): Promise<EnquiryRow[]> {
  return db
    .select({ enquiry: enquiries, spaceName: spaces.name })
    .from(enquiries)
    .leftJoin(spaces, eq(enquiries.spaceId, spaces.id))
    .where(status ? eq(enquiries.status, status) : undefined)
    .orderBy(desc(enquiries.createdAt))
    .limit(300);
}

export type CalendarData = {
  bookings: Array<{ booking: Booking; space: Space; guest: Guest }>;
  blackouts: Array<{ blackout: Blackout; spaceName: string | null }>;
};

/** Approved bookings and blackouts overlapping [from, to) for the calendar. */
export async function getCalendarData(from: ISODate, to: ISODate): Promise<CalendarData> {
  const [bookingRows, blackoutRows] = await Promise.all([
    db
      .select({ booking: bookings, space: spaces, guest: guests })
      .from(bookings)
      .innerJoin(spaces, eq(bookings.spaceId, spaces.id))
      .innerJoin(guests, eq(bookings.guestId, guests.id))
      .where(
        and(
          eq(bookings.status, "approved"),
          lt(bookings.startDate, to),
          gt(bookings.endDate, from)
        )
      )
      .orderBy(asc(bookings.startDate)),
    db
      .select({ blackout: blackouts, spaceName: spaces.name })
      .from(blackouts)
      .leftJoin(spaces, eq(blackouts.spaceId, spaces.id))
      .where(and(lt(blackouts.startDate, to), gt(blackouts.endDate, from)))
      .orderBy(asc(blackouts.startDate)),
  ]);
  return { bookings: bookingRows, blackouts: blackoutRows };
}

export async function listUpcomingBlackouts(today: ISODate) {
  return db
    .select({ blackout: blackouts, spaceName: spaces.name })
    .from(blackouts)
    .leftJoin(spaces, eq(blackouts.spaceId, spaces.id))
    .where(gt(blackouts.endDate, today))
    .orderBy(asc(blackouts.startDate))
    .limit(100);
}

export type DashboardData = {
  pendingCount: number;
  newEnquiryCount: number;
  arrivalsSoon: BookingWithRelations[];
  pendingRequests: BookingWithRelations[];
  monthRevenueCents: number;
  monthLabel: ISODate;
};

export async function getDashboardData(today: ISODate): Promise<DashboardData> {
  const monthStart: ISODate = `${today.slice(0, 7)}-01`;
  const monthEnd = addMonths(monthStart, 1);
  const soon = addDays(today, 14);

  const [pending, newEnquiries, revenue, arrivalsSoon, pendingRequests] =
    await Promise.all([
      db
        .select({ n: sql<number>`count(*)::int` })
        .from(bookings)
        .where(eq(bookings.status, "pending")),
      db
        .select({ n: sql<number>`count(*)::int` })
        .from(enquiries)
        .where(eq(enquiries.status, "new")),
      db
        .select({
          n: sql<number>`coalesce(sum(coalesce(${bookings.finalTotalCents}, ${bookings.quotedTotalCents})), 0)::int`,
        })
        .from(bookings)
        .where(
          and(
            eq(bookings.status, "approved"),
            gte(bookings.startDate, monthStart),
            lt(bookings.startDate, monthEnd)
          )
        ),
      db
        .select({ booking: bookings, space: spaces, guest: guests })
        .from(bookings)
        .innerJoin(spaces, eq(bookings.spaceId, spaces.id))
        .innerJoin(guests, eq(bookings.guestId, guests.id))
        .where(
          and(
            eq(bookings.status, "approved"),
            gte(bookings.startDate, today),
            lte(bookings.startDate, soon)
          )
        )
        .orderBy(asc(bookings.startDate))
        .limit(6),
      db
        .select({ booking: bookings, space: spaces, guest: guests })
        .from(bookings)
        .innerJoin(spaces, eq(bookings.spaceId, spaces.id))
        .innerJoin(guests, eq(bookings.guestId, guests.id))
        .where(eq(bookings.status, "pending"))
        .orderBy(desc(bookings.createdAt))
        .limit(6),
    ]);

  return {
    pendingCount: pending[0]?.n ?? 0,
    newEnquiryCount: newEnquiries[0]?.n ?? 0,
    monthRevenueCents: revenue[0]?.n ?? 0,
    arrivalsSoon,
    pendingRequests,
    monthLabel: monthStart,
  };
}
