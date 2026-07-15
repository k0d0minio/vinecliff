"use client";

import { useActionState, useMemo, useState } from "react";
import { useFormStatus } from "react-dom";
import { ChevronLeft, ChevronRight, Loader2, Send, Undo2 } from "lucide-react";
import {
  addDays,
  addMonths,
  diffDays,
  formatDate,
  formatMonth,
  parseISO,
  type ISODate,
} from "@/lib/booking/dates";
import {
  bookingWindow,
  isDateBlocked,
  type DateRange,
} from "@/lib/booking/availability";
import { computeQuote, formatMoney, unitLabel } from "@/lib/booking/pricing";
import { EVENT_TYPES } from "@/lib/booking/event-types";
import { buttonVariants } from "@/app/components/ui/button";
import { FormError, Input, Label, Select, Textarea } from "@/app/components/ui/field";
import { cn } from "@/lib/utils";
import { requestBooking, type BookingFormState } from "./actions";

export type PanelSpace = {
  id: string;
  slug: string;
  name: string;
  isEvent: boolean;
  blocksEstate: boolean;
  minNights: number;
  maxGuests: number;
  bufferDays: number;
  minLeadDays: number;
  maxHorizonMonths: number;
  nightlyRateCents: number;
  weeklyRateCents: number | null;
  cleaningFeeCents: number;
};

function firstOfMonth(date: ISODate): ISODate {
  return `${date.slice(0, 7)}-01`;
}

function SubmitButton({ disabled }: { disabled: boolean }) {
  const { pending } = useFormStatus();
  return (
    <button
      type="submit"
      disabled={disabled || pending}
      className={cn(buttonVariants({ variant: "amber", size: "lg" }), "w-full")}
    >
      {pending ? (
        <>
          <Loader2 className="size-4 animate-spin" />
          Sending your request…
        </>
      ) : (
        <>
          <Send className="size-4" />
          Request to book
        </>
      )}
    </button>
  );
}

