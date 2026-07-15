import Link from "next/link";
import { notFound } from "next/navigation";
import { ArrowLeft, CalendarDays, Mail, Phone } from "lucide-react";
import { getGuestWithBookings } from "@/lib/db/queries";
import { formatDayMonth, todayAtEstate } from "@/lib/booking/dates";
import { formatMoney } from "@/lib/booking/pricing";
import { PageHeader, Card } from "../../components/page-shell";
import { BookingStatusBadge } from "../../components/badges";
import { GuestNotesForm } from "../guest-notes-form";

export const dynamic = "force-dynamic";
export const metadata = { title: "Guest" };

type Props = { params: Promise<{ id: string }> };

export default async function GuestDetailPage({ params }: Props) {
  const { id } = await params;
  const data = await getGuestWithBookings(id).catch(() => null);
  if (!data) notFound();
  const { guest, bookings } = data;
  const today = todayAtEstate();
  const totalSpentCents = bookings
    .filter(({ booking }) => booking.status === "approved")
    .reduce(
      (sum, { booking }) => sum + (booking.finalTotalCents ?? booking.quotedTotalCents),
      0
    );

  return (
    <div className="space-y-6">
      <Link
        href="/admin/guests"
        className="inline-flex items-center gap-1.5 text-sm font-medium text-pine-700 hover:text-amber"
      >
        <ArrowLeft className="size-4" />
        All guests
      </Link>

      <PageHeader
        title={`${guest.firstName} ${guest.lastName}`}
        description={`Guest since ${formatDayMonth(guest.createdAt.toISOString().slice(0, 10))}, ${guest.createdAt.getUTCFullYear()}${totalSpentCents > 0 ? ` · ${formatMoney(totalSpentCents)} booked all-time` : ""}`}
      />

      <div className="grid gap-6 lg:grid-cols-[24rem_1fr]">
        <div className="space-y-6">
          <Card>
            <h2 className="font-display text-lg text-ink">Contact</h2>
            <div className="mt-3 space-y-2 text-sm text-ink-soft">
              <a
                href={`mailto:${guest.email}`}
                className="flex items-center gap-2 hover:text-pine-700"
              >
                <Mail className="size-4 text-stone" />
                {guest.email}
              </a>
              {guest.phone ? (
                <a href={`tel:${guest.phone}`} className="flex items-center gap-2 hover:text-pine-700">
                  <Phone className="size-4 text-stone" />
                  {guest.phone}
                </a>
              ) : (
                <p className="text-stone">No phone on file.</p>
              )}
            </div>
          </Card>

          <Card>
            <h2 className="font-display text-lg text-ink">Private notes</h2>
            <div className="mt-3">
              <GuestNotesForm guestId={guest.id} defaultNotes={guest.notes ?? ""} />
            </div>
          </Card>
        </div>

        <Card>
          <h2 className="font-display text-lg text-ink">Bookings</h2>
          {bookings.length === 0 ? (
            <p className="mt-3 text-sm text-stone">No bookings yet.</p>
          ) : (
            <ul className="mt-3 divide-y divide-pine-100">
              {bookings.map(({ booking, space }) => (
                <li key={booking.id}>
                  <Link
                    href={`/admin/bookings/${booking.id}`}
                    className="flex flex-wrap items-center gap-x-4 gap-y-1 py-3 transition-colors hover:text-pine-700"
                  >
                    <CalendarDays className="size-4 text-stone" />
                    <span className="text-sm font-medium text-ink">{booking.reference}</span>
                    <span className="text-sm text-ink-soft">{space.name}</span>
                    <span className="text-sm text-ink-soft">
                      {formatDayMonth(booking.startDate)} → {formatDayMonth(booking.endDate)}
                    </span>
                    <span className="ml-auto flex items-center gap-3">
                      <BookingStatusBadge
                        status={booking.status}
                        completed={booking.status === "approved" && booking.endDate <= today}
                      />
                      <span className="w-20 text-right text-sm font-medium text-ink">
                        {formatMoney(booking.finalTotalCents ?? booking.quotedTotalCents)}
                      </span>
                    </span>
                  </Link>
                </li>
              ))}
            </ul>
          )}
        </Card>
      </div>
    </div>
  );
}
