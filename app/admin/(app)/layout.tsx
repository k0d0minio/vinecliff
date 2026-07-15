import type { Metadata } from "next";
import { Sidebar } from "./components/sidebar";

export const metadata: Metadata = {
  title: {
    default: "Admin",
    template: "%s · Vine Cliff Admin",
  },
  robots: { index: false, follow: false },
};

export default function AdminLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  return (
    <div className="min-h-dvh bg-cream lg:pl-64">
      <Sidebar />
      <main className="mx-auto max-w-5xl px-4 py-6 sm:px-6 sm:py-8 lg:px-10 lg:py-10">
        {children}
      </main>
    </div>
  );
}
