import Link from "next/link";
import {
  ArrowUpRight,
  CalendarClock,
  CalendarDays,
  Inbox,
  Landmark,
} from "lucide-react";
import { adminNav } from "@/lib/admin";
import { getDashboardData } from "@/lib/db/queries";
import { formatDayMonth, formatMonth, todayAtEstate } from "@/lib/booking/dates";
import { formatMoney } from "@/lib/booking/pricing";
import { PageHeader, Card } from "./components/page-shell";

export const dynamic = "force-dynamic";
export const metadata = { title: "Dashboard" };

// Everything except the dashboard itself, surfaced as quick links.
const shortcuts = adminNav.filter((item) => item.href !== "/admin");

export default async function AdminDashboardPage() {
  const today = todayAtEstate();
  const data = await getDashboardData(today);

  const stats = [
    {
      label: "Requests to review",
      value: String(data.pendingCount),
      icon: CalendarClock,
      href: "/admin/bookings?tab=pending",
    },
    {
      label: "Arriving in the next 14 days",
      value: String(data.arrivalsSoon.length),
      icon: CalendarDays,
      href: "/admin/bookings?tab=upcoming",
    },
    {
      label: `Booked for ${formatMonth(data.monthLabel)}`,
      value: formatMoney(data.monthRevenueCents),
      icon: Landmark,
      href: "/admin/bookings?tab=upcoming",
    },
    {
      label: "New enquiries",
      value: String(data.newEnquiryCount),
      icon: Inbox,
      href: "/admin/enquiries?status=new",
    },
  ];

  return (
    <div className="space-y-8">
      <PageHeader
        title="Welcome back"
        description="A home base for managing bookings, enquiries and everything guests see on the Vine Cliff website."
      />

      <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
        {stats.map((stat) => {
          const Icon = stat.icon;
          return (
            <Link key={stat.label} href={stat.href}>
              <Card className="flex h-full items-center gap-4 transition-colors hover:border-pine-400">
                <div className="flex size-11 shrink-0 items-center justify-center rounded-xl bg-pine-50 text-pine-600">
                  <Icon className="size-5" />
                </div>
                <div>
                  <p className="font-display text-2xl text-ink">{stat.value}</p>
                  <p className="text-sm text-ink-soft">{stat.label}</p>
                </div>
              </Card>
            </Link>
          );
        })}
      </div>

      <div className="grid gap-6 lg:grid-cols-2">
        <Card>
          <div className="flex items-center justify-between">
            <h2 className="font-display text-lg text-ink">Waiting on you</h2>
            <Link
              href="/admin/bookings?tab=pending"
              className="text-sm font-medium text-pine-700 hover:text-amber"
            >
              All pending →
            </Link>
          </div>
          {data.pendingRequests.length === 0 ? (
            <p className="mt-3 text-sm text-stone">
              No pending requests — new ones land here the moment guests submit them.
            </p>
          ) : (
            <ul className="mt-3 divide-y divide-pine-100">
              {data.pendingRequests.map(({ booking, space, guest }) => (
                <li key={booking.id}>
                  <Link
                    href={`/admin/bookings/${booking.id}`}
                    className="flex items-center gap-3 py-2.5 text-sm transition-colors hover:text-pine-700"
                  >
                    <span className="font-medium text-ink">
                      {guest.firstName} {guest.lastName}
                    </span>
                    <span className="text-ink-soft">{space.name}</span>
                    <span className="ml-auto text-xs text-stone">
                      {formatDayMonth(booking.startDate)} → {formatDayMonth(booking.endDate)}
                    </span>
                    <span className="w-16 text-right font-medium text-ink">
                      {formatMoney(booking.quotedTotalCents)}
                    </span>
                  </Link>
                </li>
              ))}
            </ul>
          )}
        </Card>

        <Card>
          <div className="flex items-center justify-between">
            <h2 className="font-display text-lg text-ink">Next arrivals</h2>
            <Link
              href="/admin/calendar"
              className="text-sm font-medium text-pine-700 hover:text-amber"
            >
              Calendar →
            </Link>
          </div>
          {data.arrivalsSoon.length === 0 ? (
            <p className="mt-3 text-sm text-stone">Nothing arriving in the next two weeks.</p>
          ) : (
            <ul className="mt-3 divide-y divide-pine-100">
              {data.arrivalsSoon.map(({ booking, space, guest }) => (
                <li key={booking.id}>
                  <Link
                    href={`/admin/bookings/${booking.id}`}
                    className="flex items-center gap-3 py-2.5 text-sm transition-colors hover:text-pine-700"
                  >
                    <span className="w-14 shrink-0 font-medium text-pine-700">
                      {formatDayMonth(booking.startDate)}
                    </span>
                    <span className="font-medium text-ink">
                      {guest.firstName} {guest.lastName}
                    </span>
                    <span className="text-ink-soft">{space.name}</span>
                    <span className="ml-auto text-xs text-stone">
                      {booking.partySize} guests
                    </span>
                  </Link>
                </li>
              ))}
            </ul>
          )}
        </Card>
      </div>

      <section>
        <h2 className="text-sm font-semibold uppercase tracking-wide text-stone">Manage</h2>
        <div className="mt-3 grid gap-4 sm:grid-cols-2">
          {shortcuts.map((item) => {
            const Icon = item.icon;
            return (
              <Link
                key={item.href}
                href={item.href}
                className="group flex items-start gap-4 rounded-2xl border border-pine-100 bg-cream-100 p-5 transition-colors hover:border-pine-400"
              >
                <div className="flex size-10 items-center justify-center rounded-xl bg-pine-50 text-pine-600">
                  <Icon className="size-5" />
                </div>
                <div className="flex-1">
                  <p className="flex items-center gap-1 font-medium text-ink">
                    {item.label}
                    <ArrowUpRight className="size-4 text-stone transition-colors group-hover:text-pine-600" />
                  </p>
                  <p className="mt-0.5 text-sm text-ink-soft">{item.description}</p>
                </div>
              </Link>
            );
          })}
        </div>
      </section>
    </div>
  );
}
