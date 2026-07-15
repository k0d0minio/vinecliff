"use server";

import { revalidatePath } from "next/cache";
import { eq } from "drizzle-orm";
import { db } from "@/lib/db";
import { blackouts } from "@/lib/db/schema";
import { requireAdmin } from "@/lib/auth/require-admin";
import { addDays, isValidISODate } from "@/lib/booking/dates";
import type { AdminActionState } from "../bookings/actions";

function text(formData: FormData, name: string, maxLength = 400): string {
  const value = formData.get(name);
  return typeof value === "string" ? value.trim().slice(0, maxLength) : "";
}

export async function createBlackout(
  _previous: AdminActionState,
  formData: FormData
): Promise<AdminActionState> {
  try {
    await requireAdmin();
    const spaceId = text(formData, "spaceId", 40) || null;
    const firstDay = text(formData, "firstDay", 10);
    const lastDay = text(formData, "lastDay", 10);
    const reason = text(formData, "reason", 200) || null;

    if (!isValidISODate(firstDay) || !isValidISODate(lastDay)) {
      return { error: "Pick both days." };
    }
    if (lastDay < firstDay) {
      return { error: "The last blocked day can't be before the first." };
    }

    await db.insert(blackouts).values({
      spaceId,
      startDate: firstDay,
      // Stored half-open like bookings: the space reopens the day after.
      endDate: addDays(lastDay, 1),
      reason,
    });

    revalidatePath("/admin/calendar");
    revalidatePath("/admin");
    return { ok: true };
  } catch (error) {
    console.error("Blackout create failed:", error);
    return { error: "Could not add the blackout — please try again." };
  }
}

export async function deleteBlackout(formData: FormData): Promise<void> {
  try {
    await requireAdmin();
    const id = text(formData, "blackoutId", 40);
    if (id) await db.delete(blackouts).where(eq(blackouts.id, id));
    revalidatePath("/admin/calendar");
  } catch (error) {
    console.error("Blackout delete failed:", error);
  }
}
