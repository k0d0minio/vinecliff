// Status chips shared across the admin. Server-safe (no hooks).
import { cn } from "@/lib/utils";
import type { Booking, Enquiry } from "@/lib/db/schema";

const chip =
  "inline-flex items-center rounded-full px-2.5 py-0.5 text-xs font-medium whitespace-nowrap";

const BOOKING_STYLES: Record<string, string> = {
  pending: "bg-amber/15 text-[#9a5a12]",
  approved: "bg-pine-50 text-pine-700",
  declined: "bg-parchment text-stone",
  cancelled: "bg-parchment text-stone line-through decoration-stone/50",
  completed: "bg-lake/10 text-lake",
};

export function BookingStatusBadge({
  status,
  completed = false,
}: {
  status: Booking["status"];
  completed?: boolean;
}) {
  const key = completed && status === "approved" ? "completed" : status;
  return <span className={cn(chip, BOOKING_STYLES[key])}>{key}</span>;
}

const PAYMENT_LABELS: Record<Booking["paymentStatus"], string> = {
  unpaid: "unpaid",
  deposit_paid: "deposit paid",
  paid: "paid",
  refunded: "refunded",
};

const PAYMENT_STYLES: Record<Booking["paymentStatus"], string> = {
  unpaid: "bg-parchment text-stone",
  deposit_paid: "bg-amber/15 text-[#9a5a12]",
  paid: "bg-pine-50 text-pine-700",
  refunded: "bg-lake/10 text-lake",
};

export function PaymentStatusBadge({ status }: { status: Booking["paymentStatus"] }) {
  return <span className={cn(chip, PAYMENT_STYLES[status])}>{PAYMENT_LABELS[status]}</span>;
}

const ENQUIRY_STYLES: Record<Enquiry["status"], string> = {
  new: "bg-amber/15 text-[#9a5a12]",
  replied: "bg-pine-50 text-pine-700",
  converted: "bg-lake/10 text-lake",
  archived: "bg-parchment text-stone",
};

export function EnquiryStatusBadge({ status }: { status: Enquiry["status"] }) {
  return <span className={cn(chip, ENQUIRY_STYLES[status])}>{status}</span>;
}

/** Small alert chip, e.g. "cancellation requested". */
export function AlertBadge({ children }: { children: React.ReactNode }) {
  return <span className={cn(chip, "bg-amber/15 text-[#9a5a12]")}>{children}</span>;
}
