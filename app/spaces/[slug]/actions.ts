"use server";

import { redirect } from "next/navigation";
import { db } from "@/lib/db";
import { bookings, guests, type Booking } from "@/lib/db/schema";
import { getAvailabilityData, getSpaceBySlug } from "@/lib/db/queries";
import { todayAtEstate } from "@/lib/booking/dates";
import { bookingWindow, validateRequest } from "@/lib/booking/availability";
import { computeQuote } from "@/lib/booking/pricing";
import { makeManageToken, makeReference } from "@/lib/booking/tokens";
import { EVENT_TYPES } from "@/lib/booking/event-types";
import { getCancellationPolicy, getNotifyEmail } from "@/lib/settings";
import {
  ownerNewRequestEmail,
  requestReceivedEmail,
  sendEmail,
} from "@/lib/email";

export type BookingFormState = { error?: string };

function cleanText(value: FormDataEntryValue | null, maxLength: number): string {
  return typeof value === "string" ? value.trim().slice(0, maxLength) : "";
}

const EMAIL_PATTERN = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;

export async function requestBooking(
  _previous: BookingFormState,
  formData: FormData
): Promise<BookingFormState> {
  // Honeypot: real guests never fill this. Bots get waved through to the
  // homepage without a hint that anything was filtered.
  if (cleanText(formData.get("website"), 100)) redirect("/");

  const slug = cleanText(formData.get("space"), 100);
  const startDate = cleanText(formData.get("startDate"), 10);
  const endDate = cleanText(formData.get("endDate"), 10);
  const firstName = cleanText(formData.get("firstName"), 80);
  const lastName = cleanText(formData.get("lastName"), 80);
  const email = cleanText(formData.get("email"), 200).toLowerCase();
  const phone = cleanText(formData.get("phone"), 40);
  const message = cleanText(formData.get("message"), 2000);
  const partySize = Number(cleanText(formData.get("partySize"), 5));
  const eventTypeRaw = cleanText(formData.get("eventType"), 60);

  if (!firstName || !lastName) {
    return { error: "Please tell us your name." };
  }
  if (!EMAIL_PATTERN.test(email)) {
    return { error: "That email address doesn't look right." };
  }

  let manageToken: string;
  try {
    const space = await getSpaceBySlug(slug);
    if (!space || !space.active) {
      return { error: "This space isn't taking bookings right now." };
    }

    const eventType = space.isEvent
      ? (EVENT_TYPES as readonly string[]).find((t) => t === eventTypeRaw) ?? "Other"
      : null;

    // Authoritative availability check against fresh data.
    const today = todayAtEstate();
    const window = bookingWindow(space, today);
    const availability = await getAvailabilityData(today, window.lastEnd);
    const validation = validateRequest({
      space,
      startDate,
      endDate,
      partySize,
      today,
      bookings: availability.bookings,
      blackouts: availability.blackouts,
    });
    if (!validation.ok) return { error: validation.error };

    const quote = computeQuote(space, startDate, endDate);

    // Guests are deduplicated by email; details refresh to the latest request
    // but a blank phone never wipes one we already have.
    const [guest] = await db
      .insert(guests)
      .values({ email, firstName, lastName, phone: phone || null })
      .onConflictDoUpdate({
        target: guests.email,
        set: {
          firstName,
          lastName,
          ...(phone ? { phone } : {}),
          updatedAt: new Date(),
        },
      })
      .returning();

    // Reference and token collisions are astronomically rare but cheap to
    // retry — the unique constraints are the arbiter.
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
            status: "pending",
            startDate,
            endDate,
            partySize,
            eventType,
            guestMessage: message || null,
            quotedTotalCents: quote.totalCents,
            blocksEstate: space.blocksEstate,
            source: "website",
          })
          .returning();
        booking = row;
      } catch (error) {
        const text = error instanceof Error ? error.message : String(error);
        const isUniqueCollision =
          text.includes("bookings_reference_unique") ||
          text.includes("bookings_manage_token_unique");
        if (!isUniqueCollision) throw error;
      }
    }
    if (!booking) {
      return { error: "Something went wrong saving your request — please try again." };
    }
    manageToken = booking.manageToken;

    // Emails are best-effort; the request is already safely stored.
    const policy = await getCancellationPolicy();
    const emailData = {
      reference: booking.reference,
      spaceName: space.name,
      isEvent: space.isEvent,
      startDate,
      endDate,
      partySize,
      guestFirstName: firstName,
      manageToken: booking.manageToken,
      quote,
      policy,
    };
    await Promise.all([
      sendEmail({
        to: email,
        ...requestReceivedEmail(emailData),
      }),
      sendEmail({
        to: await getNotifyEmail(),
        replyTo: email,
        ...ownerNewRequestEmail({
          ...emailData,
          guestFullName: `${firstName} ${lastName}`,
          guestEmail: email,
          guestPhone: phone || null,
          message: message || null,
          eventType,
        }),
      }),
    ]);
  } catch (error) {
    console.error("Booking request failed:", error);
    return {
      error: "Something went wrong sending your request. Please try again, or call us.",
    };
  }

  redirect(`/bookings/${manageToken}?submitted=1`);
}
