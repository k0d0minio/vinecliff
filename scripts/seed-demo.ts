// Fills the platform with realistic demo data — guests, bookings across every
// status, blackouts and enquiries — so the estate can be shown off end to end
// (public availability calendars, the admin pipeline, the guests CRM, the
// dashboard stats). It is NOT a schema migration: it seeds *content*, on
// demand, and is safe to run against any database that already has the
// booking-platform tables and the four spaces (created by migrations 0002 and
// 0003).
//
//   DATABASE_URL="postgres://..." npm run db:seed:demo
//   DATABASE_URL="postgres://..." npm run db:seed:demo -- --reset   # wipe only
//
// Why a script and not a static SQL seed: bookings carry computed quotes,
// unique references and secret tokens, and their dates are anchored to *today*
// so the demo always shows a live mix of past stays, upcoming arrivals and
// fresh requests. A hardcoded SQL file would drift into the past and can't
// compute any of that.
//
// Idempotent: every run first removes the data it previously created (demo
// guests are tagged by a reserved email domain, blackouts by their reason) and
// then re-inserts a fresh set. Real guests, real bookings and owner-created
// blackouts are never touched.
import "dotenv/config";
import { inArray, like } from "drizzle-orm";
import { db } from "../lib/db";
import {
  blackouts,
  bookings,
  enquiries,
  guests,
  spaces,
  type NewBlackout,
  type NewBooking,
  type NewEnquiry,
  type NewGuest,
  type Space,
} from "../lib/db/schema";
import { addDays, todayAtEstate, type ISODate } from "../lib/booking/dates";
import { computeQuote } from "../lib/booking/pricing";
import { makeManageToken, makeReference } from "../lib/booking/tokens";

// Everything demo is tagged so a reset can find and remove exactly what this
// script created — and nothing else.
const DEMO_EMAIL_DOMAIN = "demo.vinecliff.dev";
const today = todayAtEstate();

// A stable millisecond clock for created/decided timestamps, anchored to the
// start of today at the estate so repeat runs land on tidy round times.
const NOW = new Date(`${today}T12:00:00Z`).getTime();
const DAY_MS = 86_400_000;
/** A timestamp `days` from today (negative = in the past), for created_at etc. */
function ts(days: number): Date {
  return new Date(NOW + days * DAY_MS);
}

// ---------------------------------------------------------------------------
// Guests — one row per person, deduplicated by email (the demo domain).
// ---------------------------------------------------------------------------

type GuestSeed = Omit<NewGuest, "email"> & { key: string };

const GUESTS: GuestSeed[] = [
  { key: "harper", firstName: "Amelia", lastName: "Harper", phone: "+1 716-555-0142", notes: "Repeat farmhouse guest — always books the first week of summer. Prefers the lake-facing room.", createdAt: ts(-380) },
  { key: "okafor", firstName: "Daniel", lastName: "Okafor", phone: "+1 585-555-0119", notes: "Anniversary trips to the carriage house. Loves a quiet arrival.", createdAt: ts(-300) },
  { key: "bianchi", firstName: "Sofia", lastName: "Bianchi", phone: "+1 716-555-0177", notes: "Booked the barn for her sister's wedding — big family, lots of vendors.", createdAt: ts(-250) },
  { key: "nguyen", firstName: "Linh", lastName: "Nguyen", phone: "+1 212-555-0188", notes: "Writing retreats. Came twice last year, very tidy.", createdAt: ts(-220) },
  { key: "carter", firstName: "Marcus", lastName: "Carter", phone: "+1 716-555-0164", notes: "Corporate offsite organiser. Asks a lot of questions but pays promptly.", createdAt: ts(-190) },
  { key: "delgado", firstName: "Elena", lastName: "Delgado", phone: "+1 646-555-0133", notes: null, createdAt: ts(-160) },
  { key: "kowalski", firstName: "Peter", lastName: "Kowalski", phone: "+1 716-555-0150", notes: "Reunion every couple of years — the whole family fills the estate.", createdAt: ts(-140) },
  { key: "obrien", firstName: "Grace", lastName: "O'Brien", phone: "+1 315-555-0128", notes: "Photographer scouting the barn for a styled shoot.", createdAt: ts(-120) },
  { key: "patel", firstName: "Ravi", lastName: "Patel", phone: "+1 716-555-0191", notes: null, createdAt: ts(-95) },
  { key: "schneider", firstName: "Hannah", lastName: "Schneider", phone: "+1 585-555-0107", notes: "First-timer, found us through the Chautauqua listing.", createdAt: ts(-70) },
  { key: "romano", firstName: "Luca", lastName: "Romano", phone: "+1 716-555-0173", notes: "Wedding enquiry — comparing us with a couple of other venues.", createdAt: ts(-45) },
  { key: "fitzgerald", firstName: "Claire", lastName: "Fitzgerald", phone: "+1 716-555-0116", notes: null, createdAt: ts(-30) },
  { key: "andersson", firstName: "Erik", lastName: "Andersson", phone: "+1 917-555-0155", notes: "Big birthday celebration in the works.", createdAt: ts(-20) },
  { key: "morales", firstName: "Isabella", lastName: "Morales", phone: "+1 716-555-0102", notes: null, createdAt: ts(-12) },
  { key: "thompson", firstName: "James", lastName: "Thompson", phone: "+1 716-555-0139", notes: "Called about a last-minute long weekend.", createdAt: ts(-6) },
  { key: "walsh", firstName: "Nora", lastName: "Walsh", phone: "+1 518-555-0148", notes: null, createdAt: ts(-2) },
];

