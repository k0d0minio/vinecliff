"use client";

import { useActionState } from "react";
import { useFormStatus } from "react-dom";
import { Lock, Mail, AlertCircle, Loader2 } from "lucide-react";
import { cn } from "@/lib/utils";
import { buttonVariants } from "../../components/ui/button";
import { login, type LoginState } from "./actions";

function SubmitButton() {
  const { pending } = useFormStatus();
  return (
    <button
      type="submit"
      disabled={pending}
      className={cn(buttonVariants({ variant: "primary", size: "lg" }), "w-full")}
    >
      {pending ? (
        <>
          <Loader2 className="size-4 animate-spin" />
          Checking…
        </>
      ) : (
        "Enter admin"
      )}
    </button>
  );
}

export function LoginForm({ from }: { from?: string }) {
  const [state, formAction] = useActionState<LoginState, FormData>(login, {});

  return (
    <form action={formAction} className="space-y-5">
      {from ? <input type="hidden" name="from" value={from} /> : null}

      <div className="space-y-2">
        <label
          htmlFor="email"
          className="block text-sm font-medium text-ink-soft"
        >
          Email
        </label>
        <div className="relative">
          <Mail className="pointer-events-none absolute left-4 top-1/2 size-4 -translate-y-1/2 text-stone" />
          <input
            id="email"
            name="email"
            type="email"
            autoComplete="username"
            autoFocus
            required
            placeholder="you@example.com"
            className="h-12 w-full rounded-full border border-pine-100 bg-cream-100 pl-11 pr-4 text-sm text-ink outline-none transition-colors placeholder:text-stone/70 focus:border-pine-400 focus:ring-2 focus:ring-pine-600/20"
          />
        </div>
      </div>

      <div className="space-y-2">
        <label
          htmlFor="password"
          className="block text-sm font-medium text-ink-soft"
        >
          Password
        </label>
        <div className="relative">
          <Lock className="pointer-events-none absolute left-4 top-1/2 size-4 -translate-y-1/2 text-stone" />
          <input
            id="password"
            name="password"
            type="password"
            autoComplete="current-password"
            required
            placeholder="Enter your password"
            className="h-12 w-full rounded-full border border-pine-100 bg-cream-100 pl-11 pr-4 text-sm text-ink outline-none transition-colors placeholder:text-stone/70 focus:border-pine-400 focus:ring-2 focus:ring-pine-600/20"
          />
        </div>
      </div>

      {state.error ? (
        <p
          role="alert"
          className="flex items-start gap-2 rounded-2xl bg-amber/10 px-4 py-3 text-sm text-[#9a5a12]"
        >
          <AlertCircle className="mt-0.5 size-4 shrink-0" />
          <span>{state.error}</span>
        </p>
      ) : null}

      <SubmitButton />
    </form>
  );
}
