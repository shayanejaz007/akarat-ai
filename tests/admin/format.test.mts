import { test } from "node:test";
import assert from "node:assert/strict";
import {
  ago,
  compact,
  dayLabel,
  full,
  humanize,
  initials,
  jod,
  pct,
  plainAnswer,
  plural,
  tick,
  titleOf,
  usd,
  usdTick,
  when,
  whatsapp,
} from "../../app/admin/_lib/format.ts";

test("compact shortens from ten thousand up, and never shows a trailing .0", () => {
  assert.equal(compact(0), "0");
  assert.equal(compact(null), "0");
  assert.equal(compact(999), "999");
  assert.equal(compact(1284), "1,284");
  assert.equal(compact(9999), "9,999");
  assert.equal(compact(12000), "12K");
  assert.equal(compact(12900), "12.9K");
  assert.equal(compact(123456), "123K");
  assert.equal(compact(1_200_000), "1.2M");
  assert.equal(compact(12_000_000), "12M");
});

test("full, jod and plural keep every digit", () => {
  assert.equal(full(12894), "12,894");
  assert.equal(jod(150000), "150,000 JOD");
  assert.equal(plural(1, "night"), "1 night");
  assert.equal(plural(3, "night"), "3 nights");
  assert.equal(plural(2, "person", "people"), "2 people");
});

test("axis ticks are compact from a thousand up", () => {
  assert.equal(tick(0), "0");
  assert.equal(tick(500), "500");
  assert.equal(tick(1000), "1K");
  assert.equal(tick(1500), "1.5K");
  assert.equal(tick(2_000_000), "2M");
  assert.equal(tick(0.25), "0.25");
});

test("dollars: unknown, a sliver, and to the cent", () => {
  assert.equal(usd(null), "n/a");
  assert.equal(usd(Number.NaN), "n/a");
  assert.equal(usd(0), "$0.00");
  assert.equal(usd(0.004), "< $0.01");
  assert.equal(usd(1234.5), "$1,234.50");
  assert.equal(usdTick(0), "$0");
  assert.equal(usdTick(0.25), "$0.25");
  assert.equal(usdTick(1.5), "$1.5");
  assert.equal(usdTick(2000), "$2K");
});

test("percentages: nothing to divide by, a sliver, and rounding", () => {
  assert.equal(pct(0, 0), "n/a");
  assert.equal(pct(1, 400), "<1%");
  assert.equal(pct(0, 10), "0%");
  assert.equal(pct(1, 3), "33%");
  assert.equal(pct(2, 3), "67%");
});

test("ago counts down from just now to a date, and never rounds up", () => {
  const now = Date.parse("2026-11-03T12:00:00Z");
  const before = (s: number) => new Date(now - s * 1000).toISOString();
  assert.equal(ago(null, now), "never");
  assert.equal(ago("not a date", now), "—");
  assert.equal(ago(before(30), now), "just now");
  assert.equal(ago(before(5 * 60), now), "5 min ago");
  assert.equal(ago(before(59 * 60 + 59), now), "59 min ago");
  assert.equal(ago(before(3 * 3600), now), "3 h ago");
  assert.equal(ago(before(2 * 86400), now), "2 d ago");
  const old = ago("2026-03-01T12:00:00Z", now);
  assert.match(old, /2026/);
  assert.doesNotMatch(old, /ago/);
});

test("days are read at noon, so no time zone moves them", () => {
  assert.equal(dayLabel("2026-11-03"), "3 Nov");
  assert.equal(dayLabel("2026-11-03", true), "Tue 3 Nov");
  assert.equal(when(null), "—");
  assert.equal(when("nonsense"), "—");
});

test("a listing's title in whichever language it has", () => {
  assert.equal(titleOf({ title_en: "Villa in Abdoun", title_ar: "فيلا" }), "Villa in Abdoun");
  assert.equal(titleOf({ title_en: "  ", title_ar: "فيلا في عبدون" }), "فيلا في عبدون");
  assert.equal(titleOf({ title_en: "", title_ar: null }), "Untitled");
  assert.equal(titleOf(null), "Untitled");
});

test("initials from a name, else an email", () => {
  assert.equal(initials("Shayan Ejaz"), "SE");
  assert.equal(initials("  omar  "), "O");
  assert.equal(initials("Ahmad bin Ali Haddad"), "AH");
  assert.equal(initials(null, "lina@example.com"), "L");
  assert.equal(initials("", ""), "?");
});

test("WhatsApp links turn a local Jordanian number international", () => {
  assert.equal(whatsapp("079 123 4567"), "https://wa.me/962791234567");
  assert.equal(whatsapp("+962 79 123 4567"), "https://wa.me/962791234567");
});

test("humanize stored values", () => {
  assert.equal(humanize("apartment"), "Apartment");
  assert.equal(humanize("office_space"), "Office space");
  assert.equal(humanize(null), "—");
});

test("Ask a Lawyer's citation markers become [1,2] in plain text", () => {
  assert.equal(plainAnswer("The rent law 1,2 says so."), "The rent law [1,2] says so.");
  assert.equal(plainAnswer("Stray marker"), "Stray marker");
});
