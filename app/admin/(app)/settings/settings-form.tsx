"use client";

import { useActionState } from "react";
import { useFormStatus } from "react-dom";
import { Check, Loader2, Save } from "lucide-react";
import { cn } from "@/lib/utils";
import { buttonVariants } from "@/app/components/ui/button";
import { FormError, Input, Label, Textarea } from "@/app/components/ui/field";
import type { AdminActionState } from "../bookings/actions";
import { saveSettings } from "./actions";

function SubmitButton() {
  const { pending } = useFormStatus();
  return (
    <button
      type="submit"
      disabled={pending}
      className={cn(buttonVariants({ variant: "primary", size: "sm" }))}
    >
      {pending ? <Loader2 className="size-4 animate-spin" /> : <Save className="size-4" />}
      Save settings
    </button>
  );
}

export function SettingsForm({
  notifyEmail,
  cancellationPolicy,
}: {
  notifyEmail: string;
  cancellationPolicy: string;
}) {
  const [state, formAction] = useActionState<AdminActionState, FormData>(saveSettings, {});

  return (
    <form action={formAction} className="space-y-5">
      <div className="space-y-1.5">
        <Label htmlFor="notifyEmail">Notification email</Label>
        <Input
          id="notifyEmail"
          name="notifyEmail"
          type="email"
          defaultValue={notifyEmail}
          required
          maxLength={200}
        />
        <p className="text-xs text-stone">
          New requests, cancellations and enquiries are sent here.
        </p>
      </div>
      <div className="space-y-1.5">
        <Label htmlFor="cancellationPolicy">Cancellation policy</Label>
        <Textarea
          id="cancellationPolicy"
          name="cancellationPolicy"
          defaultValue={cancellationPolicy}
          maxLength={2000}
          className="min-h-32"
        />
        <p className="text-xs text-stone">
          Shown to guests on space pages, booking status pages and in emails.
        </p>
      </div>
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
