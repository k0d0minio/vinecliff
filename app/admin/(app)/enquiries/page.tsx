import Link from "next/link";
import { Archive, CalendarPlus, Inbox, Mail, Phone, RotateCcw, Reply } from "lucide-react";
import { cn } from "@/lib/utils";
import { listEnquiries } from "@/lib/db/queries";
import type { Enquiry } from "@/lib/db/schema";
import { site } from "@/lib/site";
import { PageHeader, EmptyState } from "../components/page-shell";
import { EnquiryStatusBadge } from "../components/badges";
import { setEnquiryStatus } from "./actions";

export const dynamic = "force-dynamic";
export const metadata = { title: "Enquiries" };

const FILTERS: Array<{ key: string; label: string; status?: Enquiry["status"] }> = [
  { key: "new", label: "New", status: "new" },
  { key: "replied", label: "Replied", status: "replied" },
  { key: "converted", label: "Converted", status: "converted" },
  { key: "archived", label: "Archived", status: "archived" },
  { key: "all", label: "All" },
];

type Props = { searchParams: Promise<{ status?: string }> };

function splitName(full: string): { firstName: string; lastName: string } {
  const parts = full.trim().split(/\s+/);
  return {
    firstName: parts[0] ?? "",
    lastName: parts.slice(1).join(" ") || "—",
  };
}

export default async function EnquiriesPage({ searchParams }: Props) {
  const params = await searchParams;
  const filter = FILTERS.find((f) => f.key === params.status) ?? FILTERS[0];
  const rows = await listEnquiries(filter.status);

  return (
    <div className="space-y-6">
      <PageHeader
        title="Enquiries"
        description="Messages from the website's enquiry form. Reply by email, then mark them — or convert one straight into a booking."
      />

      <nav className="flex flex-wrap gap-2">
        {FILTERS.map((f) => (
          <Link
            key={f.key}
            href={`/admin/enquiries?status=${f.key}`}
            className={cn(
              "rounded-full px-3.5 py-1.5 text-sm font-medium transition-colors",
              filter.key === f.key
                ? "bg-pine-700 text-cream"
                : "bg-cream-100 text-ink-soft hover:bg-pine-50"
            )}
          >
            {f.label}
          </Link>
        ))}
      </nav>

      {rows.length === 0 ? (
        <EmptyState
          icon={Inbox}
          title="Nothing here"
          description="Messages sent through the website's enquiry form will collect here so you can reply and turn them into bookings."
        />
      ) : (
        <ul className="space-y-3">
          {rows.map(({ enquiry, spaceName }) => {
            const name = splitName(enquiry.name);
            const convertHref = `/admin/bookings/new?enquiry=${enquiry.id}&firstName=${encodeURIComponent(name.firstName)}&lastName=${encodeURIComponent(name.lastName)}&email=${encodeURIComponent(enquiry.email)}${enquiry.phone ? `&phone=${encodeURIComponent(enquiry.phone)}` : ""}`;
            return (
              <li
                key={enquiry.id}
                className="rounded-2xl border border-pine-100 bg-cream-100 p-5"
              >
                <div className="flex flex-wrap items-center gap-x-4 gap-y-1">
                  <p className="font-medium text-ink">{enquiry.name}</p>
                  <a
                    href={`mailto:${enquiry.email}?subject=${encodeURIComponent(`Your enquiry to ${site.fullName}`)}`}
                    className="inline-flex items-center gap-1.5 text-sm text-ink-soft hover:text-pine-700"
                  >
                    <Mail className="size-3.5 text-stone" />
                    {enquiry.email}
                  </a>
                  {enquiry.phone ? (
                    <span className="inline-flex items-center gap-1.5 text-sm text-ink-soft">
                      <Phone className="size-3.5 text-stone" />
                      {enquiry.phone}
                    </span>
                  ) : null}
                  <span className="ml-auto flex items-center gap-2">
                    {spaceName ? (
                      <span className="rounded-full bg-pine-50 px-2.5 py-0.5 text-xs font-medium text-pine-700">
                        {spaceName}
                      </span>
                    ) : null}
                    <EnquiryStatusBadge status={enquiry.status} />
                  </span>
                </div>
                <p className="mt-3 whitespace-pre-line text-sm leading-relaxed text-ink-soft">
                  {enquiry.message}
                </p>
                <div className="mt-4 flex flex-wrap items-center gap-2 border-t border-pine-100 pt-3 text-sm">
                  <span className="text-xs text-stone">
                    {enquiry.createdAt.toLocaleDateString("en-US", {
                      month: "short",
                      day: "numeric",
                      year: "numeric",
                      timeZone: "America/New_York",
                    })}
                  </span>
                  <span className="ml-auto flex flex-wrap gap-2">
                    {enquiry.status === "new" ? (
                      <form action={setEnquiryStatus}>
                        <input type="hidden" name="enquiryId" value={enquiry.id} />
                        <input type="hidden" name="status" value="replied" />
                        <button className="inline-flex items-center gap-1.5 rounded-full px-3 py-1 font-medium text-pine-700 transition-colors hover:bg-pine-50">
                          <Reply className="size-3.5" />
                          Mark replied
                        </button>
                      </form>
                    ) : null}
                    {enquiry.status !== "converted" ? (
                      <Link
                        href={convertHref}
                        className="inline-flex items-center gap-1.5 rounded-full px-3 py-1 font-medium text-pine-700 transition-colors hover:bg-pine-50"
                      >
                        <CalendarPlus className="size-3.5" />
                        Convert to booking
                      </Link>
                    ) : enquiry.bookingId ? (
                      <Link
                        href={`/admin/bookings/${enquiry.bookingId}`}
                        className="inline-flex items-center gap-1.5 rounded-full px-3 py-1 font-medium text-pine-700 transition-colors hover:bg-pine-50"
                      >
                        <CalendarPlus className="size-3.5" />
                        View booking
                      </Link>
                    ) : null}
                    {enquiry.status !== "archived" ? (
                      <form action={setEnquiryStatus}>
                        <input type="hidden" name="enquiryId" value={enquiry.id} />
                        <input type="hidden" name="status" value="archived" />
                        <button className="inline-flex items-center gap-1.5 rounded-full px-3 py-1 font-medium text-stone transition-colors hover:bg-pine-50">
                          <Archive className="size-3.5" />
                          Archive
                        </button>
                      </form>
                    ) : (
                      <form action={setEnquiryStatus}>
                        <input type="hidden" name="enquiryId" value={enquiry.id} />
                        <input type="hidden" name="status" value="new" />
                        <button className="inline-flex items-center gap-1.5 rounded-full px-3 py-1 font-medium text-stone transition-colors hover:bg-pine-50">
                          <RotateCcw className="size-3.5" />
                          Restore
                        </button>
                      </form>
                    )}
                  </span>
                </div>
              </li>
            );
          })}
        </ul>
      )}
    </div>
  );
}
