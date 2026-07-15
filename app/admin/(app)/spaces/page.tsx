import { Pencil } from "lucide-react";
import { spaces } from "@/lib/site";
import { PageHeader, Card } from "../components/page-shell";

export const metadata = { title: "Spaces" };

export default function SpacesPage() {
  return (
    <div className="space-y-8">
      <PageHeader
        title="Spaces"
        description="The rentable spaces across the estate, as shown on the public website. Editing will be enabled here soon."
      />

      <div className="grid gap-4 sm:grid-cols-2">
        {spaces.map((space) => (
          <Card key={space.id} className="flex flex-col">
            <div className="flex items-start justify-between gap-3">
              <div>
                <h2 className="font-display text-lg text-ink">{space.name}</h2>
                <p className="mt-0.5 text-xs uppercase tracking-wide text-stone">
                  {space.kind} · {space.age}
                </p>
              </div>
              <button
                aria-label={`Edit ${space.name}`}
                className="flex size-9 shrink-0 items-center justify-center rounded-xl border border-pine-100 text-pine-600 transition-colors hover:border-pine-400 hover:bg-pine-50"
              >
                <Pencil className="size-4" />
              </button>
            </div>
            <p className="mt-3 flex-1 text-sm leading-relaxed text-ink-soft">
              {space.blurb}
            </p>
            <ul className="mt-4 flex flex-wrap gap-2">
              {space.features.map((feature) => (
                <li
                  key={feature}
                  className="rounded-full bg-pine-50 px-3 py-1 text-xs font-medium text-pine-700"
                >
                  {feature}
                </li>
              ))}
            </ul>
          </Card>
        ))}
      </div>
    </div>
  );
}