export function BookingPanel({
  space,
  blocked,
  today,
}: {
  space: PanelSpace;
  blocked: DateRange[];
  today: ISODate;
}) {
  const window = useMemo(() => bookingWindow(space, today), [space, today]);
  const [month, setMonth] = useState<ISODate>(firstOfMonth(window.firstStart));
  const [start, setStart] = useState<ISODate | null>(null);
  /** Exclusive end: checkout day for stays, day after the last event day. */
  const [endEx, setEndEx] = useState<ISODate | null>(null);
  const [rangeError, setRangeError] = useState<string | null>(null);
  const [state, formAction] = useActionState<BookingFormState, FormData>(
    requestBooking,
    {}
  );

  const canPrev = month > firstOfMonth(window.firstStart);
  const canNext = addMonths(month, 1) <= firstOfMonth(addDays(window.lastEnd, -1));

  const isSelectable = (day: ISODate) =>
    day >= window.firstStart && day < window.lastEnd && !isDateBlocked(day, blocked);

  const pickDay = (day: ISODate) => {
    setRangeError(null);
    if (!start || (start && endEx)) {
      setStart(day);
      setEndEx(null);
      return;
    }
    if (day === start) {
      // Second tap on the same day: a single-day event; stays need a night.
      if (space.isEvent) setEndEx(addDays(day, 1));
      return;
    }
    if (day < start) {
      setStart(day);
      return;
    }
    const candidateEnd = space.isEvent ? addDays(day, 1) : day;
    for (let d = start; d < candidateEnd; d = addDays(d, 1)) {
      if (isDateBlocked(d, blocked)) {
        setRangeError("That range crosses unavailable dates — please pick a shorter span.");
        return;
      }
    }
    setEndEx(candidateEnd);
  };

  const clearDates = () => {
    setStart(null);
    setEndEx(null);
    setRangeError(null);
  };

  // The last day to *display* as selected — checkout day for stays (guests
  // read it as part of the trip), the final event day for events.
  const displayEnd = endEx ? (space.isEvent ? addDays(endEx, -1) : endEx) : null;

  const quote = start && endEx ? computeQuote(space, start, endEx) : null;
  const nights = start && endEx ? diffDays(start, endEx) : 0;

  // --- Month grid -----------------------------------------------------------
  const monthDays = useMemo(() => {
    const count = diffDays(month, addMonths(month, 1));
    const lead = parseISO(month).getUTCDay();
    return { count, lead };
  }, [month]);

  const dayLabels = ["Su", "Mo", "Tu", "We", "Th", "Fr", "Sa"];

  return (
    <div className="rounded-3xl border border-pine-100 bg-cream-100 p-6 shadow-soft sm:p-7">
      <p className="eyebrow text-amber">Request to book</p>
      <h2 className="mt-2 font-display text-2xl text-pine-900">
        {space.isEvent ? "Pick your days" : "Pick your dates"}
      </h2>
      <p className="mt-2 text-sm leading-relaxed text-stone">
        {space.isEvent
          ? "Select your first and last day, including any setup and teardown time."
          : "Select your check-in and checkout days."}{" "}
        We review every request personally — nothing is charged online.
      </p>

      {/* Calendar */}
      <div className="mt-5 rounded-2xl border border-pine-100 bg-cream p-4">
        <div className="flex items-center justify-between">
          <button
            type="button"
            aria-label="Previous month"
            onClick={() => canPrev && setMonth(addMonths(month, -1))}
            disabled={!canPrev}
            className="flex size-8 items-center justify-center rounded-full text-pine-700 transition-colors hover:bg-pine-50 disabled:opacity-30"
          >
            <ChevronLeft className="size-4" />
          </button>
          <p className="text-sm font-medium text-ink">{formatMonth(month)}</p>
          <button
            type="button"
            aria-label="Next month"
            onClick={() => canNext && setMonth(addMonths(month, 1))}
            disabled={!canNext}
            className="flex size-8 items-center justify-center rounded-full text-pine-700 transition-colors hover:bg-pine-50 disabled:opacity-30"
          >
            <ChevronRight className="size-4" />
          </button>
        </div>
        <div className="mt-3 grid grid-cols-7 text-center">
          {dayLabels.map((d) => (
            <span key={d} className="pb-1 text-[0.65rem] font-medium uppercase tracking-wider text-stone">
              {d}
            </span>
          ))}
          {Array.from({ length: monthDays.lead }).map((_, i) => (
            <span key={`lead-${i}`} />
          ))}
          {Array.from({ length: monthDays.count }).map((_, i) => {
            const day = addDays(month, i);
            const selectable = isSelectable(day);
            const isEndpoint = day === start || (displayEnd !== null && day === displayEnd);
            const inRange =
              start !== null &&
              displayEnd !== null &&
              day > start &&
              day < displayEnd;
            const blockedDay = isDateBlocked(day, blocked);
            return (
              <button
                key={day}
                type="button"
                disabled={!selectable}
                onClick={() => pickDay(day)}
                aria-label={formatDate(day)}
                aria-pressed={isEndpoint || inRange}
                className={cn(
                  "mx-auto flex size-9 items-center justify-center rounded-full text-sm transition-colors",
                  isEndpoint
                    ? "bg-pine-700 font-medium text-cream"
                    : inRange
                      ? "bg-pine-100 text-pine-900"
                      : selectable
                        ? "cursor-pointer text-ink hover:bg-pine-100"
                        : blockedDay
                          ? "text-stone/40 line-through decoration-stone/40"
                          : "text-stone/35"
                )}
              >
                {i + 1}
              </button>
            );
          })}
        </div>
        <div className="mt-3 flex items-center justify-between border-t border-pine-100 pt-3">
          <p className="text-xs text-stone">
            Minimum {space.minNights} {unitLabel(space, space.minNights)} · up to{" "}
            {space.maxGuests} guests
          </p>
          {start ? (
            <button
              type="button"
              onClick={clearDates}
              className="inline-flex items-center gap-1 text-xs font-medium text-pine-700 hover:text-amber"
            >
              <Undo2 className="size-3" />
              Clear
            </button>
          ) : null}
        </div>
      </div>

      {rangeError ? <p className="mt-3 text-sm text-[#9a5a12]">{rangeError}</p> : null}

      {/* Selection + quote */}
      {start && endEx && quote ? (
        <div className="mt-5 rounded-2xl bg-pine-50 p-4">
          <p className="text-sm font-medium text-pine-900">
            {formatDate(start)} → {formatDate(space.isEvent ? addDays(endEx, -1) : endEx)}
            <span className="ml-2 font-normal text-pine-600">
              {nights} {unitLabel(space, nights)}
            </span>
          </p>
          <dl className="mt-3 space-y-1.5 border-t border-pine-100 pt-3">
            {quote.lines.map((line) => (
              <div key={line.label} className="flex justify-between text-sm text-ink-soft">
                <dt>{line.label}</dt>
                <dd>{formatMoney(line.amountCents)}</dd>
              </div>
            ))}
            <div className="flex justify-between border-t border-pine-100 pt-2 text-sm font-semibold text-ink">
              <dt>Estimated total</dt>
              <dd>{formatMoney(quote.totalCents)}</dd>
            </div>
          </dl>
          <p className="mt-2 text-xs text-stone">
            An estimate — we confirm the final price with your booking.
          </p>
        </div>
      ) : start ? (
        <p className="mt-4 text-sm text-stone">
          {space.isEvent
            ? "Now pick your last day (or tap the same day again for a single-day event)."
            : "Now pick your checkout day."}
        </p>
      ) : null}

      {/* Details form */}
      <form action={formAction} className="mt-6 space-y-4">
        <input type="hidden" name="space" value={space.slug} />
        <input type="hidden" name="startDate" value={start ?? ""} />
        <input type="hidden" name="endDate" value={endEx ?? ""} />
        {/* Honeypot — humans never see or fill this. */}
        <div aria-hidden="true" className="absolute -left-[9999px] top-auto h-px w-px overflow-hidden">
          <label>
            Website
            <input type="text" name="website" tabIndex={-1} autoComplete="off" />
          </label>
        </div>

        <div className="grid grid-cols-2 gap-3">
          <div className="space-y-1.5">
            <Label htmlFor="firstName">First name</Label>
            <Input id="firstName" name="firstName" autoComplete="given-name" required maxLength={80} />
          </div>
          <div className="space-y-1.5">
            <Label htmlFor="lastName">Last name</Label>
            <Input id="lastName" name="lastName" autoComplete="family-name" required maxLength={80} />
          </div>
        </div>
        <div className="space-y-1.5">
          <Label htmlFor="email">Email</Label>
          <Input id="email" name="email" type="email" autoComplete="email" required maxLength={200} />
        </div>
        <div className="grid grid-cols-2 gap-3">
          <div className="space-y-1.5">
            <Label htmlFor="phone">Phone <span className="font-normal text-stone">(optional)</span></Label>
            <Input id="phone" name="phone" type="tel" autoComplete="tel" maxLength={40} />
          </div>
          <div className="space-y-1.5">
            <Label htmlFor="partySize">Guests</Label>
            <Input
              id="partySize"
              name="partySize"
              type="number"
              min={1}
              max={space.maxGuests}
              defaultValue={2}
              required
            />
          </div>
        </div>
        {space.isEvent ? (
          <div className="space-y-1.5">
            <Label htmlFor="eventType">Occasion</Label>
            <Select id="eventType" name="eventType" required defaultValue="">
              <option value="" disabled>
                What are we celebrating?
              </option>
              {EVENT_TYPES.map((t) => (
                <option key={t} value={t}>
                  {t}
                </option>
              ))}
            </Select>
          </div>
        ) : null}
        <div className="space-y-1.5">
          <Label htmlFor="message">
            Your plans <span className="font-normal text-stone">(optional)</span>
          </Label>
          <Textarea
            id="message"
            name="message"
            maxLength={2000}
            placeholder={
              space.isEvent
                ? "Tell us about the occasion, rough guest count, timings…"
                : "Anything we should know about your stay?"
            }
          />
        </div>

        <FormError message={state.error} />

        <SubmitButton disabled={!start || !endEx} />
        <p className="text-center text-xs leading-relaxed text-stone">
          Submitting sends a request, not a charge. We&apos;ll confirm availability and payment
          details personally.
        </p>
      </form>
    </div>
  );
}
