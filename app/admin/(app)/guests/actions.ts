"use server";

import { revalidatePath } from "next/cache";
import { eq } from "drizzle-orm";
import { db } from "@/lib/db";
import { guests } from "@/lib/db/schema";
import { requireAdmin } from "@/lib/auth/require-admin";
import type { AdminActionState } from "../bookings/actions";

export async function saveGuestNotes(
  _previous: AdminActionState,
  formData: FormData
): Promise<AdminActionState> {
  try {
    await requireAdmin();
    const id = typeof formData.get("guestId") === "string" ? (formData.get("guestId") as string) : "";
    const raw = formData.get("notes");
    const notes = typeof raw === "string" ? raw.trim().slice(0, 4000) : "";
    await db
      .update(guests)
      .set({ notes: notes || null })
      .where(eq(guests.id, id));
    revalidatePath(`/admin/guests/${id}`);
    revalidatePath("/admin/guests");
    return { ok: true };
  } catch (error) {
    console.error("Guest notes update failed:", error);
    return { error: "Could not save notes — please try again." };
  }
}
