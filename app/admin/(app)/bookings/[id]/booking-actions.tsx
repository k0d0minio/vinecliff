"use client";

// Status-dependent action forms for a single booking: approve/decline while
// pending, payment tracking and cancellation once approved.
import { useActionState, useState } from "react";
import { useFormStatus } from "react-dom";
import { AlertTriangle, Check, Loader2 } from "lucide-react";
import { cn } from "@/lib/utils";
import { buttonVariants } from "@/app/components/ui/button";
import { FormError, Input, Label, Select, Textarea } from "@/app/components/ui/field";
import {
  approveBooking,
  cancelBooking,
  declineBooking,
  recordPayment,
  saveAdminNotes,
  type AdminActionState,
} from "../actions";

export type BookingActionData = {
  id: string;
  status: "pending" | "approved" | "declined" | "cancelled";
  quotedTotalCents: number;
  finalTotalCents: number | null;
  depositCents: number | null;
  paymentStatus: "unpaid" | "deposit_paid" | "paid" | "refunded";
  blocksEstate: boolean;
  cancelRequested: boolean;
  conflict: boolean;
  isEvent: boolean;
};

function dollars(cents: number | null): string {
  if (cents === null) return "";
  const value = cents / 100;
  return Number.isInteger(value) ? String(value) : value.toFixed(2);
}

function ActionButton({
  label,
  pendingLabel,
  variant = "primary",
}: {
  label: string;
  pendingLabel: string;
  variant?: "primary" | "amber" | "outline";
}) {
  const { pending } = useFormStatus();
  return (
    <button
      type="submit"
      disabled={pending}
      className={cn(buttonVariants({ variant, size: "sm" }))}
    >
      {pending ? (
        <>
          <Loader2 className="size-4 animate-spin" />
          {pendingLabel}
        </>
      ) : (
        label
      )}
    </button>
  );
}

function Saved({ state }: { state: AdminActionState }) {
  if (!state.ok) return null;
  return (
    <p className="inline-flex items-center gap-1.5 text-sm font-medium text-pine-700">
      <Check className="size-4" />
      Done
    </p>
  );
}

export function PendingActions({ booking }: { booking: BookingActionData }) {
  const [approveState, approveAction] = useActionState<AdminActionState, FormData>(
    approveBooking,
    {}
  );
  const [declineState, declineAction] = useActionState<AdminActionState, FormData>(
    declineBooking,
    {}
  );
  const [declining, setDeclining] = useState(false);

  return (
    <div className="space-y-5">
      {booking.conflict ? (
        <p className="flex items-start gap-2 rounded-2xl bg-amber/10 px-4 py-3 text-sm leading-relaxed text-[#9a5a12]">
          <AlertTriangle className="mt-0.5 size-4 shrink-0" />
          These dates now overlap another confirmed booking, a turnover buffer or a blackout.
          You can still approve if you know it works — the calendar won&apos;t stop you.
        </p>
      ) : null}

      <form action={approveAction} className="space-y-4">
        <input type="hidden" name="bookingId" value={booking.id} />
        <div className="grid grid-cols-2 gap-3">
          <div className="space-y-1.5">
            <Label htmlFor="finalTotal">Final total ($)</Label>
            <Input
              id="finalTotal"
              name="finalTotal"
              inputMode="decimal"
              defaultValue={dollars(booking.finalTotalCents ?? booking.quotedTotalCents)}
            />
          </div>
          <div className="space-y-1.5">
            <Label htmlFor="deposit">Deposit ($, optional)</Label>
            <Input id="deposit" name="deposit" inputMode="decimal" defaultValue={dollars(booking.depositCents)} />
          </div>
        </div>
        <label className="flex items-start gap-2.5 text-sm text-ink-soft">
          <input
            type="checkbox"
            name="blocksEstate"
            defaultChecked={booking.blocksEstate}
            className="mt-0.5 size-4 accent-pine-700"
          />
          Reserve the whole estate for these dates (blocks every space)
        </label>
        <div className="space-y-1.5">
          <Label htmlFor="approveNote">Note to the guest (optional, goes in the email)</Label>
          <Textarea
            id="approveNote"
            name="decisionNote"
            className="min-h-20"
            placeholder="We can't wait to host you — we'll call this week about the deposit."
          />
        </div>
        <div className="flex items-center gap-3">
          <ActionButton label="Approve booking" pendingLabel="Approving…" variant="primary" />
          <Saved state={approveState} />
        </div>
        <FormError message={approveState.error} />
      </form>

      <div className="border-t border-pine-100 pt-4">
        {!declining ? (
          <button
            type="button"
            onClick={() => setDeclining(true)}
            className={cn(buttonVariants({ variant: "outline", size: "sm" }))}
          >
            Decline instead…
          </button>
        ) : (
          <form action={declineAction} className="space-y-3">
            <input type="hidden" name="bookingId" value={booking.id} />
            <div className="space-y-1.5">
              <Label htmlFor="declineNote">Note to the guest (optional, goes in the email)</Label>
              <Textarea
                id="declineNote"
                name="decisionNote"
                className="min-h-20"
                placeholder="We're already hosting a wedding that weekend — early September is wide open though."
              />
            </div>
            <div className="flex items-center gap-3">
              <ActionButton label="Decline request" pendingLabel="Declining…" variant="amber" />
              <button
                type="button"
                onClick={() => setDeclining(false)}
                className={cn(buttonVariants({ variant: "ghost", size: "sm" }))}
              >
                Never mind
              </button>
              <Saved state={declineState} />
            </div>
            <FormError message={declineState.error} />
          </form>
        )}
      </div>
    </div>
  );
}

