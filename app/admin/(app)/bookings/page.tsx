import Link from "next/link";
import { CalendarDays, Plus, Search } from "lucide-react";
import { cn } from "@/lib/utils";
import { buttonVariants } from "@/app/components/ui/button";
import { Input } from "@/app/components/ui/field";
import { listBookingsForAdmin, type BookingTab } from "@/lib/db/queries";
import { formatDayMonth, todayAtEstate } from "@/lib/booking/dates";
import { formatMoney } from "@/lib/booking/pricing";
import { PageHeader, EmptyState } from "../components/page-shell";
import { AlertBadge, BookingStatusBadge, PaymentStatusBadge } from "../components/badges";

export const dynamic = "force-dynamic";
export const metadata = { title: "Bookings" };

const TABS: Array<{ key: BookingTab; label: string }> = [
  { key: "pending", label: "Pending" },
  { key: "upcoming", label: "Upcoming" },
  { key: "past", label: "Past" },
  { key: "archive", label: "Declined & cancelled" },
  { key: "all", label: "All" },
];

type Props = { searchParams: Promise<{ tab?: string; q?: string }> };

export default async function BookingsPage({ searchParams }: Props) {
  const params = await searchParams;
  const tab: BookingTab = TABS.some((t) => t.key === params.tab)
    ? (params.tab as BookingTab)
    : params.q
      ? "all"
      : "pending";
  const q = params.q?.trim() || undefined;
  const today = todayAtEstate();
  const rows = await listBookingsForAdmin({ tab, q, today });

  return (
    <div className="space-y-6">
      <PageHeader
        title="Bookings"
        description="Requests to review, plus every stay and event across the estate."
        actions={
          <Link
            href="/admin/bookings/new"
            className={cn(buttonVariants({ variant: "primary", size: "sm" }))}
          >
            <Plus className="size-4" />
            New booking
          </Link>
        }
      />

      <div className="flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between">
        <nav className="flex flex-wrap gap-2">
          {TABS.map((t) => (
            <Link
              key={t.key}
              href={`/admin/bookings?tab=${t.key}${q ? `&q=${encodeURIComponent(q)}` : ""}`}
              className={cn(
                "rounded-full px-3.5 py-1.5 text-sm font-medium transition-colors",
                tab === t.key
                  ? "bg-pine-700 text-cream"
                  : "bg-cream-100 text-ink-soft hover:bg-pine-50"
              )}
            >
              {t.label}
            </Link>
          ))}
        </nav>
        <form action="/admin/bookings" className="relative sm:w-64">
          <input type="hidden" name="tab" value={tab} />
          <Search className="pointer-events-none absolute left-3.5 top-1/2 size-4 -translate-y-1/2 text-stone" />
          <Input
            name="q"
            defaultValue={q}
            placeholder="Reference, name or email"
            className="h-10 pl-10"
          />
        </form>
      </div>

      {rows.length === 0 ? (
        <EmptyState
          icon={CalendarDays}
          title={q ? "Nothing matches that search" : "Nothing here yet"}
          description={
            tab === "pending"
              ? "New booking requests from the website will land here for you to approve or decline."
              : "Bookings in this view will appear as they come in."
          }
        />
      ) : (
        <ul className="space-y-3">
          {rows.map(({ booking, space, guest }) => {
            const completed = booking.status === "approved" && booking.endDate <= today;
            return (
              <li key={booking.id}>
                <Link
                  href={`/admin/bookings/${booking.id}`}
                  className="flex flex-wrap items-center gap-x-6 gap-y-2 rounded-2xl border border-pine-100 bg-cream-100 p-4 transition-colors hover:border-pine-400 sm:px-5"
                >
                  <div className="min-w-40">
                    <p className="font-medium text-ink">
                      {guest.firstName} {guest.lastName}
                    </p>
                    <p className="text-xs text-stone">
                      {booking.reference} · {space.name}
                    </p>
                  </div>
                  <div className="text-sm text-ink-soft">
                    {formatDayMonth(booking.startDate)} → {formatDayMonth(booking.endDate)}
                    <span className="ml-2 text-xs text-stone">
                      {booking.partySize} guests
                    </span>
                  </div>
                  <div className="ml-auto flex flex-wrap items-center gap-2">
                    {booking.cancelRequestedAt && booking.status === "approved" ? (
                      <AlertBadge>cancel requested</AlertBadge>
                    ) : null}
                    {booking.status === "approved" ? (
                      <PaymentStatusBadge status={booking.paymentStatus} />
                    ) : null}
                    <BookingStatusBadge status={booking.status} completed={completed} />
                    <span className="w-20 text-right text-sm font-medium text-ink">
                      {formatMoney(booking.finalTotalCents ?? booking.quotedTotalCents)}
                    </span>
                  </div>
                </Link>
              </li>
            );
          })}
        </ul>
      )}
    </div>
  );
}
