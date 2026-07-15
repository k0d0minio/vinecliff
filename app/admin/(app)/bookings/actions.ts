"use server";

import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";
import { eq } from "drizzle-orm";
import { db } from "@/lib/db";
import { bookings, enquiries, guests, type Booking } from "@/lib/db/schema";
import {
  getAvailabilityData,
  getBookingWithRelations,
  getSpaceById,
  type BookingWithRelations,
} from "@/lib/db/queries";
import { requireAdmin } from "@/lib/auth/require-admin";
import { isValidISODate, rangesOverlap } from "@/lib/booking/dates";
import { blockedRanges } from "@/lib/booking/availability";
import { computeQuote } from "@/lib/booking/pricing";
import { makeManageToken, makeReference } from "@/lib/booking/tokens";
import { getCancellationPolicy } from "@/lib/settings";
import {
  bookingApprovedEmail,
  bookingCancelledEmail,
  bookingDeclinedEmail,
  sendEmail,
} from "@/lib/email";

export type AdminActionState = { error?: string; ok?: boolean };

function text(formData: FormData, name: string, maxLength = 4000): string {
  const value = formData.get(name);
  return typeof value === "string" ? value.trim().slice(0, maxLength) : "";
}

/** Parse a human dollar amount ("4,500", "$4500.50") into cents; null if blank. */
function parseMoney(raw: string): number | null {
  if (!raw) return null;
  const cleaned = raw.replace(/[^0-9.]/g, "");
  if (!cleaned) return null;
  const dollars = Number.parseFloat(cleaned);
  if (!Number.isFinite(dollars) || dollars < 0) return null;
  return Math.round(dollars * 100);
}

function guestEmailData(row: BookingWithRelations, policy: string | null) {
  return {
    reference: row.booking.reference,
    spaceName: row.space.name,
    isEvent: row.space.isEvent,
    startDate: row.booking.startDate,
    endDate: row.booking.endDate,
    partySize: row.booking.partySize,
    guestFirstName: row.guest.firstName,
    manageToken: row.booking.manageToken,
    policy,
  };
}

function revalidateBookingViews(id: string) {
  revalidatePath("/admin");
  revalidatePath("/admin/bookings");
  revalidatePath(`/admin/bookings/${id}`);
  revalidatePath("/admin/calendar");
}

export async function approveBooking(
  _previous: AdminActionState,
  formData: FormData
): Promise<AdminActionState> {
  try {
    await requireAdmin();
    const id = text(formData, "bookingId", 40);
    const row = await getBookingWithRelations(id);
    if (!row) return { error: "Booking not found." };
    if (row.booking.status !== "pending") {
      return { error: "Only pending requests can be approved." };
    }

    const finalTotalCents =
      parseMoney(text(formData, "finalTotal", 20)) ?? row.booking.quotedTotalCents;
    const depositCents = parseMoney(text(formData, "deposit", 20));
    const blocksEstate = formData.get("blocksEstate") === "on";
    const decisionNote = text(formData, "decisionNote", 1000) || null;

    await db
      .update(bookings)
      .set({
        status: "approved",
        decidedAt: new Date(),
        finalTotalCents,
        depositCents,
        blocksEstate,
        decisionNote,
      })
      .where(eq(bookings.id, id));

    const policy = await getCancellationPolicy();
    await sendEmail({
      to: row.guest.email,
      ...bookingApprovedEmail({
        ...guestEmailData(row, policy),
        totalCents: finalTotalCents,
        note: decisionNote,
      }),
    });

    revalidateBookingViews(id);
    return { ok: true };
  } catch (error) {
    console.error("Approve failed:", error);
    return { error: "Could not approve the booking — please try again." };
  }
}

