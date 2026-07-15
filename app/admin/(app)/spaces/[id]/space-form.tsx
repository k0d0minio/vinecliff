"use client";

import { useActionState } from "react";
import { useFormStatus } from "react-dom";
import { Check, Loader2, Save } from "lucide-react";
import { cn } from "@/lib/utils";
import { buttonVariants } from "@/app/components/ui/button";
import { FormError, Input, Label, Select, Textarea } from "@/app/components/ui/field";
import { SPACE_IMAGES } from "@/lib/space-images";
import type { AdminActionState } from "../../bookings/actions";
import { updateSpace } from "../actions";

export type SpaceFormData = {
  id: string;
  name: string;
  kind: string;
  age: string;
  blurb: string;
  description: string;
  image: string;
  features: string[];
  isEvent: boolean;
  blocksEstate: boolean;
  active: boolean;
  nightlyRateCents: number;
  weeklyRateCents: number | null;
  cleaningFeeCents: number;
  minNights: number;
  maxGuests: number;
  bufferDays: number;
  minLeadDays: number;
  maxHorizonMonths: number;
  sortOrder: number;
};

function dollars(cents: number | null): string {
  if (cents === null) return "";
  const value = cents / 100;
  return Number.isInteger(value) ? String(value) : value.toFixed(2);
}

function SubmitButton() {
  const { pending } = useFormStatus();
  return (
    <button
      type="submit"
      disabled={pending}
      className={cn(buttonVariants({ variant: "primary", size: "md" }))}
    >
      {pending ? <Loader2 className="size-4 animate-spin" /> : <Save className="size-4" />}
      Save space
    </button>
  );
}

