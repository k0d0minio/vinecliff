// Database schema, managed by Drizzle.
//
// Conventions used throughout:
//   - Money is stored as integer cents (never floats).
//   - Date ranges are half-open [startDate, endDate): endDate is the checkout
//     day for stays and the day after the last event day for events. Two
//     bookings that share a boundary date do not overlap.
//   - Dates are plain calendar dates (Postgres `date`, read as "YYYY-MM-DD"
//     strings) in the estate's local time — never timestamps, so there is no
//     timezone drift between the form, the calendar and the database.
import { sql } from "drizzle-orm";
import {
  boolean,
  date,
  index,
  integer,
  pgEnum,
  pgTable,
  text,
  timestamp,
  uuid,
} from "drizzle-orm/pg-core";

// The admin section is gated by real accounts stored here rather than a single
// shared password. Passwords are stored only as scrypt hashes (see
// `lib/auth/password.ts`) — the plaintext never touches the database.
export const users = pgTable("users", {
  id: uuid("id").primaryKey().defaultRandom(),
  email: text("email").notNull().unique(),
  passwordHash: text("password_hash").notNull(),
  firstName: text("first_name").notNull(),
  lastName: text("last_name").notNull(),
  createdAt: timestamp("created_at", { withTimezone: true })
    .notNull()
    .defaultNow(),
  updatedAt: timestamp("updated_at", { withTimezone: true })
    .notNull()
    .defaultNow(),
});

export type User = typeof users.$inferSelect;
export type NewUser = typeof users.$inferInsert;

// ---------------------------------------------------------------------------
// Spaces — the bookable units (farmhouse, carriage house, barn, whole estate).
// The database is the source of truth for the public site; rows are seeded
// from the original lib/site.ts content and edited in the admin.
// ---------------------------------------------------------------------------

export const spaces = pgTable(
  "spaces",
  {
    id: uuid("id").primaryKey().defaultRandom(),
    slug: text("slug").notNull().unique(),
    name: text("name").notNull(),
    /** Short positioning line, e.g. "Weekly & weekend stays". */
    kind: text("kind").notNull(),
    /** Heritage note shown on cards, e.g. "Built c. 1850". */
    age: text("age").notNull(),
    /** Card-length summary. */
    blurb: text("blurb").notNull(),
    /** Long-form copy for the space's detail page. */
    description: text("description").notNull(),
    /** Path under /public, e.g. "/img/house.jpg". */
    image: text("image").notNull(),
    features: text("features")
      .array()
      .notNull()
      .default(sql`'{}'::text[]`),

    /** Event spaces price per day and speak of "event days", not "nights". */
    isEvent: boolean("is_event").notNull().default(false),
    /**
     * When true, an approved booking of this space blocks the whole estate by
     * default, and this space is only available when every space is free
     * (weddings and estate hires take over the property). Overridable per
     * booking at approval time.
     */
    blocksEstate: boolean("blocks_estate").notNull().default(false),

    /** Per night for stays; per event day when `isEvent`. */
    nightlyRateCents: integer("nightly_rate_cents").notNull(),
    /** Optional discounted rate applied per full 7-night block. */
    weeklyRateCents: integer("weekly_rate_cents"),
    cleaningFeeCents: integer("cleaning_fee_cents").notNull().default(0),

    minNights: integer("min_nights").notNull().default(1),
    maxGuests: integer("max_guests").notNull(),
    /** Days kept free between bookings of this space for turnover. */
    bufferDays: integer("buffer_days").notNull().default(1),
    /** Requests must arrive at least this many days before arrival. */
    minLeadDays: integer("min_lead_days").notNull().default(2),
    /** ...and no further out than this many months. */
    maxHorizonMonths: integer("max_horizon_months").notNull().default(18),

    /** Secret path segment for this space's private iCal feed. */
    icalToken: text("ical_token")
      .notNull()
      .unique()
      .default(sql`md5(gen_random_uuid()::text || gen_random_uuid()::text)`),

    active: boolean("active").notNull().default(true),
    sortOrder: integer("sort_order").notNull().default(0),
    createdAt: timestamp("created_at", { withTimezone: true })
      .notNull()
      .defaultNow(),
    updatedAt: timestamp("updated_at", { withTimezone: true })
      .notNull()
      .defaultNow()
      .$onUpdate(() => new Date()),
  },
  (t) => [index("spaces_sort_idx").on(t.sortOrder)]
);

