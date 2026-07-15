"use client";

import { useActionState, useState } from "react";
import { useFormStatus } from "react-dom";
import { Loader2 } from "lucide-react";
import { cn } from "@/lib/utils";
import { buttonVariants } from "@/app/components/ui/button";
import { FormError } from "@/app/components/ui/field";
import {
  requestCancellation,
  withdrawRequest,
  type ManageBookingState,
} from "./actions";

function ConfirmButton({ label }: { label: string }) {
  const { pending } = useFormStatus();
  return (
    <button
      type="submit"
      disabled={pending}
      className={cn(buttonVariants({ variant: "primary", size: "sm" }))}
    >
      {pending ? <Loader2 className="size-4 animate-spin" /> : null}
      {label}
    </button>
  );
}

export function CancelControls({
  token,
  mode,
}: {
  token: string;
  /** "withdraw" cancels a pending request; "request" flags an approved booking. */
  mode: "withdraw" | "request";
}) {
  const [confirming, setConfirming] = useState(false);
  const [state, formAction] = useActionState<ManageBookingState, FormData>(
    mode === "withdraw" ? withdrawRequest : requestCancellation,
    {}
  );

  if (!confirming) {
    return (
      <button
        type="button"
        onClick={() => setConfirming(true)}
        className={cn(buttonVariants({ variant: "outline", size: "sm" }))}
      >
        {mode === "withdraw" ? "Withdraw this request" : "Request cancellation"}
      </button>
    );
  }

  return (
    <form action={formAction} className="space-y-3">
      <input type="hidden" name="token" value={token} />
      <p className="text-sm text-ink-soft">
        {mode === "withdraw"
          ? "Withdraw your request? Your dates will be released straight away."
          : "Ask us to cancel this booking? We'll review it against the cancellation policy and confirm by email."}
      </p>
      <div className="flex flex-wrap gap-3">
        <ConfirmButton
          label={mode === "withdraw" ? "Yes — withdraw it" : "Yes — request cancellation"}
        />
        <button
          type="button"
          onClick={() => setConfirming(false)}
          className={cn(buttonVariants({ variant: "ghost", size: "sm" }))}
        >
          Keep my booking
        </button>
      </div>
      <FormError message={state.error} />
    </form>
  );
}
