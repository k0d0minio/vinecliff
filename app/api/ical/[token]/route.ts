// Private iCal availability feed, one per space, addressed by the space's
// secret token: /api/ical/<token>. Subscribe from Google Calendar, or paste
// into Airbnb/VRBO so external listings block dates booked here.
//
// The feed emits everything that makes the space unavailable: its own
// approved bookings (padded by the turnover buffer), estate-reserving
// bookings on other spaces, and applicable blackouts.
import { and, eq, gt, lt, ne } from "drizzle-orm";
import { db } from "@/lib/db";
import { blackouts, bookings } from "@/lib/db/schema";
import { getSpaceByIcalToken } from "@/lib/db/queries";
import { addDays, addMonths, todayAtEstate, type ISODate } from "@/lib/booking/dates";

export const dynamic = "force-dynamic";

function icsDate(date: ISODate): string {
  return date.replaceAll("-", "");
}

function icsEscape(value: string): string {
  return value
    .replace(/\\/g, "\\\\")
    .replace(/;/g, "\\;")
    .replace(/,/g, "\\,")
    .replace(/\r?\n/g, "\\n");
}

type FeedEvent = {
  uid: string;
  startDate: ISODate;
  endDate: ISODate;
  summary: string;
};

export async function GET(
  _request: Request,
  { params }: { params: Promise<{ token: string }> }
) {
  const { token } = await params;
  const space = await getSpaceByIcalToken(token);
  if (!space) return new Response("Not found", { status: 404 });

  const today = todayAtEstate();
  const from = addDays(today, -365);
  const to = addMonths(today, 24);
  const overlapping = and(lt(bookings.startDate, to), gt(bookings.endDate, from));

  const [ownBookings, otherBookings, blackoutRows] = await Promise.all([
    db
      .select({
        id: bookings.id,
        reference: bookings.reference,
        startDate: bookings.startDate,
        endDate: bookings.endDate,
      })
      .from(bookings)
      .where(
        and(eq(bookings.spaceId, space.id), eq(bookings.status, "approved"), overlapping)
      ),
    db
      .select({
        id: bookings.id,
        startDate: bookings.startDate,
        endDate: bookings.endDate,
      })
      .from(bookings)
      .where(
        and(
          ne(bookings.spaceId, space.id),
          eq(bookings.status, "approved"),
          overlapping,
          // Estate-wide spaces are blocked by *any* booking elsewhere;
          // ordinary spaces only by estate-reserving ones.
          space.blocksEstate ? undefined : eq(bookings.blocksEstate, true)
        )
      ),
    db
      .select()
      .from(blackouts)
      .where(and(lt(blackouts.startDate, to), gt(blackouts.endDate, from))),
  ]);

  const events: FeedEvent[] = [
    ...ownBookings.map((b) => ({
      uid: `booking-${b.id}`,
      startDate: addDays(b.startDate, -space.bufferDays),
      endDate: addDays(b.endDate, space.bufferDays),
      summary: `Booked · ${b.reference}`,
    })),
    ...otherBookings.map((b) => ({
      uid: `estate-${b.id}`,
      startDate: b.startDate,
      endDate: b.endDate,
      summary: "Estate reserved",
    })),
    ...blackoutRows
      .filter(
        (bl) => bl.spaceId === null || bl.spaceId === space.id || space.blocksEstate
      )
      .map((bl) => ({
        uid: `blackout-${bl.id}`,
        startDate: bl.startDate,
        endDate: bl.endDate,
        summary: bl.reason ? `Blocked · ${bl.reason}` : "Blocked",
      })),
  ];

  const stamp = `${new Date().toISOString().replace(/[-:]/g, "").slice(0, 15)}Z`;
  const lines = [
    "BEGIN:VCALENDAR",
    "VERSION:2.0",
    "PRODID:-//Vine Cliff//Availability//EN",
    "CALSCALE:GREGORIAN",
    `X-WR-CALNAME:${icsEscape(`Vine Cliff — ${space.name}`)}`,
    ...events.flatMap((event) => [
      "BEGIN:VEVENT",
      `UID:${event.uid}@vinecliff`,
      `DTSTAMP:${stamp}`,
      `DTSTART;VALUE=DATE:${icsDate(event.startDate)}`,
      `DTEND;VALUE=DATE:${icsDate(event.endDate)}`,
      `SUMMARY:${icsEscape(event.summary)}`,
      "END:VEVENT",
    ]),
    "END:VCALENDAR",
  ];

  return new Response(lines.join("\r\n") + "\r\n", {
    headers: {
      "Content-Type": "text/calendar; charset=utf-8",
      "Content-Disposition": `inline; filename="vinecliff-${space.slug}.ics"`,
      "Cache-Control": "private, max-age=300",
    },
  });
}
