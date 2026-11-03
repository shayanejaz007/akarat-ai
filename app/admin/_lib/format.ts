/**
 * Number, money, date and text formatting for the admin panel.
 *
 * Pure and import-free, so tests/admin runs it under plain Node. Days from
 * the server ("YYYY-MM-DD") are Amman days (0018_admin_analytics.sql); they
 * are read at noon here so no time zone can move one across midnight.
 */

const strip = (s: string) => s.replace(/\.0$/, "");

/** 1,284 · 12.9K · 4.2M: for stat tiles and anywhere space is short. */
export function compact(n: number | null | undefined): string {
  const v = Number(n ?? 0);
  const a = Math.abs(v);
  if (a >= 1e6) return `${strip((v / 1e6).toFixed(a >= 1e7 ? 0 : 1))}M`;
  if (a >= 1e4) return `${strip((v / 1e3).toFixed(a >= 1e5 ? 0 : 1))}K`;
  return Math.round(v).toLocaleString("en-US");
}

/** Every digit: 12,894. */
export const full = (n: number | null | undefined): string => Number(n ?? 0).toLocaleString("en-US");

export const jod = (n: number | null | undefined): string => `${full(n)} JOD`;

/** Axis ticks: 0 · 500 · 1K · 1.5K · 2M. */
export function tick(v: number): string {
  const a = Math.abs(v);
  if (a >= 1e6) return `${strip((v / 1e6).toFixed(1))}M`;
  if (a >= 1e3) return `${strip((v / 1e3).toFixed(1))}K`;
  return String(Math.round(v * 100) / 100);
}

/** US dollars: "n/a" when unknown, "< $0.01" for a sliver, otherwise to the cent. */
export function usd(n: number | null | undefined): string {
  if (n == null || Number.isNaN(n)) return "n/a";
  if (n > 0 && n < 0.01) return "< $0.01";
  return `$${n.toLocaleString("en-US", { minimumFractionDigits: 2, maximumFractionDigits: 2 })}`;
}

/** Axis ticks in dollars: $0 · $0.25 · $1.5 · $2K. */
export const usdTick = (v: number): string => (v === 0 ? "$0" : Math.abs(v) < 1 ? `$${v.toFixed(2)}` : `$${tick(v)}`);

/** A share as a whole percentage: "<1%" for a sliver, "n/a" with nothing to divide by. */
export function pct(n: number, of: number): string {
  if (!of) return "n/a";
  const p = (n / of) * 100;
  if (p > 0 && p < 1) return "<1%";
  return `${Math.round(p)}%`;
}

/** "just now", "3 min ago", "5 h ago", "2 d ago", then the date. */
export function ago(iso: string | null | undefined, now: number = Date.now()): string {
  if (!iso) return "never";
  const t = new Date(iso).getTime();
  if (Number.isNaN(t)) return "—";
  const s = Math.max(0, (now - t) / 1000);
  if (s < 60) return "just now";
  if (s < 3600) return `${Math.floor(s / 60)} min ago`;
  if (s < 86400) return `${Math.floor(s / 3600)} h ago`;
  if (s < 86400 * 30) return `${Math.floor(s / 86400)} d ago`;
  return new Date(t).toLocaleDateString("en-GB", { day: "numeric", month: "short", year: "numeric" });
}

/** "3 Nov, 14:05". */
export function when(iso: string | null | undefined): string {
  if (!iso) return "—";
  const d = new Date(iso);
  return Number.isNaN(d.getTime())
    ? "—"
    : d.toLocaleString("en-GB", { day: "numeric", month: "short", hour: "2-digit", minute: "2-digit" });
}

/** A "YYYY-MM-DD" day as "3 Nov", or "Tue 3 Nov" with the weekday. */
export function dayLabel(day: string, weekday = false): string {
  const d = new Date(`${day}T12:00:00`);
  return d.toLocaleDateString(
    "en-GB",
    weekday ? { weekday: "short", day: "numeric", month: "short" } : { day: "numeric", month: "short" },
  );
}

/** "3 Nov 2026" for a "YYYY-MM-DD" day. */
export const dayLong = (day: string): string =>
  new Date(`${day}T12:00:00`).toLocaleDateString("en-GB", { day: "numeric", month: "short", year: "numeric" });

/** "1 night", "3 nights". */
export const plural = (n: number, one: string, many = `${one}s`): string => `${full(n)} ${n === 1 ? one : many}`;

/** A listing's title in whichever language it has. */
export const titleOf = (r: { title_en?: string | null; title_ar?: string | null } | null | undefined): string =>
  r?.title_en?.trim() || r?.title_ar?.trim() || "Untitled";

/** Up to two initials from a name, else the first letter of an email, for avatars. */
export function initials(name: string | null | undefined, email?: string | null): string {
  const parts = (name ?? "").trim().split(/\s+/).filter(Boolean);
  if (parts.length) return (parts[0][0] + (parts.length > 1 ? parts[parts.length - 1][0] : "")).toUpperCase();
  const e = (email ?? "").trim();
  return e ? e[0].toUpperCase() : "?";
}

/** A wa.me link for a Jordanian number written the local way (07…) or the international way. */
export const whatsapp = (phone: string): string => `https://wa.me/${phone.replace(/[^\d]/g, "").replace(/^0/, "962")}`;

/** "apartment" → "Apartment", "office_space" → "Office space". */
export function humanize(s: string | null | undefined): string {
  const t = (s ?? "").replace(/[_-]+/g, " ").trim();
  return t ? t[0].toUpperCase() + t.slice(1) : "—";
}

/** An answer from Ask a Lawyer as plain text: citation markers become [1,2]. */
export const plainAnswer = (text: string): string =>
  text.replace(/([^]*)/g, "[$1]").replace(/[-]/g, "");
