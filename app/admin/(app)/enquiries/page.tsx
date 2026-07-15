import { Inbox } from "lucide-react";
import { PageHeader, EmptyState } from "../components/page-shell";

export const metadata = { title: "Enquiries" };

export default function EnquiriesPage() {
  return (
    <div className="space-y-8">
      <PageHeader
        title="Enquiries"
        description="Messages and booking requests sent through the website and by phone."
      />
      <EmptyState
        icon={Inbox}
        title="No enquiries yet"
        description="Guest messages will collect here so you can reply and turn them into bookings."
      />
    </div>
  );
}
