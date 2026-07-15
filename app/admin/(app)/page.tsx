import Link from "next/link";
import { ArrowUpRight, CalendarDays, Inbox, Users } from "lucide-react";
import { adminNav } from "@/lib/admin";
import { PageHeader, Card } from "./components/page-shell";

export const metadata = { title: "Dashboard" };

// Placeholder figures — these will be replaced with live data later.
const stats = [
  { label: "Upcoming bookings", value: "—", icon: CalendarDays },
  { label: "New enquiries", value: "—", icon: Inbox },
  { label: "Guests this month", value: "—", icon: Users },
];

// Everything except the dashboard itself, surfaced as quick links.
const shortcuts = adminNav.filter((item) => item.href !== "/admin");

export default function AdminDashboardPage() {
  return (
    <div className="space-y-8">
      <PageHeader
        title="Welcome back"
        description="A home base for managing bookings, enquiries and everything guests see on the Vine Cliff website."
      />

      <div className="grid gap-4 sm:grid-cols-3">
        {stats.map((stat) => {
          const Icon = stat.icon;
          return (
            <Card key={stat.label} className="flex items-center gap-4">
              <div className="flex size-11 items-center justify-center rounded-xl bg-pine-50 text-pine-600">
                <Icon className="size-5" />
              </div>
              <div>
                <p className="font-display text-2xl text-ink">{stat.value}</p>
                <p className="text-sm text-ink-soft">{stat.label}</p>
              </div>
            </Card>
          );
        })}
      </div>

      <section>
        <h2 className="text-sm font-semibold uppercase tracking-wide text-stone">
          Manage
        </h2>
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
                  <p className="mt-0.5 text-sm text-ink-soft">
                    {item.description}
                  </p>
                </div>
              </Link>
            );
          })}
        </div>
      </section>
    </div>
  );
}