export function SpaceForm({ space }: { space: SpaceFormData }) {
  const [state, formAction] = useActionState<AdminActionState, FormData>(updateSpace, {});

  return (
    <form action={formAction} className="space-y-8">
      <input type="hidden" name="spaceId" value={space.id} />

      <section className="space-y-4">
        <h2 className="font-display text-lg text-ink">What guests see</h2>
        <div className="grid gap-4 sm:grid-cols-2">
          <div className="space-y-1.5">
            <Label htmlFor="name">Name</Label>
            <Input id="name" name="name" defaultValue={space.name} required maxLength={120} />
          </div>
          <div className="space-y-1.5">
            <Label htmlFor="kind">Tagline</Label>
            <Input id="kind" name="kind" defaultValue={space.kind} required maxLength={120} />
          </div>
        </div>
        <div className="grid gap-4 sm:grid-cols-2">
          <div className="space-y-1.5">
            <Label htmlFor="age">Heritage note</Label>
            <Input id="age" name="age" defaultValue={space.age} required maxLength={120} />
          </div>
          <div className="space-y-1.5">
            <Label htmlFor="image">Hero photo</Label>
            <Select id="image" name="image" defaultValue={space.image}>
              {SPACE_IMAGES.map((img) => (
                <option key={img} value={img}>
                  {img.replace("/img/", "").replace(".jpg", "").replaceAll("-", " ")}
                </option>
              ))}
            </Select>
          </div>
        </div>
        <div className="space-y-1.5">
          <Label htmlFor="blurb">Card summary</Label>
          <Textarea id="blurb" name="blurb" defaultValue={space.blurb} required maxLength={600} className="min-h-20" />
        </div>
        <div className="space-y-1.5">
          <Label htmlFor="description">
            Full description <span className="font-normal text-stone">(blank line = new paragraph)</span>
          </Label>
          <Textarea
            id="description"
            name="description"
            defaultValue={space.description}
            required
            maxLength={6000}
            className="min-h-44"
          />
        </div>
        <div className="space-y-1.5">
          <Label htmlFor="features">
            Feature list <span className="font-normal text-stone">(one per line, up to 12)</span>
          </Label>
          <Textarea
            id="features"
            name="features"
            defaultValue={space.features.join("\n")}
            className="min-h-28"
          />
        </div>
      </section>

      <section className="space-y-4">
        <h2 className="font-display text-lg text-ink">Rates</h2>
        <div className="grid gap-4 sm:grid-cols-3">
          <div className="space-y-1.5">
            <Label htmlFor="nightlyRate">{space.isEvent ? "Per event day ($)" : "Per night ($)"}</Label>
            <Input id="nightlyRate" name="nightlyRate" inputMode="decimal" defaultValue={dollars(space.nightlyRateCents)} required />
          </div>
          <div className="space-y-1.5">
            <Label htmlFor="weeklyRate">
              Per week ($) <span className="font-normal text-stone">(blank = none)</span>
            </Label>
            <Input id="weeklyRate" name="weeklyRate" inputMode="decimal" defaultValue={dollars(space.weeklyRateCents)} />
          </div>
          <div className="space-y-1.5">
            <Label htmlFor="cleaningFee">Cleaning fee ($)</Label>
            <Input id="cleaningFee" name="cleaningFee" inputMode="decimal" defaultValue={dollars(space.cleaningFeeCents)} />
          </div>
        </div>
      </section>

      <section className="space-y-4">
        <h2 className="font-display text-lg text-ink">Booking rules</h2>
        <div className="grid grid-cols-2 gap-4 sm:grid-cols-5">
          <div className="space-y-1.5">
            <Label htmlFor="minNights">{space.isEvent ? "Min days" : "Min nights"}</Label>
            <Input id="minNights" name="minNights" type="number" min={1} max={60} defaultValue={space.minNights} />
          </div>
          <div className="space-y-1.5">
            <Label htmlFor="maxGuests">Max guests</Label>
            <Input id="maxGuests" name="maxGuests" type="number" min={1} max={1000} defaultValue={space.maxGuests} />
          </div>
          <div className="space-y-1.5">
            <Label htmlFor="bufferDays">Buffer days</Label>
            <Input id="bufferDays" name="bufferDays" type="number" min={0} max={14} defaultValue={space.bufferDays} />
          </div>
          <div className="space-y-1.5">
            <Label htmlFor="minLeadDays">Lead days</Label>
            <Input id="minLeadDays" name="minLeadDays" type="number" min={0} max={365} defaultValue={space.minLeadDays} />
          </div>
          <div className="space-y-1.5">
            <Label htmlFor="maxHorizonMonths">Horizon (months)</Label>
            <Input id="maxHorizonMonths" name="maxHorizonMonths" type="number" min={1} max={36} defaultValue={space.maxHorizonMonths} />
          </div>
        </div>
        <p className="text-xs leading-relaxed text-stone">
          Buffer days stay blocked around each booking for turnover. Lead days is the shortest
          notice you'll accept; horizon is how far ahead guests can request.
        </p>
        <div className="space-y-2.5">
          <label className="flex items-start gap-2.5 text-sm text-ink-soft">
            <input type="checkbox" name="isEvent" defaultChecked={space.isEvent} className="mt-0.5 size-4 accent-pine-700" />
            Event space — priced per day, forms speak of “days” not “nights”
          </label>
          <label className="flex items-start gap-2.5 text-sm text-ink-soft">
            <input type="checkbox" name="blocksEstate" defaultChecked={space.blocksEstate} className="mt-0.5 size-4 accent-pine-700" />
            Takes the whole estate — bookings here block every space, and it's only available
            when everything is free
          </label>
          <label className="flex items-start gap-2.5 text-sm text-ink-soft">
            <input type="checkbox" name="active" defaultChecked={space.active} className="mt-0.5 size-4 accent-pine-700" />
            Active — shown on the website and open for requests
          </label>
        </div>
        <div className="w-32 space-y-1.5">
          <Label htmlFor="sortOrder">Sort order</Label>
          <Input id="sortOrder" name="sortOrder" type="number" min={0} max={99} defaultValue={space.sortOrder} />
        </div>
      </section>

      <div className="flex items-center gap-3 border-t border-pine-100 pt-5">
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
