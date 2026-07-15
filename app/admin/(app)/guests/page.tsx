import Link from "next/link";
import { NotebookPen, Search, Users } from "lucide-react";
import { Input } from "@/app/components/ui/field";
import { listGuestsWithStats } from "@/lib/db/queries";
import { formatDayMonth, todayAtEstate } from "@/lib/booking/dates";
import { PageHeader, EmptyState } from "../components/page-shell";

export const dynamic = "force-dynamic";
export const metadata = { title: "Guests" };

type Props = { searchParams: Promise<{ q?: string }> };

export default async function GuestsPage({ searchParams }: Props) {
  const { q } = await searchParams;
  const query = q?.trim() || undefined;
  const rows = await listGuestsWithStats(query);
  const today = todayAtEstate();

  return (
    <div className="space-y-6">
      <PageHeader
        title="Guests"
        description="Everyone who has booked or requested a stay — with history and your private notes."
        actions={
          <form action="/admin/guests" className="relative w-full sm:w-64">
            <Search className="pointer-events-none absolute left-3.5 top-1/2 size-4 -translate-y-1/2 text-stone" />
            <Input name="q" defaultValue={query} placeholder="Name or email" className="h-10 pl-10" />
          </form>
        }
      />

      {rows.length === 0 ? (
        <EmptyState
          icon={Users}
          title={query ? "No guests match that search" : "No guests yet"}
          description="Guests are added automatically with their first booking request, and deduplicated by email."
        />
      ) : (
        <ul className="space-y-3">
          {rows.map(({ guest, bookingCount, lastStart }) => (
            <li key={guest.id}>
              <Link
                href={`/admin/guests/${guest.id}`}
                className="flex flex-wrap items-center gap-x-6 gap-y-1.5 rounded-2xl border border-pine-100 bg-cream-100 p-4 transition-colors hover:border-pine-400 sm:px-5"
              >
                <div className="min-w-44">
                  <p className="font-medium text-ink">
                    {guest.firstName} {guest.lastName}
                  </p>
                  <p className="text-xs text-stone">{guest.email}</p>
                </div>
                {guest.phone ? (
                  <span className="text-sm text-ink-soft">{guest.phone}</span>
                ) : null}
                <div className="ml-auto flex items-center gap-4 text-sm text-ink-soft">
                  {guest.notes ? (
                    <NotebookPen className="size-4 text-stone" aria-label="Has notes" />
                  ) : null}
                  <span>
                    {bookingCount} booking{bookingCount === 1 ? "" : "s"}
                  </span>
                  <span className="w-28 text-right text-xs text-stone">
                    {lastStart
                      ? lastStart > today
                        ? `next ${formatDayMonth(lastStart)}`
                        : `last ${formatDayMonth(lastStart)}`
                      : "—"}
                  </span>
                </div>
              </Link>
            </li>
          ))}
        </ul>
      )}
    </div>
  );
}