function emailFor(g: GuestSeed): string {
  return `${g.firstName}.${g.lastName}`
    .toLowerCase()
    .replace(/[^a-z]+/g, ".")
    .replace(/\.+/g, ".")
    .replace(/^\.|\.$/g, "") + `@${DEMO_EMAIL_DOMAIN}`;
}

// ---------------------------------------------------------------------------
// Bookings — a lifelike spread across statuses and time. Approved bookings are
// laid out so that no two of them ever conflict (same-space overlaps, or the
// estate-wide holds taken by barn/estate events), which keeps the public
// availability calendars clean and honest. Pending/declined/cancelled rows
// don't block anything, so they can sit wherever tells a good story.
// ---------------------------------------------------------------------------

type BookingSeed = {
  slug: Space["slug"];
  guestKey: string;
  status: NonNullable<NewBooking["status"]>;
  /** Check-in offset in days from today (negative = past). */
  startOffset: number;
  nights: number;
  partySize: number;
  eventType?: string;
  guestMessage?: string;
  paymentStatus?: NonNullable<NewBooking["paymentStatus"]>;
  source?: NonNullable<NewBooking["source"]>;
  decisionNote?: string;
  adminNotes?: string;
  /** Days before check-in that the request came in. */
  leadDays: number;
};

const BOOKINGS: BookingSeed[] = [
  // ---- Past, completed & paid (history + guests CRM + "past" tab) ----------
  { slug: "farmhouse", guestKey: "harper", status: "approved", startOffset: -90, nights: 7, partySize: 8, guestMessage: "Our annual family week — can't wait to be back on the porch.", paymentStatus: "paid", source: "website", leadDays: 60, adminNotes: "Lovely as always. Left the place spotless." },
  { slug: "carriage-house", guestKey: "okafor", status: "approved", startOffset: -60, nights: 5, partySize: 2, guestMessage: "Celebrating our anniversary.", paymentStatus: "paid", source: "website", leadDays: 40 },
  { slug: "barn", guestKey: "bianchi", status: "approved", startOffset: -45, nights: 3, partySize: 120, eventType: "Wedding", guestMessage: "Saturday ceremony, Friday setup, Sunday teardown. ~120 guests.", paymentStatus: "paid", source: "email", leadDays: 210, adminNotes: "Beautiful wedding. Caterer used the north lawn." },
  { slug: "farmhouse", guestKey: "nguyen", status: "approved", startOffset: -30, nights: 5, partySize: 3, guestMessage: "Quiet writing retreat.", paymentStatus: "paid", source: "website", leadDays: 25 },

  // ---- Upcoming, confirmed (block the calendar + dashboard arrivals) --------
  { slug: "carriage-house", guestKey: "schneider", status: "approved", startOffset: 10, nights: 4, partySize: 2, guestMessage: "First visit — so excited!", paymentStatus: "deposit_paid", source: "website", leadDays: 20 },
  { slug: "farmhouse", guestKey: "delgado", status: "approved", startOffset: 20, nights: 7, partySize: 9, guestMessage: "Full week for the extended family.", paymentStatus: "deposit_paid", source: "website", leadDays: 45 },
  { slug: "estate", guestKey: "romano", status: "approved", startOffset: 45, nights: 3, partySize: 140, eventType: "Wedding", guestMessage: "Whole-estate wedding weekend, roughly 140 guests. Party staying in the houses.", paymentStatus: "deposit_paid", source: "email", leadDays: 160, adminNotes: "Deposit in. Final headcount due 30 days out." },
  { slug: "barn", guestKey: "kowalski", status: "approved", startOffset: 80, nights: 2, partySize: 90, eventType: "Reunion", guestMessage: "Kowalski family reunion — hog roast on the Saturday.", paymentStatus: "deposit_paid", source: "phone", leadDays: 120 },
  { slug: "farmhouse", guestKey: "harper", status: "approved", startOffset: 95, nights: 5, partySize: 8, guestMessage: "Booking our usual again for the autumn.", paymentStatus: "unpaid", source: "website", leadDays: 30, adminNotes: "Repeat guest — invoice sent, deposit pending." },
  { slug: "carriage-house", guestKey: "okafor", status: "approved", startOffset: 95, nights: 4, partySize: 2, paymentStatus: "unpaid", source: "website", leadDays: 28 },

  // ---- Pending requests (the admin inbox / dashboard "needs a decision") ----
  { slug: "farmhouse", guestKey: "patel", status: "pending", startOffset: 35, nights: 5, partySize: 6, guestMessage: "Hoping for a long weekend with friends — flexible by a day or two.", source: "website", leadDays: 12 },
  { slug: "carriage-house", guestKey: "fitzgerald", status: "pending", startOffset: 30, nights: 3, partySize: 2, guestMessage: "Is the porch room available these dates?", source: "website", leadDays: 8 },
  { slug: "estate", guestKey: "morales", status: "pending", startOffset: 120, nights: 4, partySize: 130, eventType: "Wedding", guestMessage: "Considering Vine Cliff for our wedding — would love to visit.", source: "website", leadDays: 5 },
  { slug: "barn", guestKey: "andersson", status: "pending", startOffset: 150, nights: 2, partySize: 70, eventType: "Birthday or celebration", guestMessage: "50th birthday party — evening reception with a band.", source: "website", leadDays: 4 },
  { slug: "farmhouse", guestKey: "thompson", status: "pending", startOffset: 6, nights: 3, partySize: 5, guestMessage: "Last-minute I know! Any chance for this coming weekend?", source: "phone", leadDays: 1 },

  // ---- Declined (archive tab) ----------------------------------------------
  { slug: "barn", guestKey: "walsh", status: "declined", startOffset: 45, nights: 3, partySize: 100, eventType: "Wedding", guestMessage: "Hoping for that weekend in particular.", decisionNote: "So sorry — the estate is already booked for a wedding that weekend. We'd love to host you on another date.", source: "website", leadDays: 20 },

  // ---- Cancelled (archive tab) ---------------------------------------------
  { slug: "farmhouse", guestKey: "carter", status: "cancelled", startOffset: 55, nights: 5, partySize: 7, eventType: undefined, guestMessage: "Team offsite for the week.", adminNotes: "Guest cancelled — offsite postponed to next quarter. Deposit refunded.", paymentStatus: "refunded", source: "website", leadDays: 35 },
];

