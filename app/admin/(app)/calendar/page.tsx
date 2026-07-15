import Link from "next/link";
import { ChevronLeft, ChevronRight, Trash2 } from "lucide-react";
import { cn } from "@/lib/utils";
import { getActiveSpaces, getCalendarData, listUpcomingBlackouts } from "@/lib/db/queries";
import {
  addDays,
  addMonths,
  diffDays,
  formatDayMonth,
  formatMonth,
  parseISO,
  todayAtEstate,
  type ISODate,
} from "@/lib/booking/dates";
import { PageHeader, Card } from "../components/page-shell";
import { BlackoutForm } from "./blackout-form";
import { deleteBlackout } from "./actions";

export const dynamic = "force-dynamic";
export const metadata = { title: "Calendar" };

// One colour per space, assigned by sort order.
const SPACE_COLORS = [
  "bg-pine-600 text-cream",
  "bg-amber text-cream-100",
  "bg-lake text-cream-100",
  "bg-stone text-cream-100",
  "bg-pine-900 text-cream",
];

const WEEKDAYS = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"];

type Props = { searchParams: Promise<{ month?: string }> };

export default async function CalendarPage({ searchParams }: Props) {
  const params = await searchParams;
  const today = todayAtEstate();
  const monthFirst: ISODate = /^\d{4}-(0[1-9]|1[0-2])$/.test(params.month ?? "")
    ? `${params.month}-01`
    : `${today.slice(0, 7)}-01`;
  const monthEnd = addMonths(monthFirst, 1);

  const [spaces, calendar, upcomingBlackouts] = await Promise.all([
    getActiveSpaces(),
    getCalendarData(monthFirst, monthEnd),
    listUpcomingBlackouts(today),
  ]);

  const colorBySpace = new Map(
    spaces.map((s, i) => [s.id, SPACE_COLORS[i % SPACE_COLORS.length]])
  );
  const shortName = (name: string) => name.replace(/^The /, "");

  const lead = parseISO(monthFirst).getUTCDay();
  const dayCount = diffDays(monthFirst, monthEnd);
  const prevMonth = addMonths(monthFirst, -1).slice(0, 7);
  const nextMonth = addMonths(monthFirst, 1).slice(0, 7);

  return (
    <div className="space-y-6">
      <PageHeader
        title="Calendar"
        description="Confirmed bookings and blackout dates across every space. Pending requests don't block dates and aren't shown here."
      />

      <Card className="overflow-x-auto p-4 sm:p-5">
        <div className="min-w-[680px]">
          <div className="flex items-center justify-between pb-4">
            <div className="flex items-center gap-1">
              <Link
                href={`/admin/calendar?month=${prevMonth}`}
                aria-label="Previous month"
                className="flex size-8 items-center justify-center rounded-full text-pine-700 hover:bg-pine-50"
              >
                <ChevronLeft className="size-4" />
              </Link>
              <Link
                href={`/admin/calendar?month=${nextMonth}`}
                aria-label="Next month"
                className="flex size-8 items-center justify-center rounded-full text-pine-700 hover:bg-pine-50"
              >
                <ChevronRight className="size-4" />
              </Link>
              <Link
                href="/admin/calendar"
                className="ml-2 rounded-full px-3 py-1 text-xs font-medium text-pine-700 hover:bg-pine-50"
              >
                Today
              </Link>
            </div>
            <h2 className="font-display text-xl text-ink">{formatMonth(monthFirst)}</h2>
            <div className="flex flex-wrap items-center justify-end gap-x-4 gap-y-1">
              {spaces.map((s) => (
                <span key={s.id} className="flex items-center gap-1.5 text-xs text-ink-soft">
                  <span
                    className={cn("size-2.5 rounded-full", colorBySpace.get(s.id)?.split(" ")[0])}
                  />
                  {shortName(s.name)}
                </span>
              ))}
              <span className="flex items-center gap-1.5 text-xs text-ink-soft">
                <span className="size-2.5 rounded-full border border-stone/50 bg-parchment" />
                Blackout
              </span>
            </div>
          </div>

          <div className="grid grid-cols-7 gap-px overflow-hidden rounded-xl bg-pine-100">
            {WEEKDAYS.map((d) => (
              <div
                key={d}
                className="bg-cream px-2 py-1.5 text-center text-[0.65rem] font-medium uppercase tracking-wider text-stone"
              >
                {d}
              </div>
            ))}
            {Array.from({ length: lead }).map((_, i) => (
              <div key={`lead-${i}`} className="min-h-24 bg-cream/60" />
            ))}
            {Array.from({ length: dayCount }).map((_, i) => {
              const day = addDays(monthFirst, i);
              const isToday = day === today;
              const dayBookings = calendar.bookings.filter(
                ({ booking }) => booking.startDate <= day && day < booking.endDate
              );
              const dayBlackouts = calendar.blackouts.filter(
                ({ blackout }) => blackout.startDate <= day && day < blackout.endDate
              );
              return (
                <div key={day} className="min-h-24 space-y-1 bg-cream-100 p-1.5">
                  <p
                    className={cn(
                      "text-right text-xs",
                      isToday
                        ? "ml-auto flex size-5 items-center justify-center rounded-full bg-pine-700 font-semibold text-cream"
                        : "text-stone"
                    )}
                  >
                    {i + 1}
                  </p>
                  {dayBookings.map(({ booking, space, guest }) => {
                    const isStart = booking.startDate === day || day === monthFirst;
                    return (
                      <Link
                        key={booking.id}
                        href={`/admin/bookings/${booking.id}`}
                        title={`${booking.reference} · ${guest.firstName} ${guest.lastName} · ${space.name}`}
                        className={cn(
                          "block truncate rounded px-1.5 text-[0.68rem] leading-5",
                          colorBySpace.get(space.id),
                          !isStart && "h-1.5 rounded-full p-0 opacity-70"
                        )}
                      >
                        {isStart ? `${shortName(space.name)} · ${guest.lastName}` : null}
                      </Link>
                    );
                  })}
                  {dayBlackouts.map(({ blackout, spaceName }) => {
                    const isStart = blackout.startDate === day || day === monthFirst;
                    return (
                      <div
                        key={blackout.id}
                        title={`${spaceName ?? "Whole estate"}${blackout.reason ? ` — ${blackout.reason}` : ""}`}
                        className={cn(
                          "truncate rounded border border-stone/30 bg-parchment px-1.5 text-[0.68rem] leading-5 text-stone",
                          !isStart && "h-1.5 rounded-full border-dashed p-0"
                        )}
                      >
                        {isStart
                          ? `✕ ${spaceName ? shortName(spaceName) : "All"}${blackout.reason ? ` · ${blackout.reason}` : ""}`
                          : null}
                      </div>
                    );
                  })}
                </div>
              );
            })}
          </div>
        </div>
      </Card>

      <div className="grid gap-6 lg:grid-cols-2">
        <Card>
          <h2 className="font-display text-lg text-ink">Block dates</h2>
          <p className="mb-4 mt-1 text-sm text-ink-soft">
            Close a space (or the whole estate) for maintenance, family time or the winter —
            guests can&apos;t request blocked dates.
          </p>
          <BlackoutForm spaceOptions={spaces.map((s) => ({ id: s.id, name: s.name }))} />
        </Card>

        <Card>
          <h2 className="font-display text-lg text-ink">Upcoming blackouts</h2>
          {upcomingBlackouts.length === 0 ? (
            <p className="mt-3 text-sm text-stone">Nothing blocked ahead.</p>
          ) : (
            <ul className="mt-3 divide-y divide-pine-100">
              {upcomingBlackouts.map(({ blackout, spaceName }) => (
                <li key={blackout.id} className="flex items-center justify-between gap-3 py-2.5">
                  <div>
                    <p className="text-sm font-medium text-ink">
                      {spaceName ?? "Whole estate"}
                      {blackout.reason ? (
                        <span className="font-normal text-stone"> · {blackout.reason}</span>
                      ) : null}
                    </p>
                    <p className="text-xs text-stone">
                      {formatDayMonth(blackout.startDate)} →{" "}
                      {formatDayMonth(addDays(blackout.endDate, -1))} (reopens{" "}
                      {formatDayMonth(blackout.endDate)})
                    </p>
                  </div>
                  <form action={deleteBlackout}>
                    <input type="hidden" name="blackoutId" value={blackout.id} />
                    <button
                      type="submit"
                      aria-label="Delete blackout"
                      className="flex size-8 items-center justify-center rounded-full text-stone transition-colors hover:bg-amber/10 hover:text-[#9a5a12]"
                    >
                      <Trash2 className="size-4" />
                    </button>
                  </form>
                </li>
              ))}
            </ul>
          )}
        </Card>
      </div>
    </div>
  );
}