export type Space = typeof spaces.$inferSelect;
export type NewSpace = typeof spaces.$inferInsert;

// ---------------------------------------------------------------------------
// Guests — one row per person, deduplicated by email. Doubles as a lightweight
// CRM (notes, booking history via the bookings relation).
// ---------------------------------------------------------------------------

export const guests = pgTable("guests", {
  id: uuid("id").primaryKey().defaultRandom(),
  /** Stored lowercased; the unique key that deduplicates repeat guests. */
  email: text("email").notNull().unique(),
  firstName: text("first_name").notNull(),
  lastName: text("last_name").notNull(),
  phone: text("phone"),
  /** Private admin notes ("prefers the lake room", "repeat wedding client"). */
  notes: text("notes"),
  createdAt: timestamp("created_at", { withTimezone: true })
    .notNull()
    .defaultNow(),
  updatedAt: timestamp("updated_at", { withTimezone: true })
    .notNull()
    .defaultNow()
    .$onUpdate(() => new Date()),
});

export type Guest = typeof guests.$inferSelect;
export type NewGuest = typeof guests.$inferInsert;

// ---------------------------------------------------------------------------
// Bookings — request-to-book: rows arrive as `pending` and only block the
// calendar once an admin approves them.
// ---------------------------------------------------------------------------

export const bookingStatus = pgEnum("booking_status", [
  "pending",
  "approved",
  "declined",
  "cancelled",
]);

export const paymentStatus = pgEnum("payment_status", [
  "unpaid",
  "deposit_paid",
  "paid",
  "refunded",
]);

export const bookingSource = pgEnum("booking_source", [
  "website",
  "phone",
  "email",
  "admin",
]);

export const bookings = pgTable(
  "bookings",
  {
    id: uuid("id").primaryKey().defaultRandom(),
    /** Human-friendly code guests quote on the phone, e.g. "VC-7KMQ4". */
    reference: text("reference").notNull().unique(),
    spaceId: uuid("space_id")
      .notNull()
      .references(() => spaces.id),
    guestId: uuid("guest_id")
      .notNull()
      .references(() => guests.id),
    status: bookingStatus("status").notNull().default("pending"),

    /** Check-in day (first event day for event spaces). */
    startDate: date("start_date", { mode: "string" }).notNull(),
    /** Checkout day, exclusive (day after the last event day). */
    endDate: date("end_date", { mode: "string" }).notNull(),
    partySize: integer("party_size").notNull(),
    /** For event spaces: "Wedding", "Reunion", ... */
    eventType: text("event_type"),
    /** The guest's message from the booking form. */
    guestMessage: text("guest_message"),

    /** Auto-computed estimate shown to the guest at request time. */
    quotedTotalCents: integer("quoted_total_cents").notNull(),
    /** Owner-adjusted price, set at approval. Falls back to the quote. */
    finalTotalCents: integer("final_total_cents"),
    depositCents: integer("deposit_cents"),
    paymentStatus: paymentStatus("payment_status").notNull().default("unpaid"),

    /** Whether this booking blocks every space (weddings, estate hire). */
    blocksEstate: boolean("blocks_estate").notNull().default(false),
    source: bookingSource("source").notNull().default("website"),

    /** Secret token for the guest's private status page. */
    manageToken: text("manage_token").notNull().unique(),

    /** Note included in the approval/decline email to the guest. */
    decisionNote: text("decision_note"),
    /** Private admin notes, never shown to the guest. */
    adminNotes: text("admin_notes"),

    /** Set when the guest asks to cancel from their status page. */
    cancelRequestedAt: timestamp("cancel_requested_at", { withTimezone: true }),
    decidedAt: timestamp("decided_at", { withTimezone: true }),
    cancelledAt: timestamp("cancelled_at", { withTimezone: true }),
    createdAt: timestamp("created_at", { withTimezone: true })
      .notNull()
      .defaultNow(),
    updatedAt: timestamp("updated_at", { withTimezone: true })
      .notNull()
      .defaultNow()
      .$onUpdate(() => new Date()),
  },
  (t) => [
    index("bookings_space_dates_idx").on(t.spaceId, t.startDate),
    index("bookings_status_idx").on(t.status),
    index("bookings_guest_idx").on(t.guestId),
  ]
);