// ---------------------------------------------------------------------------
// Blackouts — the owner-blocked side of availability. Tagged by reason so a
// reset removes exactly these and leaves any real blackouts alone.
// ---------------------------------------------------------------------------

type BlackoutSeed = {
  slug: Space["slug"] | null;
  startOffset: number;
  nights: number;
  reason: string;
};

const BLACKOUTS: BlackoutSeed[] = [
  { slug: "carriage-house", startOffset: 5, nights: 3, reason: "Owner's family visiting (demo)" },
  { slug: "farmhouse", startOffset: 130, nights: 4, reason: "Porch restoration (demo)" },
  { slug: "barn", startOffset: 170, nights: 2, reason: "Annual barn inspection (demo)" },
  { slug: null, startOffset: 210, nights: 45, reason: "Estate winterized for the season (demo)" },
];

const DEMO_BLACKOUT_REASONS = BLACKOUTS.map((b) => b.reason);

// ---------------------------------------------------------------------------
// Enquiries — the general-message inbox, in every status. One is "converted"
// and linked to a real demo booking below.
// ---------------------------------------------------------------------------

type EnquirySeed = {
  guestKey: string;
  slug?: Space["slug"];
  message: string;
  status: NonNullable<NewEnquiry["status"]>;
  /** Link to the pending booking created for this guest+space, if any. */
  linkToBookingOfGuest?: string;
  createdOffset: number;
};

