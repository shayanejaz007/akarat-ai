// The listing quality score (lib/listing-score.js) and the database rules
// around it and around "price on request" (migration 0025), on a real
// Postgres (PGlite).
import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { PGlite } from "@electric-sql/pglite";
import { QUALITY_MAX, QUALITY_PARTS, scoreBand, scoreListing } from "../../lib/listing-score.js";

const photo = (i: number) => ({ url: `https://x.test/p${i}.jpg`, type: "image" });
const LONG_EN = "A bright corner apartment on a quiet street. ".repeat(10);
const LONG_AR = "شقة زاوية مشمسة في شارع هادئ قريبة من المدارس. ".repeat(10);

const complete = {
  row: {
    deal: "sale", property_type: "apartment", city_id: "amman", neighborhood_id: "abdoun", lat: 31.95, lng: 35.88,
    price_jod: 150000, price_on_request: false, bedrooms: 3, bathrooms: 2, area_sqm: 180, year_built: 2015,
    title_en: "Three-bedroom apartment in Abdoun", title_ar: "شقة ثلاث غرف في عبدون",
  },
  payload: {
    description_en: LONG_EN, description_ar: LONG_AR, amenities: ["parking", "elevator", "heating"],
    images: [...Array.from({ length: 12 }, (_, i) => photo(i)), { url: "https://x.test/v.mp4", type: "video" }],
    contact: { phone: "0791234567" },
  },
};

test("the parts add up to 100", () => {
  assert.equal(QUALITY_MAX, 100);
});

test("a complete listing scores 100 and has nothing missing", () => {
  const r = scoreListing(complete.row, complete.payload);
  assert.equal(r.score, 100);
  assert.deepEqual(r.missing, []);
  assert.equal(scoreBand(r.score), "excellent");
});

test("an empty listing scores low, and photos are the biggest thing missing", () => {
  const r = scoreListing({ deal: "sale", property_type: "apartment", price_jod: 0, title_en: "Flat" }, {});
  assert.ok(r.score < 15, `scored ${r.score}`);
  assert.equal(r.missing[0], "photos");
  assert.equal(scoreBand(r.score), "poor");
});

test("photos count up to ten; videos are not photos", () => {
  const with5 = scoreListing(complete.row, { ...complete.payload, images: Array.from({ length: 5 }, (_, i) => photo(i)) });
  assert.equal(with5.parts.photos, 13);
  assert.equal(with5.parts.video, 0);
  const with30 = scoreListing(complete.row, { ...complete.payload, images: Array.from({ length: 30 }, (_, i) => photo(i)) });
  assert.equal(with30.parts.photos, QUALITY_PARTS.photos);
  const videoOnly = scoreListing(complete.row, { ...complete.payload, images: [{ url: "https://x.test/a.mov" }] });
  assert.equal(videoOnly.parts.photos, 0);
  assert.equal(videoOnly.parts.video, QUALITY_PARTS.video);
});

test("price on request loses only the price points", () => {
  const r = scoreListing({ ...complete.row, price_on_request: true, price_jod: 0 }, complete.payload);
  assert.equal(r.score, 100 - QUALITY_PARTS.price);
  assert.deepEqual(r.missing, ["price"]);
});

test("one language earns the description but not the both-languages points", () => {
  const r = scoreListing({ ...complete.row, title_ar: "" }, { ...complete.payload, description_ar: "" });
  assert.equal(r.parts.description, QUALITY_PARTS.description);
  assert.equal(r.parts.languages, 0);
});

test("land is judged on its plot, not rooms or amenities", () => {
  const land = scoreListing(
    { ...complete.row, property_type: "land", bedrooms: null, bathrooms: null, area_sqm: null, year_built: null, land_sqm: 900 },
    { ...complete.payload, amenities: [] },
  );
  assert.equal(land.parts.facts, QUALITY_PARTS.facts);
  assert.equal(land.parts.amenities, QUALITY_PARTS.amenities);
  const flat = scoreListing({ ...complete.row, year_built: null, area_sqm: null }, complete.payload);
  assert.ok(flat.parts.facts < QUALITY_PARTS.facts);
});

test("the place counts town, neighbourhood and pin", () => {
  assert.equal(scoreListing({ ...complete.row, lat: null, lng: null }, complete.payload).parts.location, 10);
  assert.equal(scoreListing({ ...complete.row, neighborhood_id: null, lat: null, lng: null }, complete.payload).parts.location, 5);
});

/* ── The database rules (migration 0025) ─────────────────────────────── */

