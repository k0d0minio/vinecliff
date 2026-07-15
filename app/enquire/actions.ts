"use server";

import { redirect } from "next/navigation";
import { db } from "@/lib/db";
import { enquiries } from "@/lib/db/schema";
import { getSpaceBySlug } from "@/lib/db/queries";
import { getNotifyEmail } from "@/lib/settings";
import { ownerNewEnquiryEmail, sendEmail } from "@/lib/email";

export type EnquiryFormState = { error?: string; sent?: boolean };

function cleanText(value: FormDataEntryValue | null, maxLength: number): string {
  return typeof value === "string" ? value.trim().slice(0, maxLength) : "";
}

const EMAIL_PATTERN = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;

export async function submitEnquiry(
  _previous: EnquiryFormState,
  formData: FormData
): Promise<EnquiryFormState> {
  if (cleanText(formData.get("website"), 100)) redirect("/");

  const name = cleanText(formData.get("name"), 160);
  const email = cleanText(formData.get("email"), 200).toLowerCase();
  const phone = cleanText(formData.get("phone"), 40);
  const spaceSlug = cleanText(formData.get("space"), 100);
  const message = cleanText(formData.get("message"), 4000);

  if (!name) return { error: "Please tell us your name." };
  if (!EMAIL_PATTERN.test(email)) {
    return { error: "That email address doesn't look right." };
  }
  if (message.length < 5) {
    return { error: "Tell us a little about what you're planning." };
  }

  try {
    const space = spaceSlug ? await getSpaceBySlug(spaceSlug) : null;

    await db.insert(enquiries).values({
      name,
      email,
      phone: phone || null,
      spaceId: space?.id ?? null,
      message,
    });

    await sendEmail({
      to: await getNotifyEmail(),
      replyTo: email,
      ...ownerNewEnquiryEmail({
        name,
        email,
        phone: phone || null,
        spaceName: space?.name ?? null,
        message,
      }),
    });
  } catch (error) {
    console.error("Enquiry failed:", error);
    return { error: "Something went wrong — please try again, or just call us." };
  }

  return { sent: true };
}
