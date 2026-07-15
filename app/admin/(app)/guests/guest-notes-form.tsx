"use client";

import { useActionState } from "react";
import { useFormStatus } from "react-dom";
import { Check, Loader2 } from "lucide-react";
import { cn } from "@/lib/utils";
import { buttonVariants } from "@/app/components/ui/button";
import { FormError, Textarea } from "@/app/components/ui/field";
import type { AdminActionState } from "../bookings/actions";
import { saveGuestNotes } from "./actions";

function SubmitButton() {
  const { pending } = useFormStatus();
  return (
    <button
      type="submit"
      disabled={pending}
      className={cn(buttonVariants({ variant: "outline", size: "sm" }))}
    >
      {pending ? <Loader2 className="size-4 animate-spin" /> : null}
      Save notes
    </button>
  );
}

export function GuestNotesForm({
  guestId,
  defaultNotes,
}: {
  guestId: string;
  defaultNotes: string;
}) {
  const [state, formAction] = useActionState<AdminActionState, FormData>(
    saveGuestNotes,
    {}
  );
  return (
    <form action={formAction} className="space-y-3">
      <input type="hidden" name="guestId" value={guestId} />
      <Textarea
        name="notes"
        defaultValue={defaultNotes}
        className="min-h-24"
        placeholder="Prefers the lake-facing room · repeat wedding client · allergic to feather pillows…"
      />
      <div className="flex items-center gap-3">
        <SubmitButton />
        {state.ok ? (
          <p className="inline-flex items-center gap-1.5 text-sm font-medium text-pine-700">
            <Check className="size-4" />
            Saved
          </p>
        ) : null}
      </div>
      <FormError message={state.error} />
    </form>
  );
}
