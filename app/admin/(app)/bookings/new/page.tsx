import Link from "next/link";
import { ArrowLeft } from "lucide-react";
import { getActiveSpaces } from "@/lib/db/queries";
import { PageHeader, Card } from "../../components/page-shell";
import { NewBookingForm, type BookingPrefill, type SpaceOption } from "./new-booking-form";

export const dynamic = "force-dynamic";
export const metadata = { title: "New booking" };

type Props = {
  searchParams: Promise<{
    firstName?: string;
    lastName?: string;
    email?: string;
    phone?: string;
    space?: string;
    enquiry?: string;
  }>;
};

export default async function NewBookingPage({ searchParams }: Props) {
  const params = await searchParams;
  const spaces = await getActiveSpaces();
  const options: SpaceOption[] = spaces.map((s) => ({
    id: s.id,
    name: s.name,
    isEvent: s.isEvent,
    blocksEstate: s.blocksEstate,
    maxGuests: s.maxGuests,
  }));
  const prefill: BookingPrefill = {
    firstName: params.firstName,
    lastName: params.lastName,
    email: params.email,
    phone: params.phone,
    spaceId: spaces.find((s) => s.slug === params.space)?.id,
    enquiryId: params.enquiry,
  };

  return (
    <div className="space-y-6">
      <Link
        href="/admin/bookings"
        className="inline-flex items-center gap-1.5 text-sm font-medium text-pine-700 hover:text-amber"
      >
        <ArrowLeft className="size-4" />
        All bookings
      </Link>
      <PageHeader
        title="New booking"
        description="Enter a booking taken over the phone or by email. Confirmed bookings block the calendar immediately; owner bookings skip lead-time and minimum-stay rules but never double-book."
      />
      <Card>
        <NewBookingForm spaces={options} prefill={prefill} />
      </Card>
    </div>
  );
}
