// Small form primitives matching the estate's design language. Server-safe
// (no hooks) so they render in both server and client components.
import * as React from "react";
import { AlertCircle } from "lucide-react";
import { cn } from "@/lib/utils";

const baseFieldClass =
  "w-full rounded-2xl border border-pine-100 bg-cream-100 px-4 text-sm text-ink outline-none transition-colors placeholder:text-stone/70 focus:border-pine-400 focus:ring-2 focus:ring-pine-600/20 disabled:opacity-60";

export function Label({
  className,
  ...props
}: React.LabelHTMLAttributes<HTMLLabelElement>) {
  return (
    <label
      className={cn("block text-sm font-medium text-ink-soft", className)}
      {...props}
    />
  );
}

export function Input({
  className,
  ...props
}: React.InputHTMLAttributes<HTMLInputElement>) {
  return <input className={cn(baseFieldClass, "h-11", className)} {...props} />;
}

export function Textarea({
  className,
  ...props
}: React.TextareaHTMLAttributes<HTMLTextAreaElement>) {
  return (
    <textarea
      className={cn(baseFieldClass, "min-h-28 py-3 leading-relaxed", className)}
      {...props}
    />
  );
}

export function Select({
  className,
  children,
  ...props
}: React.SelectHTMLAttributes<HTMLSelectElement>) {
  return (
    <select className={cn(baseFieldClass, "h-11 appearance-auto", className)} {...props}>
      {children}
    </select>
  );
}

/** Amber alert panel, shared by every form's error state. */
export function FormError({ message }: { message?: string }) {
  if (!message) return null;
  return (
    <p
      role="alert"
      className="flex items-start gap-2 rounded-2xl bg-amber/10 px-4 py-3 text-sm text-[#9a5a12]"
    >
      <AlertCircle className="mt-0.5 size-4 shrink-0" />
      <span>{message}</span>
    </p>
  );
}
