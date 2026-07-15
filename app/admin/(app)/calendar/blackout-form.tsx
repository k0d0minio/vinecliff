"use client";

import { useActionState } from "react";
import { useFormStatus } from "react-dom";
import { Check, Loader2, ShieldMinus } from "lucide-react";
import { cn } from "@/lib/utils";
import { buttonVariants } from "@/app/components/ui/button";
import { FormError, Input, Label, Select } from "@/app/components/ui/field";
import type { AdminActionState } from "../bookings/actions";
import { createBlackout } from "./actions";

function SubmitButton() {
  const { pending } = useFormStatus();
  return (
    <button
      type="submit"
      disabled={pending}
      className={cn(buttonVariants({ variant: "primary", size: "sm" }))}
    >
      {pending ? (
        <>
          <Loader2 className="size-4 animate-spin" />
          Blocking…
        </>
      ) : (
        <>
          <ShieldMinus className="size-4" />
          Block dates
        </>
      )}
    </button>
  );
}

export function BlackoutForm({
  spaceOptions,
}: {
  spaceOptions: Array<{ id: string; name: string }>;
}) {
  const [state, formAction] = useActionState<AdminActionState, FormData>(
    createBlackout,
    {}
  );

  return (
    <form action={formAction} className="space-y-4">
      <div className="space-y-1.5">
        <Label htmlFor="blackoutSpace">Space</Label>
        <Select id="blackoutSpace" name="spaceId" defaultValue="">
          <option value="">Whole estate — every space</option>
          {spaceOptions.map((s) => (
            <option key={s.id} value={s.id}>
              {s.name}
            </option>
          ))}
        </Select>
      </div>
      <div className="grid grid-cols-2 gap-3">
        <div className="space-y-1.5">
          <Label htmlFor="firstDay">First blocked day</Label>
          <Input id="firstDay" name="firstDay" type="date" required />
        </div>
        <div className="space-y-1.5">
          <Label htmlFor="lastDay">Last blocked day</Label>
          <Input id="lastDay" name="lastDay" type="date" required />
        </div>
      </div>
      <div className="space-y-1.5">
        <Label htmlFor="reason">Reason <span className="font-normal text-stone">(optional, shows on the calendar)</span></Label>
        <Input id="reason" name="reason" maxLength={200} placeholder="Winterized, family week, roof repairs…" />
      </div>
      <div className="flex items-center gap-3">
        <SubmitButton />
        {state.ok ? (
          <p className="inline-flex items-center gap-1.5 text-sm font-medium text-pine-700">
            <Check className="size-4" />
            Blocked
          </p>
        ) : null}
      </div>
      <FormError message={state.error} />
    </form>
  );
}
