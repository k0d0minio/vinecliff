// Estate-wide settings stored as key/value rows and edited in /admin/settings.
import { eq } from "drizzle-orm";
import { db } from "@/lib/db";
import { settings } from "@/lib/db/schema";
import { site } from "@/lib/site";

export const SETTING_KEYS = {
  notifyEmail: "notify_email",
  cancellationPolicy: "cancellation_policy",
} as const;

export async function getSetting(key: string): Promise<string | null> {
  const [row] = await db
    .select({ value: settings.value })
    .from(settings)
    .where(eq(settings.key, key))
    .limit(1);
  return row?.value ?? null;
}

export async function setSetting(key: string, value: string): Promise<void> {
  await db
    .insert(settings)
    .values({ key, value })
    .onConflictDoUpdate({
      target: settings.key,
      set: { value, updatedAt: new Date() },
    });
}

/** Where owner notifications (new requests, enquiries, cancellations) go. */
export async function getNotifyEmail(): Promise<string> {
  return (await getSetting(SETTING_KEYS.notifyEmail)) ?? site.email;
}

/** Guest-facing cancellation policy, shown on forms, status pages and emails. */
export async function getCancellationPolicy(): Promise<string | null> {
  return getSetting(SETTING_KEYS.cancellationPolicy);
}