const ENQUIRIES: EnquirySeed[] = [
  { guestKey: "romano", slug: "barn", message: "Do you host winter weddings? Curious about heating in the barn.", status: "new", createdOffset: -3 },
  { guestKey: "walsh", slug: "farmhouse", message: "What's the largest group the farmhouse comfortably sleeps?", status: "new", createdOffset: -1 },
  { guestKey: "schneider", slug: "carriage-house", message: "Is early check-in ever possible? Arriving mid-morning.", status: "replied", createdOffset: -9 },
  { guestKey: "morales", slug: "estate", message: "We'd love to tour the estate for our wedding before committing.", status: "converted", linkToBookingOfGuest: "morales", createdOffset: -6 },
  { guestKey: "delgado", message: "General question — do you allow well-behaved dogs?", status: "replied", createdOffset: -18 },
  { guestKey: "andersson", message: "Interested in a corporate booking, will follow up by phone.", status: "archived", createdOffset: -25 },
];

// ---------------------------------------------------------------------------
// Runner
// ---------------------------------------------------------------------------

async function clearDemoData(): Promise<void> {
  const demoGuests = await db
    .select({ id: guests.id })
    .from(guests)
    .where(like(guests.email, `%@${DEMO_EMAIL_DOMAIN}`));
  const demoGuestIds = demoGuests.map((g) => g.id);

  // Order matters: enquiries reference bookings (nullable), bookings reference
  // guests (restrict), so remove children before parents.
  await db.delete(enquiries).where(like(enquiries.email, `%@${DEMO_EMAIL_DOMAIN}`));
  if (demoGuestIds.length) {
    await db.delete(bookings).where(inArray(bookings.guestId, demoGuestIds));
    await db.delete(guests).where(inArray(guests.id, demoGuestIds));
  }
  if (DEMO_BLACKOUT_REASONS.length) {
    await db.delete(blackouts).where(inArray(blackouts.reason, DEMO_BLACKOUT_REASONS));
  }
  console.log(
    `Cleared demo data: ${demoGuestIds.length} guests (with their bookings/enquiries) and demo blackouts.`
  );
}

