"use server";

import { revalidatePath } from "next/cache";
import { eq } from "drizzle-orm";
import { db } from "@/lib/db";
import { bookings } from "@/lib/db/schema";
import { getBookingByManageToken } from "@/lib/db/queries";
import { getNotifyEmail } from "@/lib/settings";
import {
  bookingCancelledEmail,
  ownerCancelRequestedEmail,
  ownerRequestWithdrawnEmail,
  sendEmail,
} from "@/lib/email";

export type ManageBookingState = { error?: string };

function ownerEmailData(
  row: NonNullable<Awaited<ReturnType<typeof getBookingByManageToken>>>
) {
  return {
    reference: row.booking.reference,
    spaceName: row.space.name,
    isEvent: row.space.isEvent,
    startDate: row.booking.startDate,
    endDate: row.booking.endDate,
    partySize: row.booking.partySize,
    guestFirstName: row.guest.firstName,
    manageToken: row.booking.manageToken,
    guestFullName: `${row.guest.firstName} ${row.guest.lastName}`,
    guestEmail: row.guest.email,
  };
}

/** A guest pulls back their own *pending* request — cancels immediately. */
export async function withdrawRequest(
  _previous: ManageBookingState,
  formData: FormData
): Promise<ManageBookingState> {
  const token = typeof formData.get("token") === "string" ? (formData.get("token") as string) : "";
  try {
    const row = await getBookingByManageToken(token);
    if (!row) return { error: "We couldn't find this booking." };
    if (row.booking.status !== "pending") {
      return { error: "This request can no longer be withdrawn — please contact us." };
    }

    await db
      .update(bookings)
      .set({ status: "cancelled", cancelledAt: new Date() })
      .where(eq(bookings.id, row.booking.id));

    const data = ownerEmailData(row);
    await Promise.all([
      sendEmail({ to: row.guest.email, ...bookingCancelledEmail(data) }),
      sendEmail({ to: await getNotifyEmail(), ...ownerRequestWithdrawnEmail(data) }),
    ]);
  } catch (error) {
    console.error("Withdraw request failed:", error);
    return { error: "Something went wrong — please try again or call us." };
  }
  revalidatePath(`/bookings/${token}`);
  return {};
}

/**
 * A guest asks to cancel an *approved* booking. Nothing changes on the
 * calendar — the owner reviews and cancels from the admin.
 */
export async function requestCancellation(
  _previous: ManageBookingState,
  formData: FormData
): Promise<ManageBookingState> {
  const token = typeof formData.get("token") === "string" ? (formData.get("token") as string) : "";
  try {
    const row = await getBookingByManageToken(token);
    if (!row) return { error: "We couldn't find this booking." };
    if (row.booking.status !== "approved") {
      return { error: "Only confirmed bookings can request cancellation." };
    }
    if (row.booking.cancelRequestedAt) return {};

    await db
      .update(bookings)
      .set({ cancelRequestedAt: new Date() })
      .where(eq(bookings.id, row.booking.id));

    await sendEmail({
      to: await getNotifyEmail(),
      replyTo: row.guest.email,
      ...ownerCancelRequestedEmail(ownerEmailData(row)),
    });
  } catch (error) {
    console.error("Cancellation request failed:", error);
    return { error: "Something went wrong — please try again or call us." };
  }
  revalidatePath(`/bookings/${token}`);
  return {};
}
