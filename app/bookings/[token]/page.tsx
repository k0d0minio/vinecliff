import type { Metadata } from "next";
import Link from "next/link";
import { notFound } from "next/navigation";
import {
  Ban,
  CalendarCheck,
  CheckCircle2,
  Clock,
  Mail,
  MailCheck,
  Phone,
  XCircle,
  type LucideIcon,
} from "lucide-react";
import { Nav } from "@/app/components/nav";
import { Footer } from "@/app/components/footer";
import { site } from "@/lib/site";
import { getBookingByManageToken } from "@/lib/db/queries";
import { getCancellationPolicy } from "@/lib/settings";
import { formatDate, todayAtEstate } from "@/lib/booking/dates";
import { formatMoney } from "@/lib/booking/pricing";
import { CancelControls } from "./cancel-controls";

export const dynamic = "force-dynamic";

export const metadata: Metadata = {
  title: "Your booking",
  robots: { index: false, follow: false },
};

type Props = {
  params: Promise<{ token: string }>;
  searchParams: Promise<{ submitted?: string }>;
};

const STATUS_CONTENT: Record<
  string,
  { icon: LucideIcon; title: string; body: string }
> = {
  pending: {
    icon: Clock,
    title: "Request received",
    body: "We review every request personally and will confirm by email, usually within a day or two.",
  },
  approved: {
    icon: CalendarCheck,
    title: "You're booked",
    body: "Your dates are confirmed — we can't wait to welcome you to the cliff top.",
  },
  completed: {
    icon: CheckCircle2,
    title: "Thanks for staying with us",
    body: "This booking is complete. We'd love to see you at Vine Cliff again.",
  },
  declined: {
    icon: XCircle,
    title: "We couldn't host these dates",
    body: "See our email for details — different dates often work beautifully, so do get in touch.",
  },
  cancelled: {
    icon: Ban,
    title: "This booking is cancelled",
    body: "If that's a surprise, or you'd like to rebook, call or email us any time.",
  },
};

