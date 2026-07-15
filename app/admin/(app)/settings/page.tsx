import { LogOut, ShieldCheck } from "lucide-react";
import { site } from "@/lib/site";
import { cn } from "@/lib/utils";
import { getNotifyEmail, getCancellationPolicy } from "@/lib/settings";
import { buttonVariants } from "../../../components/ui/button";
import { PageHeader, Card } from "../components/page-shell";
import { logout } from "../actions";
import { SettingsForm } from "./settings-form";

export const dynamic = "force-dynamic";
export const metadata = { title: "Settings" };

const details = [
  { label: "Business name", value: site.fullName },
  { label: "Phone", value: site.phone },
  { label: "Email", value: site.email },
  { label: "Address", value: site.address.full },
];

export default async function SettingsPage() {
  const [notifyEmail, cancellationPolicy] = await Promise.all([
    getNotifyEmail(),
    getCancellationPolicy(),
  ]);

  return (
    <div className="space-y-8">
      <PageHeader
        title="Settings"
        description="Estate-wide knobs for the booking system, plus business details and admin access."
      />

      <Card>
        <h2 className="font-display text-lg text-ink">Booking system</h2>
        <div className="mt-4">
          <SettingsForm
            notifyEmail={notifyEmail}
            cancellationPolicy={cancellationPolicy ?? ""}
          />
        </div>
      </Card>

      <Card>
        <h2 className="font-display text-lg text-ink">Business details</h2>
        <dl className="mt-4 divide-y divide-pine-100">
          {details.map((row) => (
            <div
              key={row.label}
              className="flex flex-col gap-1 py-3 sm:flex-row sm:items-center sm:justify-between"
            >
              <dt className="text-sm text-stone">{row.label}</dt>
              <dd className="text-sm font-medium text-ink sm:text-right">
                {row.value}
              </dd>
            </div>
          ))}
        </dl>
      </Card>

      <Card>
        <div className="flex items-start gap-3">
          <div className="flex size-10 shrink-0 items-center justify-center rounded-xl bg-pine-50 text-pine-600">
            <ShieldCheck className="size-5" />
          </div>
          <div>
            <h2 className="font-display text-lg text-ink">Access</h2>
            <p className="mt-1 text-sm text-ink-soft">
              Admin access is tied to individual accounts, each signing in with
              their own email and password. Accounts are stored in the estate
              database; account management will be available here soon.
            </p>
          </div>
        </div>
      </Card>

      <form action={logout}>
        <button
          type="submit"
          className={cn(buttonVariants({ variant: "outline", size: "md" }))}
        >
          <LogOut className="size-4" />
          Sign out
        </button>
      </form>
    </div>
  );
}
