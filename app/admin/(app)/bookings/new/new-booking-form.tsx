"use client";

import { useActionState, useMemo, useState } from "react";
import { useFormStatus } from "react-dom";
import { Loader2, Plus } from "lucide-react";
import { cn } from "@/lib/utils";
import { buttonVariants } from "@/app/components/ui/button";
import { FormError, Input, Label, Select, Textarea } from "@/app/components/ui/field";
import { createManualBooking, type AdminActionState } from "../actions";

export type SpaceOption = {
  id: string;
  name: string;
  isEvent: boolean;
  blocksEstate: boolean;
  maxGuests: number;
};

export type BookingPrefill = {
  firstName?: string;
  lastName?: string;
  email?: string;
  phone?: string;
  spaceId?: string;
  enquiryId?: string;
};

function SubmitButton() {
  const { pending } = useFormStatus();
  return (
    <button
      type="submit"
      disabled={pending}
      className={cn(buttonVariants({ variant: "primary", size: "md" }))}
    >
      {pending ? (
        <>
          <Loader2 className="size-4 animate-spin" />
          Saving…
        </>
      ) : (
        <>
          <Plus className="size-4" />
          Create booking
        </>
      )}
    </button>
  );
}

export function NewBookingForm({
  spaces,
  prefill,
}: {
  spaces: SpaceOption[];
  prefill: BookingPrefill;
}) {
  const [state, formAction] = useActionState<AdminActionState, FormData>(
    createManualBooking,
    {}
  );
  const [spaceId, setSpaceId] = useState(prefill.spaceId ?? spaces[0]?.id ?? "");
  const space = useMemo(
    () => spaces.find((s) => s.id === spaceId) ?? spaces[0],
    [spaces, spaceId]
  );

  return (
    <form action={formAction} className="space-y-5">
      {prefill.enquiryId ? (
        <input type="hidden" name="enquiryId" value={prefill.enquiryId} />
      ) : null}

      <div className="grid gap-4 sm:grid-cols-2">
        <div className="space-y-1.5">
          <Label htmlFor="spaceId">Space</Label>
          <Select
            id="spaceId"
            name="spaceId"
            value={spaceId}
            onChange={(e) => setSpaceId(e.target.value)}
          >
            {spaces.map((s) => (
              <option key={s.id} value={s.id}>
                {s.name}
              </option>
            ))}
          </Select>
        </div>
        <div className="space-y-1.5">
          <Label htmlFor="partySize">Guests</Label>
          <Input id="partySize" name="partySize" type="number" min={1} defaultValue={2} required />
        </div>
      </div>

      <div className="grid gap-4 sm:grid-cols-2">
        <div className="space-y-1.5">
          <Label htmlFor="startDate">{space?.isEvent ? "First day" : "Check-in"}</Label>
          <Input id="startDate" name="startDate" type="date" required />
        </div>
        <div className="space-y-1.5">
          <Label htmlFor="endDate">
            {space?.isEvent ? "Departure day (day after last event day)" : "Checkout"}
          </Label>
          <Input id="endDate" name="endDate" type="date" required />
        </div>
      </div>

      <div className="grid gap-4 sm:grid-cols-2">
        <div className="space-y-1.5">
          <Label htmlFor="firstName">Guest first name</Label>
          <Input id="firstName" name="firstName" defaultValue={prefill.firstName} required maxLength={80} />
        </div>
        <div className="space-y-1.5">
          <Label htmlFor="lastName">Guest last name</Label>
          <Input id="lastName" name="lastName" defaultValue={prefill.lastName} required maxLength={80} />
        </div>
      </div>
      <div className="grid gap-4 sm:grid-cols-2">
        <div className="space-y-1.5">
          <Label htmlFor="email">Guest email</Label>
          <Input id="email" name="email" type="email" defaultValue={prefill.email} required maxLength={200} />
        </div>
        <div className="space-y-1.5">
          <Label htmlFor="phone">Guest phone <span className="font-normal text-stone">(optional)</span></Label>
          <Input id="phone" name="phone" type="tel" defaultValue={prefill.phone} maxLength={40} />
        </div>
      </div>

      <div className="grid gap-4 sm:grid-cols-3">
        <div className="space-y-1.5">
          <Label htmlFor="status">Status</Label>
          <Select id="status" name="status" defaultValue="approved">
            <option value="approved">Confirmed</option>
            <option value="pending">Pending review</option>
          </Select>
        </div>
        <div className="space-y-1.5">
          <Label htmlFor="source">Came in via</Label>
          <Select id="source" name="source" defaultValue="phone">
            <option value="phone">Phone</option>
            <option value="email">Email</option>
            <option value="admin">Other / walk-in</option>
          </Select>
        </div>
        <div className="space-y-1.5">
          <Label htmlFor="total">
            Total ($) <span className="font-normal text-stone">(blank = auto quote)</span>
          </Label>
          <Input id="total" name="total" inputMode="decimal" placeholder="Auto" />
        </div>
      </div>

      <div className="grid gap-4 sm:grid-cols-2">
        <div className="space-y-1.5">
          <Label htmlFor="deposit">Deposit ($, optional)</Label>
          <Input id="deposit" name="deposit" inputMode="decimal" />
        </div>
        <div className="space-y-1.5">
          <Label htmlFor="adminNotes">Private notes <span className="font-normal text-stone">(optional)</span></Label>
          <Input id="adminNotes" name="adminNotes" maxLength={4000} />
        </div>
      </div>

      <div className="space-y-2.5">
        <label className="flex items-start gap-2.5 text-sm text-ink-soft">
          <input
            type="checkbox"
            name="blocksEstate"
            key={`blocks-${space?.id}`}
            defaultChecked={space?.blocksEstate ?? false}
            className="mt-0.5 size-4 accent-pine-700"
          />
          Reserve the whole estate for these dates (blocks every space)
        </label>
        <label className="flex items-start gap-2.5 text-sm text-ink-soft">
          <input
            type="checkbox"
            name="notify"
            defaultChecked
            className="mt-0.5 size-4 accent-pine-700"
          />
          Email the guest a confirmation (confirmed bookings only)
        </label>
      </div>

      <FormError message={state.error} />
      <SubmitButton />
    </form>
  );
}
