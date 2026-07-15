"use server";

import { revalidatePath } from "next/cache";
import { eq } from "drizzle-orm";
import { db } from "@/lib/db";
import { enquiries, type Enquiry } from "@/lib/db/schema";
import { requireAdmin } from "@/lib/auth/require-admin";

const STATUSES: Enquiry["status"][] = ["new", "replied", "converted", "archived"];

export async function setEnquiryStatus(formData: FormData): Promise<void> {
  try {
    await requireAdmin();
    const id = typeof formData.get("enquiryId") === "string" ? (formData.get("enquiryId") as string) : "";
    const raw = formData.get("status");
    const status = STATUSES.find((s) => s === raw);
    if (!id || !status) return;
    await db.update(enquiries).set({ status }).where(eq(enquiries.id, id));
    revalidatePath("/admin/enquiries");
    revalidatePath("/admin");
  } catch (error) {
    console.error("Enquiry status update failed:", error);
  }
}
