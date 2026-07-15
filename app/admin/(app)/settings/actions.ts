"use server";

import { revalidatePath } from "next/cache";
import { requireAdmin } from "@/lib/auth/require-admin";
import { SETTING_KEYS, setSetting } from "@/lib/settings";
import type { AdminActionState } from "../bookings/actions";

const EMAIL_PATTERN = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;

export async function saveSettings(
  _previous: AdminActionState,
  formData: FormData
): Promise<AdminActionState> {
  try {
    await requireAdmin();
    const notifyEmailRaw = formData.get("notifyEmail");
    const policyRaw = formData.get("cancellationPolicy");
    const notifyEmail =
      typeof notifyEmailRaw === "string" ? notifyEmailRaw.trim().slice(0, 200) : "";
    const policy = typeof policyRaw === "string" ? policyRaw.trim().slice(0, 2000) : "";

    if (!EMAIL_PATTERN.test(notifyEmail)) {
      return { error: "The notification email doesn't look right." };
    }

    await Promise.all([
      setSetting(SETTING_KEYS.notifyEmail, notifyEmail),
      setSetting(SETTING_KEYS.cancellationPolicy, policy),
    ]);

    revalidatePath("/admin/settings");
    return { ok: true };
  } catch (error) {
    console.error("Settings save failed:", error);
    return { error: "Could not save settings — please try again." };
  }
}
