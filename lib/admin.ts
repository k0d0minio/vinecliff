// Navigation and metadata for the admin section. Kept data-only so both the
// desktop sidebar and the mobile drawer render from a single source of truth.
import type { LucideIcon } from "lucide-react";
import {
  LayoutDashboard,
  CalendarDays,
  Inbox,
  Home,
  ImageIcon,
  Settings,
} from "lucide-react";

export type AdminNavItem = {
  href: string;
  label: string;
  icon: LucideIcon;
  /** Short line shown under the label on the dashboard grid. */
  description: string;
};

export const adminNav: AdminNavItem[] = [
  {
    href: "/admin",
    label: "Dashboard",
    icon: LayoutDashboard,
    description: "Overview of activity across the estate.",
  },
  {
    href: "/admin/bookings",
    label: "Bookings",
    icon: CalendarDays,
    description: "Stays and event reservations across the calendar.",
  },
  {
    href: "/admin/enquiries",
    label: "Enquiries",
    icon: Inbox,
    description: "Messages and booking requests from guests.",
  },
  {
    href: "/admin/spaces",
    label: "Spaces",
    icon: Home,
    description: "The farmhouse, carriage house and barn.",
  },
  {
    href: "/admin/gallery",
    label: "Gallery",
    icon: ImageIcon,
    description: "Estate photography shown on the public site.",
  },
  {
    href: "/admin/settings",
    label: "Settings",
    icon: Settings,
    description: "Business details, contact and access.",
  },
];

/**
 * Resolve the nav entry for the current pathname. The dashboard (`/admin`) is
 * matched exactly; every other entry matches its own path or any sub-route.
 */
export function activeAdminNav(pathname: string): AdminNavItem | undefined {
  return adminNav.find((item) =>
    item.href === "/admin"
      ? pathname === "/admin"
      : pathname === item.href || pathname.startsWith(`${item.href}/`)
  );
}
