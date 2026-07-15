import Image from "next/image";
import Link from "next/link";
import { Home, Pencil } from "lucide-react";
import { getAllSpaces } from "@/lib/db/queries";
import { formatMoney } from "@/lib/booking/pricing";
import { PageHeader, EmptyState } from "../components/page-shell";

export const dynamic = "force-dynamic";
export const metadata = { title: "Spaces" };

export default async function SpacesAdminPage() {
  const spaces = await getAllSpaces();

  return (
    <div className="space-y-6">
      <PageHeader
        title="Spaces"
        description="Everything guests see about each space — copy, photos, rates and booking rules. Changes go live within a few minutes."
      />

      {spaces.length === 0 ? (
        <EmptyState
          icon={Home}
          title="No spaces found"
          description="Run the database migrations to seed the farmhouse, carriage house, barn and estate package."
        />
      ) : (
        <ul className="space-y-3">
          {spaces.map((space) => (
            <li key={space.id}>
              <Link
                href={`/admin/spaces/${space.id}`}
                className="flex flex-wrap items-center gap-4 rounded-2xl border border-pine-100 bg-cream-100 p-4 transition-colors hover:border-pine-400"
              >
                <div className="relative h-16 w-24 shrink-0 overflow-hidden rounded-xl">
                  <Image src={space.image} alt={space.name} fill sizes="96px" className="object-cover" />
                </div>
                <div className="min-w-40">
                  <p className="font-medium text-ink">{space.name}</p>
                  <p className="text-xs text-stone">{space.kind}</p>
                </div>
                <div className="text-sm text-ink-soft">
                  {formatMoney(space.nightlyRateCents)} / {space.isEvent ? "day" : "night"}
                  {space.weeklyRateCents ? (
                    <span className="text-stone"> · {formatMoney(space.weeklyRateCents)} / week</span>
                  ) : null}
                </div>
                <div className="ml-auto flex items-center gap-3">
                  {!space.active ? (
                    <span className="rounded-full bg-parchment px-2.5 py-0.5 text-xs font-medium text-stone">
                      hidden
                    </span>
                  ) : null}
                  {space.blocksEstate ? (
                    <span className="rounded-full bg-pine-50 px-2.5 py-0.5 text-xs font-medium text-pine-700">
                      whole estate
                    </span>
                  ) : null}
                  <Pencil className="size-4 text-stone" />
                </div>
              </Link>
            </li>
          ))}
        </ul>
      )}
    </div>
  );
}
