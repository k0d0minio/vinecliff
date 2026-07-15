import Link from "next/link";
import { notFound } from "next/navigation";
import { ArrowLeft, CalendarPlus, ExternalLink } from "lucide-react";
import { getSpaceById } from "@/lib/db/queries";
import { siteBaseUrl } from "@/lib/email";
import { PageHeader, Card } from "../../components/page-shell";
import { SpaceForm, type SpaceFormData } from "./space-form";

export const dynamic = "force-dynamic";
export const metadata = { title: "Edit space" };

type Props = { params: Promise<{ id: string }> };

export default async function SpaceEditPage({ params }: Props) {
  const { id } = await params;
  const space = await getSpaceById(id).catch(() => null);
  if (!space) notFound();

  const formData: SpaceFormData = {
    id: space.id,
    name: space.name,
    kind: space.kind,
    age: space.age,
    blurb: space.blurb,
    description: space.description,
    image: space.image,
    features: space.features,
    isEvent: space.isEvent,
    blocksEstate: space.blocksEstate,
    active: space.active,
    nightlyRateCents: space.nightlyRateCents,
    weeklyRateCents: space.weeklyRateCents,
    cleaningFeeCents: space.cleaningFeeCents,
    minNights: space.minNights,
    maxGuests: space.maxGuests,
    bufferDays: space.bufferDays,
    minLeadDays: space.minLeadDays,
    maxHorizonMonths: space.maxHorizonMonths,
    sortOrder: space.sortOrder,
  };

  const icalUrl = `${siteBaseUrl()}/api/ical/${space.icalToken}`;

  return (
    <div className="space-y-6">
      <Link
        href="/admin/spaces"
        className="inline-flex items-center gap-1.5 text-sm font-medium text-pine-700 hover:text-amber"
      >
        <ArrowLeft className="size-4" />
        All spaces
      </Link>

      <PageHeader
        title={space.name}
        description={`Public page: /spaces/${space.slug}`}
        actions={
          <a
            href={`${siteBaseUrl()}/spaces/${space.slug}`}
            target="_blank"
            rel="noopener noreferrer"
            className="inline-flex items-center gap-1.5 text-sm font-medium text-pine-700 hover:text-amber"
          >
            View live <ExternalLink className="size-3.5" />
          </a>
        }
      />

      <Card>
        <SpaceForm space={formData} />
      </Card>

      <Card>
        <h2 className="flex items-center gap-2 font-display text-lg text-ink">
          <CalendarPlus className="size-5 text-pine-600" />
          Calendar feed (iCal)
        </h2>
        <p className="mt-2 text-sm leading-relaxed text-ink-soft">
          Subscribe to this space&apos;s bookings and blackouts from Google Calendar, or paste
          the URL into Airbnb/VRBO so external listings block dates booked here. Treat it like
          a password — anyone with the link can see when the space is unavailable.
        </p>
        <code className="mt-3 block overflow-x-auto rounded-xl bg-cream px-4 py-3 text-xs text-pine-700">
          {icalUrl}
        </code>
      </Card>
    </div>
  );
}