export function NotesForm({
  bookingId,
  defaultNotes,
}: {
  bookingId: string;
  defaultNotes: string;
}) {
  const [state, formAction] = useActionState<AdminActionState, FormData>(
    saveAdminNotes,
    {}
  );
  return (
    <form action={formAction} className="space-y-3">
      <input type="hidden" name="bookingId" value={bookingId} />
      <Textarea
        name="adminNotes"
        defaultValue={defaultNotes}
        className="min-h-24"
        placeholder="Private notes — the guest never sees these."
      />
      <div className="flex items-center gap-3">
        <ActionButton label="Save notes" pendingLabel="Saving…" variant="outline" />
        <Saved state={state} />
      </div>
      <FormError message={state.error} />
    </form>
  );
}

export function ApprovedActions({ booking }: { booking: BookingActionData }) {
  const [paymentState, paymentAction] = useActionState<AdminActionState, FormData>(
    recordPayment,
    {}
  );
  const [cancelState, cancelAction] = useActionState<AdminActionState, FormData>(
    cancelBooking,
    {}
  );
  const [cancelling, setCancelling] = useState(false);

  return (
    <div className="space-y-5">
      {booking.cancelRequested ? (
        <p className="flex items-start gap-2 rounded-2xl bg-amber/10 px-4 py-3 text-sm leading-relaxed text-[#9a5a12]">
          <AlertTriangle className="mt-0.5 size-4 shrink-0" />
          The guest has requested a cancellation. Cancel below to confirm it, or contact them
          to talk dates.
        </p>
      ) : null}

      <form action={paymentAction} className="space-y-4">
        <input type="hidden" name="bookingId" value={booking.id} />
        <div className="grid grid-cols-2 gap-3">
          <div className="space-y-1.5">
            <Label htmlFor="paymentStatus">Payment status</Label>
            <Select id="paymentStatus" name="paymentStatus" defaultValue={booking.paymentStatus}>
              <option value="unpaid">Unpaid</option>
              <option value="deposit_paid">Deposit paid</option>
              <option value="paid">Paid in full</option>
              <option value="refunded">Refunded</option>
            </Select>
          </div>
          <div className="space-y-1.5">
            <Label htmlFor="paymentDeposit">Deposit ($)</Label>
            <Input
              id="paymentDeposit"
              name="deposit"
              inputMode="decimal"
              defaultValue={dollars(booking.depositCents)}
            />
          </div>
        </div>
        <div className="flex items-center gap-3">
          <ActionButton label="Save payment" pendingLabel="Saving…" />
          <Saved state={paymentState} />
        </div>
        <FormError message={paymentState.error} />
      </form>

      <div className="border-t border-pine-100 pt-4">
        {!cancelling ? (
          <button
            type="button"
            onClick={() => setCancelling(true)}
            className={cn(buttonVariants({ variant: "outline", size: "sm" }))}
          >
            Cancel this booking…
          </button>
        ) : (
          <form action={cancelAction} className="space-y-3">
            <input type="hidden" name="bookingId" value={booking.id} />
            <p className="text-sm text-ink-soft">
              This frees the dates immediately and emails the guest. Refunds stay in your hands.
            </p>
            <div className="space-y-1.5">
              <Label htmlFor="cancelNote">Note to the guest (optional, goes in the email)</Label>
              <Textarea id="cancelNote" name="decisionNote" className="min-h-20" />
            </div>
            <div className="flex items-center gap-3">
              <ActionButton label="Yes — cancel booking" pendingLabel="Cancelling…" variant="amber" />
              <button
                type="button"
                onClick={() => setCancelling(false)}
                className={cn(buttonVariants({ variant: "ghost", size: "sm" }))}
              >
                Keep it
              </button>
              <Saved state={cancelState} />
            </div>
            <FormError message={cancelState.error} />
          </form>
        )}
      </div>
    </div>
  );
}