export async function declineBooking(
  _previous: AdminActionState,
  formData: FormData
): Promise<AdminActionState> {
  try {
    await requireAdmin();
    const id = text(formData, "bookingId", 40);
    const row = await getBookingWithRelations(id);
    if (!row) return { error: "Booking not found." };
    if (row.booking.status !== "pending") {
      return { error: "Only pending requests can be declined." };
    }

    const decisionNote = text(formData, "decisionNote", 1000) || null;
    await db
      .update(bookings)
      .set({ status: "declined", decidedAt: new Date(), decisionNote })
      .where(eq(bookings.id, id));

    await sendEmail({
      to: row.guest.email,
      ...bookingDeclinedEmail({ ...guestEmailData(row, null), note: decisionNote }),
    });

    revalidateBookingViews(id);
    return { ok: true };
  } catch (error) {
    console.error("Decline failed:", error);
    return { error: "Could not decline the booking — please try again." };
  }
}

export async function cancelBooking(
  _previous: AdminActionState,
  formData: FormData
): Promise<AdminActionState> {
  try {
    await requireAdmin();
    const id = text(formData, "bookingId", 40);
    const row = await getBookingWithRelations(id);
    if (!row) return { error: "Booking not found." };
    if (row.booking.status !== "approved") {
      return { error: "Only confirmed bookings can be cancelled." };
    }

    const decisionNote = text(formData, "decisionNote", 1000) || null;
    await db
      .update(bookings)
      .set({ status: "cancelled", cancelledAt: new Date(), decisionNote })
      .where(eq(bookings.id, id));

    const policy = await getCancellationPolicy();
    await sendEmail({
      to: row.guest.email,
      ...bookingCancelledEmail({ ...guestEmailData(row, policy), note: decisionNote }),
    });

    revalidateBookingViews(id);
    return { ok: true };
  } catch (error) {
    console.error("Cancel failed:", error);
    return { error: "Could not cancel the booking — please try again." };
  }
}

const PAYMENT_STATUSES: Booking["paymentStatus"][] = [
  "unpaid",
  "deposit_paid",
  "paid",
  "refunded",
];

export async function recordPayment(
  _previous: AdminActionState,
  formData: FormData
): Promise<AdminActionState> {
  try {
    await requireAdmin();
    const id = text(formData, "bookingId", 40);
    const statusRaw = text(formData, "paymentStatus", 20);
    const paymentStatus = PAYMENT_STATUSES.find((s) => s === statusRaw);
    if (!paymentStatus) return { error: "Pick a payment status." };
    const depositCents = parseMoney(text(formData, "deposit", 20));

    await db
      .update(bookings)
      .set({
        paymentStatus,
        ...(depositCents !== null ? { depositCents } : {}),
      })
      .where(eq(bookings.id, id));

    revalidateBookingViews(id);
    return { ok: true };
  } catch (error) {
    console.error("Payment update failed:", error);
    return { error: "Could not update payment — please try again." };
  }
}

export async function saveAdminNotes(
  _previous: AdminActionState,
  formData: FormData
): Promise<AdminActionState> {
  try {
    await requireAdmin();
    const id = text(formData, "bookingId", 40);
    const adminNotes = text(formData, "adminNotes", 4000) || null;
    await db.update(bookings).set({ adminNotes }).where(eq(bookings.id, id));
    revalidatePath(`/admin/bookings/${id}`);
    return { ok: true };
  } catch (error) {
    console.error("Notes update failed:", error);
    return { error: "Could not save notes — please try again." };
  }
}

// ---------------------------------------------------------------------------
// Manual bookings (phone/email requests entered by the owner). Lead-time and
// minimum-stay rules don't apply — the owner is the authority — but overlaps
// with confirmed bookings and blackouts are still rejected to prevent
// accidental double-booking.
// ---------------------------------------------------------------------------

const EMAIL_PATTERN = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;

