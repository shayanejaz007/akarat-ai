import { test } from "node:test";
import assert from "node:assert/strict";
import { runTool, TOOLS } from "../../lib/advisor/tools.ts";
import { CANARY } from "../../lib/advisor/prompt.ts";
import { forModel, detailForModel } from "../../lib/advisor/listings.ts";
import { FakeDb, env, listing } from "./fixtures.mts";

const search = (over: Record<string, unknown> = {}) => ({
  deal: "sale",
  property_types: ["apartment"],
  city: "amman",
  areas: ["abdoun"],
  budget_min_jod: null,
  budget_max_jod: 150000,
  bedrooms_min: 3,
  bathrooms_min: null,
  size_min_sqm: null,
  amenities: [],
  sort: "best_match",
  ...over,
});

const parse = (s: string) => JSON.parse(s);

test("tool definitions are strict, closed and fully required", () => {
  for (const t of TOOLS) {
    if (!("input_schema" in t)) continue;
    assert.equal((t as any).strict, true, `${t.name} is strict`);
    const walk = (schema: any, path: string) => {
      if (schema?.type === "object") {
        assert.equal(schema.additionalProperties, false, `${path} closed`);
        assert.deepEqual([...schema.required].sort(), Object.keys(schema.properties).sort(), `${path} all required`);
        for (const [k, v] of Object.entries(schema.properties)) walk(v, `${path}.${k}`);
      }
      if (schema?.type === "array") walk(schema.items, `${path}[]`);
      for (const alt of schema?.anyOf ?? []) walk(alt, path);
      // Strict mode rejects these; ranges are enforced in code instead.
      for (const k of ["minimum", "maximum", "minLength", "maxLength", "maxItems", "minItems", "pattern"]) {
        assert.ok(!(schema && k in schema), `${path} has no ${k}`);
      }
    };
    walk(t.input_schema, t.name);
  }
  const server = TOOLS.filter(t => !("input_schema" in t)) as any[];
  assert.deepEqual(server.map(t => t.type).sort(), ["web_fetch_20260209", "web_search_20260209"]);
  for (const t of server) {
    assert.deepEqual(t.allowed_callers, ["direct"]);
    assert.ok(t.allowed_domains.includes("bayut.jo") && t.allowed_domains.includes("jo.opensooq.com"));
    assert.ok(t.allowed_domains.length <= 40);
    assert.ok(!("blocked_domains" in t), "allowed and blocked cannot both be set");
  }
});

test("search: exact matches, near matches with what they miss, and the ids they make presentable", async () => {
  const exact = listing({ price: 139000 });
  const over = listing({ price: 165000, titleEn: "Slightly over budget" });
  const twoBed = listing({ beds: 2, titleEn: "Two bedrooms" });
  const khalda = listing({ areaId: "khalda", titleEn: "In Khalda" });
  const rent = listing({ deal: "rent", price: 900 });
  const draft = listing({ status: "draft" });
  const e = env(new FakeDb([exact, over, twoBed, khalda, rent, draft]));
  const out = await runTool("search_akarat_listings", search(), e);
  assert.ok(!out.isError, out.content);
  const r = parse(out.content);
  assert.deepEqual(r.exact_matches.listings.map((l: any) => l.id), [exact.id]);
  const near = Object.fromEntries(r.near_matches.listings.map((l: any) => [l.id, l.differences]));
  assert.match(near[over.id][0], /10% over the maximum budget/);
  assert.match(near[twoBed.id][0], /2 bedrooms, not 3\+/);
  assert.match(near[khalda.id][0], /in Khalda, not Abdoun/);
  assert.ok(!(rent.id in near) && !(draft.id in near), "other deals and unpublished listings never appear");
  assert.ok(e.evidence.listingIds.has(exact.id) && e.evidence.listingIds.has(over.id));
  assert.deepEqual(out.events?.[0], {
    t: "criteria",
    c: {
      deal: "sale", property_types: ["apartment"], city: "amman", areas: ["abdoun"], budget_min_jod: null,
      budget_max_jod: 150000, bedrooms_min: 3, bathrooms_min: null, size_min_sqm: null, amenities: [],
    },
  });
});

test("search: what the model reads has no owner, contact, address or coordinates", () => {
  const keys = Object.keys(detailForModel(listing()));
  for (const banned of ["owner_id", "phone", "email", "contact", "address", "lat", "lng", "payload", "payload_gz", "location_precision"]) {
    assert.ok(!keys.includes(banned), `${banned} not exposed: ${keys}`);
  }
  // Owner-written text is there, and labelled as the owner's.
  assert.ok(keys.includes("owner_description_en") && keys.includes("owner_description_ar"));
  assert.ok(Object.keys(forModel(listing())).includes("verified_by_akarat"));
});