export default async function BookingStatusPage({ params, searchParams }: Props) {
  const [{ token }, { submitted }] = await Promise.all([params, searchParams]);
  const row = await getBookingByManageToken(token);
  if (!row) notFound();

  const { booking, space, guest } = row;
  const policy = await getCancellationPolicy();
  const today = todayAtEstate();
  const isCompleted = booking.status === "approved" && booking.endDate <= today;
  const statusKey = isCompleted ? "completed" : booking.status;
  const status = STATUS_CONTENT[statusKey];
  const StatusIcon = status.icon;

  const total = booking.finalTotalCents ?? booking.quotedTotalCents;
  const paymentLine: string | null =
    booking.status !== "approved"
      ? null
      : booking.paymentStatus === "paid"
        ? "Paid in full — thank you."
        : booking.paymentStatus === "deposit_paid"
          ? `Deposit received${booking.depositCents ? ` (${formatMoney(booking.depositCents)})` : ""} — balance due before arrival.`
          : booking.paymentStatus === "refunded"
            ? "Refunded."
            : "We'll be in touch personally about the deposit and payment.";

  const detailRows: Array<[string, React.ReactNode]> = [
    ["Reference", <strong key="ref">{booking.reference}</strong>],
    [
      "Space",
      <Link
        key="space"
        href={`/spaces/${space.slug}`}
        className="font-medium text-pine-700 hover:text-amber"
      >
        {space.name}
      </Link>,
    ],
    [space.isEvent ? "First day" : "Check-in", formatDate(booking.startDate)],
    [space.isEvent ? "Departure day" : "Checkout", formatDate(booking.endDate)],
    ["Guests", String(booking.partySize)],
    ...(booking.eventType ? ([["Occasion", booking.eventType]] as Array<[string, string]>) : []),
    ["Booked by", `${guest.firstName} ${guest.lastName}`],
  ];

  return (
    <>
      <Nav />
      <main className="bg-cream">
        {/* Dark header band (keeps the fixed nav legible). */}
        <section className="bg-pine-900 px-5 pb-16 pt-32 text-center sm:pb-20 sm:pt-40">
          <div className="mx-auto max-w-2xl">
            <span className="inline-flex size-14 items-center justify-center rounded-full bg-cream/10 text-amber-soft">
              <StatusIcon className="size-7" />
            </span>
            <h1 className="mt-5 font-display text-3xl font-light text-cream sm:text-5xl">
              {status.title}
            </h1>
            <p className="mx-auto mt-4 max-w-lg text-pretty text-sm leading-relaxed text-cream/80 sm:text-base">
              {status.body}
            </p>
          </div>
        </section>

        <section className="mx-auto w-full max-w-2xl space-y-6 px-5 py-12 sm:px-8 sm:py-16">
          {submitted ? (
            <p className="flex items-start gap-2.5 rounded-2xl bg-pine-50 px-5 py-4 text-sm leading-relaxed text-pine-700">
              <MailCheck className="mt-0.5 size-4 shrink-0" />
              Your request is on its way — a confirmation email is heading to {guest.email}.
              Bookmark this page to check your status any time.
            </p>
          ) : null}

          {booking.status === "approved" && booking.cancelRequestedAt ? (
            <p className="flex items-start gap-2.5 rounded-2xl bg-amber/10 px-5 py-4 text-sm leading-relaxed text-[#9a5a12]">
              <Clock className="mt-0.5 size-4 shrink-0" />
              Cancellation requested — we&apos;re reviewing it and will confirm by email shortly.
            </p>
          ) : null}

          <div className="rounded-3xl border border-pine-100 bg-cream-100 p-6 shadow-soft sm:p-7">
            <h2 className="font-display text-xl text-pine-900">Booking details</h2>
            <dl className="mt-4 divide-y divide-pine-100">
              {detailRows.map(([label, value]) => (
                <div key={label} className="flex items-center justify-between gap-4 py-3">
                  <dt className="text-sm text-stone">{label}</dt>
                  <dd className="text-right text-sm text-ink">{value}</dd>
                </div>
              ))}
              <div className="flex items-center justify-between gap-4 py-3">
                <dt className="text-sm text-stone">
                  {booking.status === "pending" ? "Estimated total" : "Total"}
                </dt>
                <dd className="text-right text-sm font-semibold text-ink">
                  {formatMoney(total)}
                </dd>
              </div>
            </dl>
            {booking.status === "pending" ? (
              <p className="mt-3 text-xs leading-relaxed text-stone">
                An estimate — we confirm the final price when we confirm your dates. Nothing is
                charged online.
              </p>
            ) : null}
            {paymentLine ? (
              <p className="mt-3 rounded-xl bg-cream px-4 py-3 text-sm text-ink-soft">
                {paymentLine}
              </p>
            ) : null}
          </div>

          {booking.status === "pending" ? (
            <div className="rounded-3xl border border-pine-100 bg-cream-100 p-6 sm:p-7">
              <h2 className="font-display text-xl text-pine-900">Change of plans?</h2>
              <p className="mb-4 mt-2 text-sm leading-relaxed text-ink-soft">
                You can withdraw a pending request at any time — no questions asked.
              </p>
              <CancelControls token={booking.manageToken} mode="withdraw" />
            </div>
          ) : null}

          {booking.status === "approved" &&
          !isCompleted &&
          !booking.cancelRequestedAt ? (
            <div className="rounded-3xl border border-pine-100 bg-cream-100 p-6 sm:p-7">
              <h2 className="font-display text-xl text-pine-900">Change of plans?</h2>
              <p className="mb-4 mt-2 text-sm leading-relaxed text-ink-soft">
                Need to move or cancel? Send a cancellation request and we&apos;ll take it from
                there — moving dates is often easier than you&apos;d think.
              </p>
              <CancelControls token={booking.manageToken} mode="request" />
            </div>
          ) : null}

          {policy ? (
            <div className="rounded-3xl border border-pine-100 bg-cream-100 p-6 sm:p-7">
              <h2 className="font-display text-xl text-pine-900">Cancellation policy</h2>
              <p className="mt-2 text-sm leading-relaxed text-stone">{policy}</p>
            </div>
          ) : null}

          <p className="text-center text-sm text-ink-soft">
            Questions? Call{" "}
            <a href={site.phoneHref} className="inline-flex items-center gap-1 font-medium text-pine-700 hover:text-amber">
              <Phone className="size-3.5" />
              {site.phone}
            </a>{" "}
            or email{" "}
            <a
              href={`mailto:${site.email}?subject=Booking ${booking.reference}`}
              className="inline-flex items-center gap-1 font-medium text-pine-700 hover:text-amber"
            >
              <Mail className="size-3.5" />
              {site.email}
            </a>
          </p>
        </section>
      </main>
      <Footer />
    </>
  );
}