export async function createManualBooking(
  _previous: AdminActionState,
  formData: FormData
): Promise<AdminActionState> {
  let bookingId: string;
  try {
    await requireAdmin();

    const spaceId = text(formData, "spaceId", 40);
    const startDate = text(formData, "startDate", 10);
    const endDate = text(formData, "endDate", 10);
    const firstName = text(formData, "firstName", 80);
    const lastName = text(formData, "lastName", 80);
    const email = text(formData, "email", 200).toLowerCase();
    const phone = text(formData, "phone", 40);
    const partySize = Number(text(formData, "partySize", 5));
    const status = text(formData, "status", 10) === "pending" ? "pending" : "approved";
    const source = text(formData, "source", 10);
    const totalCents = parseMoney(text(formData, "total", 20));
    const depositCents = parseMoney(text(formData, "deposit", 20));
    const blocksEstate = formData.get("blocksEstate") === "on";
    const notify = formData.get("notify") === "on";
    const adminNotes = text(formData, "adminNotes", 4000) || null;
    const enquiryId = text(formData, "enquiryId", 40) || null;

    const space = await getSpaceById(spaceId);
    if (!space) return { error: "Pick a space." };
    if (!firstName || !lastName) return { error: "The guest needs a name." };
    if (!EMAIL_PATTERN.test(email)) return { error: "That email address doesn't look right." };
    if (!isValidISODate(startDate) || !isValidISODate(endDate) || endDate <= startDate) {
      return {
        error: space.isEvent
          ? "The departure day must be after the first day."
          : "Checkout must be after check-in.",
      };
    }
    if (!Number.isInteger(partySize) || partySize < 1) {
      return { error: "How many guests are coming?" };
    }

    if (status === "approved") {
      const availability = await getAvailabilityData(startDate, endDate);
      const blocked = blockedRanges(space, availability.bookings, availability.blackouts);
      if (blocked.some((r) => rangesOverlap(startDate, endDate, r.startDate, r.endDate))) {
        return {
          error:
            "Those dates conflict with an existing booking, buffer day or blackout. Adjust the dates (or clear the blackout) first.",
        };
      }
    }

    const quote = computeQuote(space, startDate, endDate);

    const [guest] = await db
      .insert(guests)
      .values({ email, firstName, lastName, phone: phone || null })
      .onConflictDoUpdate({
        target: guests.email,
        set: { firstName, lastName, ...(phone ? { phone } : {}), updatedAt: new Date() },
      })
      .returning();

    let booking: Booking | null = null;
    for (let attempt = 0; attempt < 3 && !booking; attempt++) {
      try {
        const [row] = await db
          .insert(bookings)
          .values({
            reference: makeReference(),
            manageToken: makeManageToken(),
            spaceId: space.id,
            guestId: guest.id,
            status,
            startDate,
            endDate,
            partySize,
            quotedTotalCents: quote.totalCents,
            finalTotalCents: totalCents ?? quote.totalCents,
            depositCents,
            blocksEstate,
            source: source === "email" ? "email" : source === "admin" ? "admin" : "phone",
            adminNotes,
            decidedAt: status === "approved" ? new Date() : null,
          })
          .returning();
        booking = row;
      } catch (error) {
        const message = error instanceof Error ? error.message : String(error);
        if (
          !message.includes("bookings_reference_unique") &&
          !message.includes("bookings_manage_token_unique")
        ) {
          throw error;
        }
      }
    }
    if (!booking) return { error: "Could not save the booking — please try again." };
    bookingId = booking.id;

    if (enquiryId) {
      await db
        .update(enquiries)
        .set({ status: "converted", bookingId: booking.id })
        .where(eq(enquiries.id, enquiryId));
      revalidatePath("/admin/enquiries");
    }

    if (notify && status === "approved") {
      const policy = await getCancellationPolicy();
      await sendEmail({
        to: email,
        ...bookingApprovedEmail({
          reference: booking.reference,
          spaceName: space.name,
          isEvent: space.isEvent,
          startDate,
          endDate,
          partySize,
          guestFirstName: firstName,
          manageToken: booking.manageToken,
          totalCents: booking.finalTotalCents ?? quote.totalCents,
          policy,
        }),
      });
    }

    revalidateBookingViews(booking.id);
  } catch (error) {
    console.error("Manual booking failed:", error);
    return { error: "Could not save the booking — please try again." };
  }
  redirect(`/admin/bookings/${bookingId}`);
}