export type Booking = typeof bookings.$inferSelect;
export type NewBooking = typeof bookings.$inferInsert;

// ---------------------------------------------------------------------------
// Blackouts — the owner-managed side of availability. Spaces are open by
// default; a blackout closes a date range for one space (or the whole estate
// when spaceId is null) with an optional reason.
// ---------------------------------------------------------------------------

export const blackouts = pgTable(
  "blackouts",
  {
    id: uuid("id").primaryKey().defaultRandom(),
    /** Null = every space (e.g. "estate winterized"). */
    spaceId: uuid("space_id").references(() => spaces.id, {
      onDelete: "cascade",
    }),
    startDate: date("start_date", { mode: "string" }).notNull(),
    /** Exclusive, like bookings: the space reopens on this day. */
    endDate: date("end_date", { mode: "string" }).notNull(),
    reason: text("reason"),
    createdAt: timestamp("created_at", { withTimezone: true })
      .notNull()
      .defaultNow(),
  },
  (t) => [index("blackouts_space_dates_idx").on(t.spaceId, t.startDate)]
);

export type Blackout = typeof blackouts.$inferSelect;
export type NewBlackout = typeof blackouts.$inferInsert;

// ---------------------------------------------------------------------------
// Enquiries — general messages from the website's enquiry form; convertible
// into bookings from the admin.
// ---------------------------------------------------------------------------

export const enquiryStatus = pgEnum("enquiry_status", [
  "new",
  "replied",
  "converted",
  "archived",
]);

export const enquiries = pgTable(
  "enquiries",
  {
    id: uuid("id").primaryKey().defaultRandom(),
    name: text("name").notNull(),
    email: text("email").notNull(),
    phone: text("phone"),
    /** Optional: which space the enquiry is about. */
    spaceId: uuid("space_id").references(() => spaces.id, {
      onDelete: "set null",
    }),
    message: text("message").notNull(),
    status: enquiryStatus("status").notNull().default("new"),
    /** Set when the enquiry is converted into a booking. */
    bookingId: uuid("booking_id").references(() => bookings.id, {
      onDelete: "set null",
    }),
    createdAt: timestamp("created_at", { withTimezone: true })
      .notNull()
      .defaultNow(),
    updatedAt: timestamp("updated_at", { withTimezone: true })
      .notNull()
      .defaultNow()
      .$onUpdate(() => new Date()),
  },
  (t) => [index("enquiries_status_idx").on(t.status)]
);

export type Enquiry = typeof enquiries.$inferSelect;
export type NewEnquiry = typeof enquiries.$inferInsert;

// ---------------------------------------------------------------------------
// Settings — small key/value store for estate-wide knobs edited in the admin
// (notification email, cancellation policy text, ...).
// ---------------------------------------------------------------------------

export const settings = pgTable("settings", {
  key: text("key").primaryKey(),
  value: text("value").notNull(),
  updatedAt: timestamp("updated_at", { withTimezone: true })
    .notNull()
    .defaultNow()
    .$onUpdate(() => new Date()),
});

export type Setting = typeof settings.$inferSelect;