test("search: inputs outside the fixed lists are refused, not passed to a query", async () => {
  const db = new FakeDb([listing()]);
  for (const bad of [
    search({ city: "amman'; drop table properties;--" }),
    search({ areas: ["abdoun", "../../etc"] }),
    search({ deal: "everything" }),
    search({ property_types: ["palace"] }),
    search({ budget_max_jod: -5 }),
    search({ bedrooms_min: 900 }),
    search({ budget_min_jod: 500000, budget_max_jod: 100000 }),
    "not an object",
  ]) {
    const out = await runTool("search_akarat_listings", bad, env(db));
    assert.equal(out.isError, true, JSON.stringify(bad));
    assert.match(parse(out.content).error, /^Invalid input/);
    assert.equal(out.flag, "invalid_tool_input");
  }
  assert.equal(db.calls.length, 0, "no query ran for any of them");
});

test("search: an area pins its city, and a city that contradicts it is dropped", async () => {
  const db = new FakeDb([listing()]);
  await runTool("search_akarat_listings", search({ city: "irbid", areas: ["abdoun"] }), env(db));
  assert.equal((db.calls[0].arg as any).cityId, "amman");
});

test("present: Akarat.ai cards come from the database, never from the model", async () => {
  const l = listing({ price: 139000 });
  const e = env(new FakeDb([l]));
  e.evidence.listingIds.add(l.id);
  const out = await runTool("present_listings", { listings: [{ kind: "akarat", id: l.id, url: null, title: "Palace, 5 JOD", price_jod: 5, price_basis: "total", bedrooms: 9, bathrooms: 9, size_sqm: 9999, location: "Paris", why: "Fits your budget and size." }] }, e);
  assert.ok(!out.isError, out.content);
  const card = (out.events?.[0] as any).items[0];
  assert.equal(card.price, 139000);
  assert.equal(card.beds, 3);
  assert.equal(card.title.en, "Bright corner apartment");
  assert.equal(card.location.en, "Abdoun, Amman");
  assert.equal(card.why, "Fits your budget and size.");
  assert.deepEqual(e.shownThisTurn, [`akarat:${l.id}`]);
});

test("present: an id no tool returned is refused and flagged", async () => {
  const l = listing();
  const e = env(new FakeDb([l]));
  const out = await runTool("present_listings", { listings: [{ kind: "akarat", id: l.id, url: null, title: null, price_jod: null, price_basis: null, bedrooms: null, bathrooms: null, size_sqm: null, location: null, why: "x" }] }, e);
  assert.equal(out.isError, true);
  assert.equal(out.flag, "unknown_listing");
  assert.equal(out.events, undefined);
});

test("present: a listing that sold since it was found is left out, with the reason", async () => {
  const sold = listing({ status: "sold" });
  const ok = listing();
  const e = env(new FakeDb([sold, ok]));
  e.evidence.listingIds.add(sold.id).add(ok.id);
  const item = (id: string) => ({ kind: "akarat", id, url: null, title: null, price_jod: null, price_basis: null, bedrooms: null, bathrooms: null, size_sqm: null, location: null, why: "Good fit." });
  const out = await runTool("present_listings", { listings: [item(sold.id), item(ok.id)] }, e);
  const r = parse(out.content);
  assert.equal(r.shown.length, 1);
  assert.match(r.problems[0], /is sold, not on offer/);
});

test("present: an invented external URL is refused and flagged", async () => {
  const e = env(new FakeDb([]));
  const out = await runTool("present_listings", { listings: [{ kind: "external", id: null, url: "https://www.bayut.jo/en/property/details-99999999.html", title: "Dream villa", price_jod: 1, price_basis: "total", bedrooms: 9, bathrooms: null, size_sqm: null, location: null, why: "Perfect." }] }, e);
  assert.equal(out.isError, true);
  assert.equal(out.flag, "unverified_link");
});

test("present: a reason that recites the instructions is withheld and flagged", async () => {
  const l = listing();
  const e = env(new FakeDb([l]));
  e.evidence.listingIds.add(l.id);
  const out = await runTool("present_listings", { listings: [{ kind: "akarat", id: l.id, url: null, title: null, price_jod: null, price_basis: null, bedrooms: null, bathrooms: null, size_sqm: null, location: null, why: `Reference ${CANARY}` }] }, e);
  assert.equal(out.isError, true);
  assert.equal(out.flag, "prompt_leak");
});