const SETUP = `
do $$ begin
  if not exists (select 1 from pg_roles where rolname = 'anon') then create role anon nologin; end if;
  if not exists (select 1 from pg_roles where rolname = 'authenticated') then create role authenticated nologin; end if;
  if not exists (select 1 from pg_roles where rolname = 'service_role') then create role service_role nologin bypassrls; end if;
end $$;
create schema if not exists auth;
create function auth.role() returns text language sql stable as $$
  select nullif(current_setting('request.jwt.claim.role', true), '')
$$;
grant usage on schema auth to anon, authenticated, service_role;
grant execute on function auth.role() to anon, authenticated, service_role;
grant usage on schema public to anon, authenticated, service_role;

create type public.deal_type as enum ('sale', 'rent', 'daily');
create table public.properties (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid,
  status text not null default 'active',
  deal public.deal_type not null,
  property_type text not null default 'apartment',
  price_jod integer not null check (price_jod >= 0),
  title_en text not null default 't',
  verified boolean not null default false,
  featured boolean not null default false,
  views integer not null default 0,
  saves integer not null default 0,
  inquiries_count integer not null default 0,
  payload_gz text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create table public.profiles (id uuid primary key, role text, verified boolean);
grant select, insert, update on public.properties to authenticated;
grant all on public.properties to service_role;
`;

// 0001's and 0013's triggers, which 0025 builds on.
const TRIGGERS = `
create trigger properties_keep_staff_fields before insert or update on public.properties
  for each row execute function public.keep_staff_fields();
`;

async function db() {
  const pg = new PGlite();
  await pg.exec(SETUP);
  await pg.exec(readFileSync(new URL("../../supabase/migrations/0025_listing_quality.sql", import.meta.url), "utf8"));
  await pg.exec(TRIGGERS);
  return pg;
}

// Runs as an owner through the API: the authenticated role, no staff claim.
async function asOwner<T>(pg: PGlite, sql: string, params: unknown[] = []) {
  await pg.exec("set role authenticated; set request.jwt.claim.role = 'authenticated';");
  try {
    return await pg.query<T>(sql, params);
  } finally {
    await pg.exec("reset role; reset request.jwt.claim.role;");
  }
}

test("an owner cannot set or change the score", async () => {
  const pg = await db();
  const ins = await asOwner<{ id: string; quality_score: number | null }>(
    pg, "insert into properties (deal, price_jod, quality_score) values ('sale', 100, 100) returning id, quality_score",
  );
  assert.equal(ins.rows[0].quality_score, null);
  const id = ins.rows[0].id;
  await pg.query("update properties set quality_score = 40, quality_scored_at = now() where id = $1", [id]);
  await asOwner(pg, "update properties set quality_score = 99 where id = $1", [id]);
  const after = await pg.query<{ quality_score: number }>("select quality_score from properties where id = $1", [id]);
  assert.equal(after.rows[0].quality_score, 40);
});

test("scoring does not change when the listing was last edited", async () => {
  const pg = await db();
  const { rows } = await pg.query<{ id: string; updated_at: string }>(
    "insert into properties (deal, price_jod, updated_at) values ('sale', 100, '2026-01-01T00:00:00Z') returning id, updated_at",
  );
  await pg.query("update properties set quality_score = 70, quality_scored_at = now(), quality_parts = '{}' where id = $1", [rows[0].id]);
  const scored = await pg.query<{ updated_at: Date }>("select updated_at from properties where id = $1", [rows[0].id]);
  assert.equal(new Date(scored.rows[0].updated_at).toISOString(), "2026-01-01T00:00:00.000Z");
  // A real edit still moves it, and the listing is due a new score.
  await asOwner(pg, "update properties set price_jod = 120 where id = $1", [rows[0].id]);
  const due = await pg.query<{ id: string }>("select * from listings_to_score(10) as id");
  assert.equal(due.rows.length, 1);
});

test("a view, a save or an inquiry is not an edit: nothing moves, nothing is due a new score", async () => {
  const pg = await db();
  const { rows } = await pg.query<{ id: string }>(
    "insert into properties (deal, price_jod, updated_at) values ('sale', 100, '2026-01-01T00:00:00Z') returning id",
  );
  await pg.query("update properties set quality_score = 70, quality_scored_at = '2026-01-02T00:00:00Z' where id = $1", [rows[0].id]);
  await pg.query("update properties set views = views + 1, saves = saves + 1, inquiries_count = inquiries_count + 1 where id = $1", [rows[0].id]);
  const after = await pg.query<{ updated_at: Date }>("select updated_at from properties where id = $1", [rows[0].id]);
  assert.equal(new Date(after.rows[0].updated_at).toISOString(), "2026-01-01T00:00:00.000Z");
  const due = await pg.query("select * from listings_to_score(10)");
  assert.equal(due.rows.length, 0);
});

test("price on request clears the price; a daily rental always keeps its price", async () => {
  const pg = await db();
  const sale = await asOwner<{ price_jod: number; price_on_request: boolean }>(
    pg, "insert into properties (deal, price_jod, price_on_request) values ('sale', 250000, true) returning price_jod, price_on_request",
  );
  assert.deepEqual(sale.rows[0], { price_jod: 0, price_on_request: true });
  const daily = await asOwner<{ price_jod: number; price_on_request: boolean }>(
    pg, "insert into properties (deal, price_jod, price_on_request) values ('daily', 60, true) returning price_jod, price_on_request",
  );
  assert.deepEqual(daily.rows[0], { price_jod: 60, price_on_request: false });
});

test("only the server can ask which listings need scoring", async () => {
  const pg = await db();
  await assert.rejects(asOwner(pg, "select * from listings_to_score(10)"));
});
