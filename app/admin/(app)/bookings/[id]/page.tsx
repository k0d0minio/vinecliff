import Link from "next/link";
import { notFound } from "next/navigation";
import { ArrowLeft, ExternalLink, Mail, Phone } from "lucide-react";
import { getAvailabilityData, getBookingWithRelations } from "@/lib/db/queries";
import { blockedRanges } from "@/lib/booking/availability";
import {
  formatDate,
  diffDays,
  rangesOverlap,
  todayAtEstate,
} from "@/lib/booking/dates";
import { formatMoney, unitLabel } from "@/lib/booking/pricing";
import { siteBaseUrl } from "@/lib/email";
import { PageHeader, Card } from "../../components/page-shell";
import { AlertBadge, BookingStatusBadge, PaymentStatusBadge } from "../../components/badges";
import {
  ApprovedActions,
  NotesForm,
  PendingActions,
  type BookingActionData,
} from "./booking-actions";

export const dynamic = "force-dynamic";
export const metadata = { title: "Booking" };

type Props = { params: Promise<{ id: string }> };

export default async function BookingDetailPage({ params }: Props) {
  const { id } = await params;
  const row = await getBookingWithRelations(id).catch(() => null);
  if (!row) notFound();
  const { booking, space, guest } = row;

  const today = todayAtEstate();
  const completed = booking.status === "approved" && booking.endDate <= today;
  const nights = diffDays(booking.startDate, booking.endDate);

  // For pending requests, warn when the dates have since been taken.
  let conflict = false;
  if (booking.status === "pending") {
    const availability = await getAvailabilityData(booking.startDate, booking.endDate);
    const blocked = blockedRanges(space, availability.bookings, availability.blackouts);
    conflict = blocked.some((r) =>
      rangesOverlap(booking.startDate, booking.endDate, r.startDate, r.endDate)
    );
  }

  const actionData: BookingActionData = {
    id: booking.id,
    status: booking.status,
    quotedTotalCents: booking.quotedTotalCents,
    finalTotalCents: booking.finalTotalCents,
    depositCents: booking.depositCents,
    paymentStatus: booking.paymentStatus,
    blocksEstate: booking.blocksEstate,
    cancelRequested: Boolean(booking.cancelRequestedAt),
    conflict,
    isEvent: space.isEvent,
  };

  const detailRows: Array<[string, React.ReactNode]> = [
    ["Space", space.name],
    [space.isEvent ? "First day" : "Check-in", formatDate(booking.startDate)],
    [space.isEvent ? "Departure day" : "Checkout", formatDate(booking.endDate)],
    ["Length", `${nights} ${unitLabel(space, nights)}`],
    ["Guests", String(booking.partySize)],
    ...(booking.eventType
      ? ([["Occasion", booking.eventType]] as Array<[string, string]>)
      : []),
    ["Source", booking.source],
    ["Requested", formatDate(booking.createdAt.toISOString().slice(0, 10))],
    ["Reserves whole estate", booking.blocksEstate ? "Yes" : "No"],
  ];

  return (
    <div className="space-y-6">
      <Link
        href="/admin/bookings"
        className="inline-flex items-center gap-1.5 text-sm font-medium text-pine-700 hover:text-amber"
      >
        <ArrowLeft className="size-4" />
        All bookings
      </Link>

      <PageHeader
        title={booking.reference}
        description={`${guest.firstName} ${guest.lastName} · ${space.name}`}
        actions={
          <div className="flex flex-wrap items-center gap-2">
            {booking.cancelRequestedAt && booking.status === "approved" ? (
              <AlertBadge>cancel requested</AlertBadge>
            ) : null}
            {booking.status === "approved" ? (
              <PaymentStatusBadge status={booking.paymentStatus} />
            ) : null}
            <BookingStatusBadge status={booking.status} completed={completed} />
          </div>
        }
      />

      <div className="grid gap-6 lg:grid-cols-[1fr_24rem]">
        <div className="space-y-6">
          <Card>
            <h2 className="font-display text-lg text-ink">Details</h2>
            <dl className="mt-3 divide-y divide-pine-100">
              {detailRows.map(([label, value]) => (
                <div key={label} className="flex items-center justify-between gap-4 py-2.5">
                  <dt className="text-sm text-stone">{label}</dt>
                  <dd className="text-right text-sm text-ink">{value}</dd>
                </div>
              ))}
              <div className="flex items-center justify-between gap-4 py-2.5">
                <dt className="text-sm text-stone">Quoted estimate</dt>
                <dd className="text-right text-sm text-ink">
                  {formatMoney(booking.quotedTotalCents)}
                </dd>
              </div>
              <div className="flex items-center justify-between gap-4 py-2.5">
                <dt className="text-sm text-stone">Final total</dt>
                <dd className="text-right text-sm font-semibold text-ink">
                  {booking.finalTotalCents !== null
                    ? formatMoney(booking.finalTotalCents)
                    : "—"}
                </dd>
              </div>
              {booking.depositCents !== null ? (
                <div className="flex items-center justify-between gap-4 py-2.5">
                  <dt className="text-sm text-stone">Deposit</dt>
                  <dd className="text-right text-sm text-ink">
                    {formatMoney(booking.depositCents)}
                  </dd>
                </div>
              ) : null}
            </dl>
            {booking.guestMessage ? (
              <blockquote className="mt-4 rounded-2xl bg-cream px-4 py-3 text-sm leading-relaxed text-ink-soft">
                “{booking.guestMessage}”
              </blockquote>
            ) : null}
            {booking.decisionNote ? (
              <p className="mt-3 text-xs text-stone">
                Note sent to guest: “{booking.decisionNote}”
              </p>
            ) : null}
            <p className="mt-4 text-xs text-stone">
              Guest status page:{" "}
              <a
                href={`${siteBaseUrl()}/bookings/${booking.manageToken}`}
                target="_blank"
                rel="noopener noreferrer"
                className="inline-flex items-center gap-1 font-medium text-pine-700 hover:text-amber"
              >
                open <ExternalLink className="size-3" />
              </a>
            </p>
          </Card>

          <Card>
            <h2 className="font-display text-lg text-ink">Guest</h2>
            <p className="mt-3 font-medium text-ink">
              {guest.firstName} {guest.lastName}
            </p>
            <div className="mt-2 space-y-1.5 text-sm text-ink-soft">
              <a
                href={`mailto:${guest.email}?subject=Your Vine Cliff booking ${booking.reference}`}
                className="flex items-center gap-2 hover:text-pine-700"
              >
                <Mail className="size-4 text-stone" />
                {guest.email}
              </a>
              {guest.phone ? (
                <a
                  href={`tel:${guest.phone}`}
                  className="flex items-center gap-2 hover:text-pine-700"
                >
                  <Phone className="size-4 text-stone" />
                  {guest.phone}
                </a>
              ) : null}
            </div>
            <Link
              href={`/admin/guests/${guest.id}`}
              className="mt-4 inline-block text-sm font-medium text-pine-700 hover:text-amber"
            >
              View guest history →
            </Link>
          </Card>

          <Card>
            <h2 className="font-display text-lg text-ink">Private notes</h2>
            <div className="mt-3">
              <NotesForm bookingId={booking.id} defaultNotes={booking.adminNotes ?? ""} />
            </div>
          </Card>
        </div>

        <div className="space-y-6">
          <Card>
            <h2 className="font-display text-lg text-ink">
              {booking.status === "pending"
                ? "Review this request"
                : booking.status === "approved"
                  ? "Manage booking"
                  : "History"}
            </h2>
            <div className="mt-4">
              {booking.status === "pending" ? (
                <PendingActions booking={actionData} />
              ) : booking.status === "approved" ? (
                <ApprovedActions booking={actionData} />
              ) : (
                <p className="text-sm leading-relaxed text-ink-soft">
                  This booking was {booking.status}
                  {booking.decidedAt
                    ? ` on ${formatDate(booking.decidedAt.toISOString().slice(0, 10))}`
                    : ""}
                  . The dates are free again — if the guest comes back, create a new booking
                  for them.
                </p>
              )}
            </div>
          </Card>
        </div>
      </div>
    </div>
  );
}
