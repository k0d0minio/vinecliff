"use client";

import { useState } from "react";
import Link from "next/link";
import { usePathname } from "next/navigation";
import { Menu, X, ExternalLink, LogOut } from "lucide-react";
import { cn } from "@/lib/utils";
import { adminNav, activeAdminNav } from "@/lib/admin";
import { logout } from "../actions";

function NavLinks({ onNavigate }: { onNavigate?: () => void }) {
  const pathname = usePathname();
  const active = activeAdminNav(pathname);

  return (
    <nav className="flex flex-col gap-1">
      {adminNav.map((item) => {
        const Icon = item.icon;
        const isActive = active?.href === item.href;
        return (
          <Link
            key={item.href}
            href={item.href}
            onClick={onNavigate}
            aria-current={isActive ? "page" : undefined}
            className={cn(
              "flex items-center gap-3 rounded-xl px-3 py-2.5 text-sm font-medium transition-colors",
              isActive
                ? "bg-pine-700 text-cream"
                : "text-cream/70 hover:bg-cream/10 hover:text-cream"
            )}
          >
            <Icon className="size-4.5 shrink-0" />
            {item.label}
          </Link>
        );
      })}
    </nav>
  );
}

function SidebarBody({ onNavigate }: { onNavigate?: () => void }) {
  return (
    <div className="flex h-full flex-col">
      <div className="px-3 py-6">
        <Link
          href="/admin"
          onClick={onNavigate}
          className="block px-3"
        >
          <span className="font-display text-2xl text-cream">Vine Cliff</span>
          <span className="mt-0.5 block eyebrow text-amber-soft">
            Estate Admin
          </span>
        </Link>
      </div>

      <div className="flex-1 overflow-y-auto px-3">
        <NavLinks onNavigate={onNavigate} />
      </div>

      <div className="mt-auto space-y-1 border-t border-cream/10 px-3 py-4">
        <Link
          href="/"
          target="_blank"
          className="flex items-center gap-3 rounded-xl px-3 py-2.5 text-sm font-medium text-cream/70 transition-colors hover:bg-cream/10 hover:text-cream"
        >
          <ExternalLink className="size-4.5 shrink-0" />
          View website
        </Link>
        <form action={logout}>
          <button
            type="submit"
            className="flex w-full items-center gap-3 rounded-xl px-3 py-2.5 text-sm font-medium text-cream/70 transition-colors hover:bg-cream/10 hover:text-cream"
          >
            <LogOut className="size-4.5 shrink-0" />
            Sign out
          </button>
        </form>
      </div>
    </div>
  );
}

export function Sidebar() {
  const [open, setOpen] = useState(false);
  const pathname = usePathname();
  const active = activeAdminNav(pathname);
  const close = () => setOpen(false);

  return (
    <>
      {/* Mobile top bar */}
      <header className="sticky top-0 z-30 flex h-14 items-center justify-between border-b border-pine-100 bg-cream/90 px-4 backdrop-blur-md lg:hidden">
        <button
          type="button"
          aria-label="Open navigation"
          onClick={() => setOpen(true)}
          className="flex size-9 items-center justify-center rounded-xl text-pine-900 transition-colors hover:bg-pine-50"
        >
          <Menu className="size-5" />
        </button>
        <span className="font-display text-lg text-pine-900">
          {active?.label ?? "Admin"}
        </span>
        <Link
          href="/admin"
          className="font-display text-lg text-pine-900"
          aria-label="Vine Cliff admin home"
        >
          VC
        </Link>
      </header>

      {/* Desktop sidebar */}
      <aside className="fixed inset-y-0 left-0 hidden w-64 bg-pine-900 lg:block">
        <SidebarBody />
      </aside>

      {/* Mobile drawer */}
      {open ? (
        <div className="fixed inset-0 z-50 lg:hidden">
          <button
            type="button"
            aria-label="Close navigation"
            onClick={close}
            className="absolute inset-0 bg-pine-900/60 backdrop-blur-sm"
          />
          <div className="absolute inset-y-0 left-0 flex w-[17rem] max-w-[82%] flex-col bg-pine-900 shadow-lift">
            <button
              type="button"
              aria-label="Close navigation"
              onClick={close}
              className="absolute right-3 top-5 flex size-9 items-center justify-center rounded-xl text-cream/70 transition-colors hover:bg-cream/10 hover:text-cream"
            >
              <X className="size-5" />
            </button>
            <SidebarBody onNavigate={close} />
          </div>
        </div>
      ) : null}
    </>
  );
}
