"use client";

import { createContext, useContext } from "react";
import type { Api, ApiError } from "../_lib/api";
import type { Overview } from "../_lib/types";
import type { IconName } from "./icons";

export type Theme = "system" | "light" | "dark";

/** What every page of the signed-in panel shares. */
export type Admin = {
  api: Api;
  overview: Overview | null;
  overviewError: ApiError | null;
  overviewAt: number | null;
  refreshOverview: () => Promise<void>;
  signOut: () => Promise<void>;
  theme: Theme;
  setTheme: (t: Theme) => void;
};

export const AdminContext = createContext<Admin | null>(null);

export function useAdmin(): Admin {
  const v = useContext(AdminContext);
  if (!v) throw new Error("useAdmin outside the signed-in panel");
  return v;
}

export type NavItem = {
  href: string;
  label: string;
  icon: IconName;
  /** Words for the command palette's matching. */
  keywords?: string;
  /** How many things here are waiting on an admin, from the overview. */
  count?: (o: Overview | null) => number | undefined;
  urgent?: boolean;
};

export const NAV: { title: string | null; items: NavItem[] }[] = [
  { title: null, items: [{ href: "/admin", label: "Overview", icon: "dashboard", keywords: "home dashboard live stats" }] },
  {
    title: "Marketplace",
    items: [
      { href: "/admin/listings", label: "Listings", icon: "building", keywords: "properties homes status feature verify" },
      {
        href: "/admin/daily-rentals",
        label: "Daily rentals",
        icon: "bed",
        keywords: "review queue approve reject suspend",
        count: o => o?.dailyRentals?.review.pending,
      },
      { href: "/admin/bookings", label: "Bookings", icon: "calendar", keywords: "requests stays nights" },
      { href: "/admin/inquiries", label: "Inquiries", icon: "inbox", keywords: "messages leads contact", count: o => o?.inquiries.new },
    ],
  },
  { title: "Community", items: [{ href: "/admin/users", label: "Users", icon: "users", keywords: "accounts people owners agents roles" }] },
  {
    title: "Trust & safety",
    items: [{ href: "/admin/reports", label: "Reports", icon: "flag", keywords: "reported scam take down", count: o => o?.openReports, urgent: true }],
  },
  {
    title: "AI assistants",
    items: [
      { href: "/admin/property-ai", label: "Property AI", icon: "sparkles", keywords: "advisor claude cost questions" },
      { href: "/admin/ask-a-lawyer", label: "Ask a Lawyer", icon: "scale", keywords: "legal library citations feedback" },
    ],
  },
];

export const SYSTEM_NAV: NavItem = { href: "/admin/system", label: "System", icon: "sliders", keywords: "settings setup migrations session" };

export const ALL_NAV: NavItem[] = [...NAV.flatMap(g => g.items), SYSTEM_NAV];

/** The section a path belongs to: the longest matching href. */
export function navFor(pathname: string): NavItem {
  const path = pathname.replace(/\/+$/, "") || "/admin";
  return (
    ALL_NAV.filter(n => path === n.href || (n.href !== "/admin" && path.startsWith(`${n.href}/`))).sort((a, b) => b.href.length - a.href.length)[0] ??
    ALL_NAV[0]
  );
}