async function seed(): Promise<void> {
  // Space lookup by slug — the four spaces come from migration 0003.
  const spaceRows = await db.select().from(spaces);
  const bySlug = new Map(spaceRows.map((s) => [s.slug, s]));
  const need = ["farmhouse", "carriage-house", "barn", "estate"];
  const missing = need.filter((slug) => !bySlug.has(slug));
  if (missing.length) {
    throw new Error(
      `Missing spaces ${missing.join(", ")}. Run migrations first (npm run db:migrate) so the booking platform is seeded.`
    );
  }

  // --- Guests --------------------------------------------------------------
  const guestValues: NewGuest[] = GUESTS.map((g) => ({
    email: emailFor(g),
    firstName: g.firstName,
    lastName: g.lastName,
    phone: g.phone ?? null,
    notes: g.notes ?? null,
    createdAt: g.createdAt ?? undefined,
  }));
  const insertedGuests = await db
    .insert(guests)
    .values(guestValues)
    .returning({ id: guests.id, email: guests.email });
  const guestIdByKey = new Map<string, string>();
  for (const g of GUESTS) {
    const row = insertedGuests.find((r) => r.email === emailFor(g));
    if (row) guestIdByKey.set(g.key, row.id);
  }

  // --- Bookings ------------------------------------------------------------
  const usedReferences = new Set<string>();
  function uniqueReference(): string {
    let ref = makeReference();
    while (usedReferences.has(ref)) ref = makeReference();
    usedReferences.add(ref);
    return ref;
  }

  const bookingValues: NewBooking[] = BOOKINGS.map((b) => {
    const space = bySlug.get(b.slug)!;
    const guestId = guestIdByKey.get(b.guestKey);
    if (!guestId) throw new Error(`Unknown guest key: ${b.guestKey}`);

    const startDate: ISODate = addDays(today, b.startOffset);
    const endDate: ISODate = addDays(startDate, b.nights);
    const quote = computeQuote(space, startDate, endDate);
    const createdAt = ts(b.startOffset - b.leadDays);

    // Approved bookings carry a final price (here, equal to the quote) and a
    // deposit (~30%, rounded to whole dollars). Others just keep the quote.
    const isApproved = b.status === "approved";
    const finalTotalCents = isApproved ? quote.totalCents : null;
    const depositCents = isApproved
      ? Math.round((quote.totalCents * 0.3) / 100) * 100
      : null;

    // Timeline: decisions land a day or two after the request; cancellations a
    // little after that.
    const decidedAt =
      b.status === "pending" ? null : ts(b.startOffset - b.leadDays + 2);
    const cancelledAt = b.status === "cancelled" ? ts(b.startOffset - 10) : null;
    const cancelRequestedAt =
      b.status === "cancelled" ? ts(b.startOffset - 11) : null;

    return {
      reference: uniqueReference(),
      spaceId: space.id,
      guestId,
      status: b.status,
      startDate,
      endDate,
      partySize: b.partySize,
      eventType: b.eventType ?? (space.isEvent ? "Other" : null),
      guestMessage: b.guestMessage ?? null,
      quotedTotalCents: quote.totalCents,
      finalTotalCents,
      depositCents,
      paymentStatus: b.paymentStatus ?? "unpaid",
      blocksEstate: space.blocksEstate,
      source: b.source ?? "website",
      manageToken: makeManageToken(),
      decisionNote: b.decisionNote ?? null,
      adminNotes: b.adminNotes ?? null,
      cancelRequestedAt,
      decidedAt,
      cancelledAt,
      createdAt,
    } satisfies NewBooking;
  });
  const insertedBookings = await db
    .insert(bookings)
    .values(bookingValues)
    .returning({ id: bookings.id, guestId: bookings.guestId, status: bookings.status });

  // --- Blackouts -----------------------------------------------------------
  const blackoutValues: NewBlackout[] = BLACKOUTS.map((b) => {
    const startDate: ISODate = addDays(today, b.startOffset);
    return {
      spaceId: b.slug ? bySlug.get(b.slug)!.id : null,
      startDate,
      endDate: addDays(startDate, b.nights),
      reason: b.reason,
    } satisfies NewBlackout;
  });
  await db.insert(blackouts).values(blackoutValues);

  // --- Enquiries -----------------------------------------------------------
  const enquiryValues: NewEnquiry[] = ENQUIRIES.map((e) => {
    const guest = GUESTS.find((g) => g.key === e.guestKey)!;
    // A "converted" enquiry links to one of this guest's pending bookings.
    let bookingId: string | null = null;
    if (e.linkToBookingOfGuest) {
      const guestId = guestIdByKey.get(e.linkToBookingOfGuest);
      const match = insertedBookings.find(
        (b) => b.guestId === guestId && b.status === "pending"
      );
      bookingId = match?.id ?? null;
    }
    return {
      name: `${guest.firstName} ${guest.lastName}`,
      email: emailFor(guest),
      phone: guest.phone ?? null,
      spaceId: e.slug ? bySlug.get(e.slug)!.id : null,
      message: e.message,
      status: e.status,
      bookingId,
      createdAt: ts(e.createdOffset),
    } satisfies NewEnquiry;
  });
  await db.insert(enquiries).values(enquiryValues);

  // --- Summary -------------------------------------------------------------
  const counts = insertedBookings.reduce<Record<string, number>>((acc, b) => {
    acc[b.status] = (acc[b.status] ?? 0) + 1;
    return acc;
  }, {});
  console.log("Demo data seeded:");
  console.log(`  • ${insertedGuests.length} guests`);
  console.log(
    `  • ${insertedBookings.length} bookings ` +
      `(${counts.approved ?? 0} approved, ${counts.pending ?? 0} pending, ` +
      `${counts.declined ?? 0} declined, ${counts.cancelled ?? 0} cancelled)`
  );
  console.log(`  • ${blackoutValues.length} blackouts`);
  console.log(`  • ${enquiryValues.length} enquiries`);
}

async function main() {
  if (!process.env.DATABASE_URL) {
    throw new Error("DATABASE_URL is not set. Cannot seed the database.");
  }
  const resetOnly = process.argv.includes("--reset");

  console.log(
    resetOnly ? "Removing demo data…" : "Seeding demo data (clearing any previous demo run first)…"
  );
  await clearDemoData();
  if (resetOnly) {
    console.log("Done — demo data removed.");
    return;
  }
  await seed();
  console.log("Done. Open /admin to explore the pipeline, calendar and CRM.");
}

main().catch((error) => {
  console.error("Seeding failed:", error);
  process.exit(1);
});
