"use client";

import { useActionState } from "react";
import { useFormStatus } from "react-dom";
import { Loader2, MailCheck, Send } from "lucide-react";
import { cn } from "@/lib/utils";
import { buttonVariants } from "@/app/components/ui/button";
import { FormError, Input, Label, Select, Textarea } from "@/app/components/ui/field";
import { submitEnquiry, type EnquiryFormState } from "./actions";

function SubmitButton() {
  const { pending } = useFormStatus();
  return (
    <button
      type="submit"
      disabled={pending}
      className={cn(buttonVariants({ variant: "amber", size: "lg" }), "w-full")}
    >
      {pending ? (
        <>
          <Loader2 className="size-4 animate-spin" />
          Sending…
        </>
      ) : (
        <>
          <Send className="size-4" />
          Send enquiry
        </>
      )}
    </button>
  );
}

export function EnquiryForm({
  spaceOptions,
  defaultSpace,
}: {
  spaceOptions: Array<{ slug: string; name: string }>;
  defaultSpace?: string;
}) {
  const [state, formAction] = useActionState<EnquiryFormState, FormData>(
    submitEnquiry,
    {}
  );

  if (state.sent) {
    return (
      <div className="rounded-3xl border border-pine-100 bg-cream-100 p-8 text-center shadow-soft">
        <span className="inline-flex size-14 items-center justify-center rounded-full bg-pine-50 text-pine-600">
          <MailCheck className="size-7" />
        </span>
        <h2 className="mt-5 font-display text-2xl text-pine-900">Thank you — it&apos;s on its way</h2>
        <p className="mx-auto mt-3 max-w-md text-sm leading-relaxed text-ink-soft">
          We read every enquiry personally and will come back to you within a day or two. If
          it&apos;s urgent, call us and we&apos;ll pick up from the porch.
        </p>
      </div>
    );
  }

  return (
    <form
      action={formAction}
      className="rounded-3xl border border-pine-100 bg-cream-100 p-6 shadow-soft sm:p-8"
    >
      {/* Honeypot — humans never see or fill this. */}
      <div aria-hidden="true" className="absolute -left-[9999px] top-auto h-px w-px overflow-hidden">
        <label>
          Website
          <input type="text" name="website" tabIndex={-1} autoComplete="off" />
        </label>
      </div>

      <div className="space-y-4">
        <div className="grid gap-4 sm:grid-cols-2">
          <div className="space-y-1.5">
            <Label htmlFor="name">Your name</Label>
            <Input id="name" name="name" autoComplete="name" required maxLength={160} />
          </div>
          <div className="space-y-1.5">
            <Label htmlFor="email">Email</Label>
            <Input id="email" name="email" type="email" autoComplete="email" required maxLength={200} />
          </div>
        </div>
        <div className="grid gap-4 sm:grid-cols-2">
          <div className="space-y-1.5">
            <Label htmlFor="phone">Phone <span className="font-normal text-stone">(optional)</span></Label>
            <Input id="phone" name="phone" type="tel" autoComplete="tel" maxLength={40} />
          </div>
          <div className="space-y-1.5">
            <Label htmlFor="space">I&apos;m interested in</Label>
            <Select id="space" name="space" defaultValue={defaultSpace ?? ""}>
              <option value="">The estate in general</option>
              {spaceOptions.map((s) => (
                <option key={s.slug} value={s.slug}>
                  {s.name}
                </option>
              ))}
            </Select>
          </div>
        </div>
        <div className="space-y-1.5">
          <Label htmlFor="message">What are you planning?</Label>
          <Textarea
            id="message"
            name="message"
            required
            maxLength={4000}
            className="min-h-36"
            placeholder="A week by the lake in August, a September wedding for 90, a spring retreat…"
          />
        </div>

        <FormError message={state.error} />
        <SubmitButton />
        <p className="text-center text-xs text-stone">
          Ready to pick dates? Each space&apos;s page has live availability and a booking form.
        </p>
      </div>
    </form>
  );
}