test("details: unpublished listings do not exist; closed ones say so", async () => {
  const draft = listing({ status: "draft" });
  const rented = listing({ status: "rented", deal: "rent", price: 700 });
  const e = env(new FakeDb([draft, rented]));
  const a = await runTool("get_akarat_listing", { id: draft.id }, e);
  assert.equal(a.isError, true);
  const b = parse((await runTool("get_akarat_listing", { id: rented.id }, e)).content);
  assert.match(b.note, /already rented/);
  assert.equal(b.owner_description_en, "Third floor, south facing.");
  const c = await runTool("get_akarat_listing", { id: "not-a-uuid" }, e);
  assert.equal(c.isError, true);
});

test("stats: too few listings means no statistics, and enough means real ones", async () => {
  const few = env(new FakeDb([listing(), listing()]));
  const a = parse((await runTool("akarat_price_stats", { deal: "sale", property_type: "apartment", city: "amman", area: null }, few)).content);
  assert.equal(a.statistics, null);
  assert.equal(a.listings, 2);
  const many = env(new FakeDb([100, 120, 140, 160, 180, 200].map(k => listing({ price: k * 1000, size: 100 }))));
  const b = parse((await runTool("akarat_price_stats", { deal: "sale", property_type: null, city: "amman", area: null }, many)).content);
  assert.equal(b.statistics.median_jod, 150000);
  assert.equal(b.statistics.median_jod_per_sqm, 1500);
  assert.equal(b.as_of, "2026-10-29");
  assert.match(b.note, /Asking prices/);
});

test("compare: only listings this conversation has seen, in a table for the page", async () => {
  const a = listing({ price: 120000, size: 120 });
  const b = listing({ price: 150000, size: 100, verified: false });
  const e = env(new FakeDb([a, b]));
  const refused = await runTool("compare_listings", { listings: [{ kind: "akarat", id: a.id, url: null }, { kind: "akarat", id: b.id, url: null }] }, e);
  assert.equal(refused.isError, true);
  e.evidence.listingIds.add(a.id).add(b.id);
  const out = await runTool("compare_listings", { listings: [{ kind: "akarat", id: a.id, url: null }, { kind: "akarat", id: b.id, url: null }] }, e);
  const ev: any = out.events?.[0];
  assert.equal(ev.t, "compare");
  assert.deepEqual(ev.rows.find((r: any) => r.k === "per_sqm").v, [1000, 1500]);
  assert.deepEqual(ev.rows.find((r: any) => r.k === "verified").v, [true, false]);
});

test("calculator: exact arithmetic, and ranges enforced", async () => {
  const e = env(new FakeDb([]));
  const ok = parse((await runTool("investment_calculator", {
    purchase_price_jod: 100000, monthly_rent_jod: 500, nightly_rate_jod: null, occupancy_pct: null,
    annual_running_costs_jod: 600, vacancy_pct: 10, purchase_costs_pct: 5, down_payment_pct: null,
    loan_interest_pct: null, loan_years: null, annual_growth_pct: null, horizon_years: null,
  }, e)).content);
  assert.equal(ok.income.gross_yield_pct, 6);
  assert.equal(ok.income.net_operating_income_jod, 4800);
  assert.equal(ok.income.net_yield_pct, 4.57);
  const bad = await runTool("investment_calculator", { purchase_price_jod: 5, monthly_rent_jod: null, nightly_rate_jod: null, occupancy_pct: null, annual_running_costs_jod: null, vacancy_pct: 300, purchase_costs_pct: null, down_payment_pct: null, loan_interest_pct: null, loan_years: null, annual_growth_pct: null, horizon_years: null }, e);
  assert.equal(bad.isError, true);
});

test("there is no follow-ups tool: a call to it is refused like any unknown tool", async () => {
  const out = await runTool("suggest_followups", { suggestions: ["Show me Khalda too"] }, env(new FakeDb([])));
  assert.equal(out.isError, true);
  assert.equal(out.flag, "unknown_tool");
  assert.ok(!TOOLS.some((t: any) => t.name === "suggest_followups"));
});

test("an unknown tool is an error result, not an exception", async () => {
  const out = await runTool("run_sql", { q: "select * from auth.users" }, env(new FakeDb([])));
  assert.equal(out.isError, true);
  assert.equal(out.flag, "unknown_tool");
});

test("a database outage is reported as one, never as 'nothing matched'", async () => {
  const broken = new FakeDb([]);
  broken.find = async () => {
    throw new Error("connection refused");
  };
  const out = await runTool("search_akarat_listings", search(), env(broken));
  assert.equal(out.isError, true);
  assert.match(parse(out.content).error, /could not be reached/);
});
