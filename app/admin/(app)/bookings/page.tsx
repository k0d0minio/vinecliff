import { CalendarDays } from "lucide-react";
import { cn } from "@/lib/utils";
import { buttonVariants } from "../../../components/ui/button";
import { PageHeader, EmptyState } from "../components/page-shell";

export const metadata = { title: "Bookings" };

export default function BookingsPage() {
  return (
    <div className="space-y-8">
      <PageHeader
        title="Bookings"
        description="Stays and event reservations across the farmhouse, carriage house and barn."
        actions={
          <button className={cn(buttonVariants({ variant: "primary", size: "sm" }))}>
            New booking
          </button>
        }
      />
      <EmptyState
        icon={CalendarDays}
        title="No bookings yet"
        description="Once the booking system is connected, reservations and their status will appear here."
      />
    </div>
  );
}
