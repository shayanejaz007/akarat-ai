// Migrations 0023 (locations) and 0024 (services) on a real Postgres: what a
// customer can and cannot do, what the admin panel's functions write, and
// that the table itself is closed to the API.
import { test, before } from "node:test";
import assert from "node:assert/strict";
import type { PGlite } from "@electric-sql/pglite";
import { USERS, asService, asUser, errorOf, freshDb } from "./db.mts";

let db: PGlite;
before(async () => {
  db = await freshDb();
});

const today = new Intl.DateTimeFormat("en-CA", { timeZone: "Asia/Amman" }).format(new Date());
const inDays = (n: number) => new Intl.DateTimeFormat("en-CA", { timeZone: "Asia/Amman" }).format(new Date(Date.now() + n * 86_400_000));
let tokens = 0;
const token = () => `00000000-0000-4000-8000-${String(++tokens).padStart(12, "0")}`;

const valid = (over: Record<string, unknown> = {}) => ({
  client_token: token(),
  category_id: "plumbing",
  description: "The kitchen sink drain is blocked and water is leaking under it.",
  governorate_id: "amman",
  city_id: "amman",
  neighborhood_id: "abdoun",
  address: "Building 12, Zahran Street, second floor",
  preferred_date: today,
  preferred_window: "morning",
  urgency: "urgent",
  photos: [],
  contact_name: "Lina Haddad",
  contact_phone: "079 555 0101",
  contact_email: "lina@example.com",
  lang: "en",
  platform: "web",
  ...over,
});

const create = (user: string | null, p: Record<string, unknown>) =>
  asUser<{ r: { id: string; ref: string; status: string; duplicate: boolean } }>(db, user, "select public.create_service_request($1::jsonb) as r", [JSON.stringify(p)]).then(x => x.rows[0].r);
const mine = (user: string) => asUser<{ r: Record<string, unknown>[] }>(db, user, "select public.my_service_requests() as r").then(x => x.rows[0].r);

test("locations: 12 governorates, every city in one, old ids kept and renamed", async () => {
  const g = await db.query<{ n: number }>("select count(*)::int as n from public.governorates");
  assert.equal(g.rows[0].n, 12);
  const orphans = await db.query<{ n: number }>("select count(*)::int as n from public.cities where governorate_id is null");
  assert.equal(orphans.rows[0].n, 0);
  const amman = await db.query<{ name_en: string; governorate_id: string }>("select name_en, governorate_id from public.cities where id = 'amman'");
  assert.deepEqual(amman.rows[0], { name_en: "Amman", governorate_id: "amman" });
  const many = await db.query<{ c: number; h: number }>("select (select count(*)::int from public.cities) as c, (select count(*)::int from public.neighborhoods) as h");
  assert.ok(many.rows[0].c > 1000 && many.rows[0].h > 400, JSON.stringify(many.rows[0]));
});

test("locations: running 0023 again keeps what an admin edited", async () => {
  await db.exec("update public.cities set name_en = 'Amman, edited', edited = true where id = 'amman'");
  const { readFileSync } = await import("node:fs");
  await db.exec(readFileSync(new URL("../../supabase/migrations/0023_locations.sql", import.meta.url), "utf8"));
  const r = await db.query<{ name_en: string }>("select name_en from public.cities where id = 'amman'");
  assert.equal(r.rows[0].name_en, "Amman, edited");
  await db.exec("update public.cities set name_en = 'Amman', edited = false where id = 'amman'");
});

test("categories: fourteen to start with, readable by anyone, inactive ones hidden", async () => {
  const all = await asUser<{ id: string }>(db, null, "select id from public.service_categories order by sort");
  assert.equal(all.rows.length, 14);
  assert.equal(all.rows.at(-1)!.id, "custom");
  await db.exec("update public.service_categories set active = false where id = 'pest'");
  const shown = await asUser<{ id: string }>(db, null, "select id from public.service_categories");
  assert.ok(!shown.rows.some(r => r.id === "pest"));
  assert.match(String(await errorOf(create(USERS.lina, valid({ category_id: "pest" })))), /invalid:category_id/);
  await db.exec("update public.service_categories set active = true where id = 'pest'");
});

test("create: a valid request gets a reference, its history and the admins' notice", async () => {
  const r = await create(USERS.lina, valid());
  assert.match(r.ref, /^SR-\d{6}$/);
  assert.equal(r.status, "pending");
  assert.equal(r.duplicate, false);
  const events = await db.query<{ kind: string; public: boolean }>("select kind, public from public.service_request_events where request_id = $1", [r.id]);
  assert.deepEqual(events.rows, [{ kind: "created", public: true }]);
  const notes = await db.query<{ user_id: string; kind: string }>("select user_id, kind from public.notifications where service_request_id = $1", [r.id]);
  assert.deepEqual(notes.rows, [{ user_id: USERS.admin, kind: "service_new" }]);
});

test("create: the same submission twice is one request", async () => {
  const p = valid();
  const first = await create(USERS.omar, p);
  const again = await create(USERS.omar, p);
  assert.equal(again.ref, first.ref);
  assert.equal(again.duplicate, true);
  const n = await db.query<{ n: number }>("select count(*)::int as n from public.service_requests where client_token = $1", [p.client_token]);
  assert.equal(n.rows[0].n, 1);
});

test("create: every field is checked", async () => {
  const cases: [Record<string, unknown>, string][] = [
    [{ client_token: "not-a-uuid" }, "invalid:client_token"],
    [{ category_id: "nope" }, "invalid:category_id"],
    [{ category_id: "custom", custom_service: "" }, "invalid:custom_service"],
    [{ description: "too short" }, "invalid:description"],
    [{ governorate_id: "nowhere" }, "invalid:governorate_id"],
    [{ governorate_id: "irbid" }, "invalid:city_id"],
    [{ neighborhood_id: "sweimeh" }, "invalid:neighborhood_id"],
    [{ address: "" }, "invalid:address"],
    [{ lat: 31.95 }, "invalid:lat"],
    [{ lat: 10, lng: 35.9 }, "invalid:lat"],
    [{ preferred_date: "2020-01-01" }, "invalid:preferred_date"],
    [{ preferred_date: inDays(400) }, "invalid:preferred_date"],
    [{ preferred_window: "midnight" }, "invalid:preferred_window"],
    [{ urgency: "whenever" }, "invalid:urgency"],
    [{ photos: ["a", "b", "c", "d", "e", "f", "g"] }, "invalid:photos"],
    [{ photos: [`${USERS.omar}/someone-else.jpg`] }, "invalid:photos"],
    [{ photos: [`${USERS.lina}/never-uploaded.jpg`] }, "invalid:photos"],
    [{ photos: [`${USERS.lina}/../escape.jpg`] }, "invalid:photos"],
    [{ contact_name: "L" }, "invalid:contact_name"],
    [{ contact_phone: "call me" }, "invalid:contact_phone"],
    [{ contact_email: "not an email" }, "invalid:contact_email"],
  ];
  for (const [over, code] of cases) {
    assert.match(String(await errorOf(create(USERS.lina, valid(over)))), new RegExp(code), JSON.stringify(over));
  }
});

test("create: a custom service carries its own name; photos must be uploaded first", async () => {
  await db.query("insert into storage.objects (bucket_id, name, owner) values ('service-photos', $1, $2)", [`${USERS.lina}/leak.jpg`, USERS.lina]);
  const r = await create(USERS.lina, valid({ category_id: "custom", custom_service: "Satellite dish fitting", photos: [`${USERS.lina}/leak.jpg`], lat: 31.94, lng: 35.88 }));
  const row = await db.query<{ custom_service: string; photos: string[]; lat: number }>("select custom_service, photos, lat from public.service_requests where id = $1", [r.id]);
  assert.deepEqual(row.rows[0], { custom_service: "Satellite dish fitting", photos: [`${USERS.lina}/leak.jpg`], lat: 31.94 });
  // A listed category drops a stray custom name.
  const listed = await create(USERS.lina, valid({ custom_service: "ignored" }));
  const plain = await db.query<{ custom_service: string | null }>("select custom_service from public.service_requests where id = $1", [listed.id]);
  assert.equal(plain.rows[0].custom_service, null);
});

test("create: signed out is refused", async () => {
  assert.match(String(await errorOf(create(null, valid()))), /permission denied|sign_in/);
});

test("the table itself is closed to the API, whoever asks", async () => {
  assert.match(String(await errorOf(asUser(db, USERS.lina, "select * from public.service_requests"))), /permission denied/);
  assert.match(String(await errorOf(asUser(db, USERS.lina, "select * from public.service_request_events"))), /permission denied/);
  assert.match(String(await errorOf(asUser(db, USERS.lina, "update public.service_requests set status = 'completed'"))), /permission denied/);
  assert.match(String(await errorOf(asUser(db, USERS.lina, "select public.admin_service_update(gen_random_uuid(), 'completed')"))), /permission denied/);
  assert.match(String(await errorOf(asUser(db, USERS.lina, "select public.admin_services_overview()"))), /permission denied/);
});

test("my requests: only one's own, with the public history only", async () => {
  const r = await create(USERS.omar, valid({ category_id: "electrical" }));
  await asService(db, "select public.admin_service_update($1, 'under_review', 'Checking which electrician is free', false)", [r.id]);
  await asService(db, "select public.admin_service_update($1, null, 'We will call you today to agree a time.', true)", [r.id]);
  const omars = await mine(USERS.omar);
  const owned = await db.query<{ id: string }>("select id from public.service_requests where user_id = $1", [USERS.omar]);
  assert.deepEqual(omars.map(x => x.id).sort(), owned.rows.map(x => x.id).sort(), "exactly the caller's own requests");
  const it = omars.find(x => x.id === r.id)!;
  assert.equal(it.status, "under_review");
  assert.equal(it.category_en, "Electrical");
  assert.equal(it.cancellable, true);
  const notes = (it.events as { kind: string; note: string | null }[]).map(e => `${e.kind}:${e.note ?? ""}`);
  assert.deepEqual(notes, ["created:", "status:", "note:We will call you today to agree a time."]);
  assert.ok(!JSON.stringify(it).includes("Checking which electrician"), "an internal note never reaches the customer");
  assert.ok(!("assigned_to" in it), "the assignment is not shown");
  const linas = await mine(USERS.lina);
  assert.ok(!linas.some(x => x.id === r.id), "another person's request is not listed");
});

test("admin update: status, a note for the customer, notification, assignment", async () => {
  const r = await create(USERS.lina, valid({ category_id: "ac" }));
  const out = await asService<{ x: { status: string } }>(db, "select public.admin_service_update($1, 'accepted', 'A technician will visit on Thursday.', true) as x", [r.id]);
  assert.equal(out.rows[0].x.status, "accepted");
  const n = await db.query<{ kind: string; data: { status: string; note: string; ref: string } }>(
    "select kind, data from public.notifications where user_id = $1 and service_request_id = $2", [USERS.lina, r.id]);
  assert.equal(n.rows.length, 1);
  assert.equal(n.rows[0].kind, "service_status");
  assert.equal(n.rows[0].data.status, "accepted");
  assert.equal(n.rows[0].data.note, "A technician will visit on Thursday.");
  assert.equal(n.rows[0].data.ref, r.ref);
  // Only an admin account can be assigned.
  assert.match(String(await errorOf(asService(db, "select public.admin_service_update($1, null, null, false, $2)", [r.id, USERS.omar]))), /invalid:assignee/);
  await asService(db, "select public.admin_service_update($1, null, null, false, $2)", [r.id, USERS.admin]);
  const a = await db.query<{ assigned_to: string }>("select assigned_to from public.service_requests where id = $1", [r.id]);
  assert.equal(a.rows[0].assigned_to, USERS.admin);
  assert.match(String(await errorOf(asService(db, "select public.admin_service_update($1, 'teleported')", [r.id]))), /invalid:status/);
});

test("cancel: before work begins only, and only one's own", async () => {
  const r = await create(USERS.lina, valid({ category_id: "painting" }));
  assert.match(String(await errorOf(asUser(db, USERS.omar, "select public.cancel_service_request($1)", [r.id]))), /not_found/);
  const c = await asUser<{ x: { status: string } }>(db, USERS.lina, "select public.cancel_service_request($1, 'Fixed it myself') as x", [r.id]);
  assert.equal(c.rows[0].x.status, "cancelled");
  const ev = await db.query<{ from_status: string; to_status: string; note: string }>("select from_status, to_status, note from public.service_request_events where request_id = $1 and kind = 'status'", [r.id]);
  assert.deepEqual(ev.rows, [{ from_status: "pending", to_status: "cancelled", note: "Fixed it myself" }]);
  assert.match(String(await errorOf(asUser(db, USERS.lina, "select public.cancel_service_request($1)", [r.id]))), /not_allowed/);

  const started = await create(USERS.lina, valid({ category_id: "carpentry" }));
  await asService(db, "select public.admin_service_update($1, 'in_progress')", [started.id]);
  assert.match(String(await errorOf(asUser(db, USERS.lina, "select public.cancel_service_request($1)", [started.id]))), /not_allowed/);
  const admins = await db.query<{ n: number }>("select count(*)::int as n from public.notifications where kind = 'service_cancelled' and user_id = $1", [USERS.admin]);
  assert.ok(admins.rows[0].n >= 1);
});

test("photos: people upload only into their own folder of the private bucket", async () => {
  const b = await db.query<{ public: boolean; file_size_limit: number }>("select public, file_size_limit from storage.buckets where id = 'service-photos'");
  assert.deepEqual(b.rows[0], { public: false, file_size_limit: 8388608 });
  assert.equal(await errorOf(asUser(db, USERS.omar, "insert into storage.objects (bucket_id, name) values ('service-photos', $1)", [`${USERS.omar}/x.jpg`])), null);
  assert.match(String(await errorOf(asUser(db, USERS.omar, "insert into storage.objects (bucket_id, name) values ('service-photos', $1)", [`${USERS.lina}/x.jpg`]))), /row-level security/);
  const seen = await asUser<{ name: string }>(db, USERS.omar, "select name from storage.objects where bucket_id = 'service-photos'");
  assert.ok(seen.rows.every(r => r.name.startsWith(USERS.omar)), "only one's own photos are visible");
});

test("a day's limit stops a flood", async () => {
  const someone = "44444444-4444-4444-8444-444444444444";
  await db.query("insert into auth.users (id) values ($1)", [someone]);
  for (let i = 0; i < 10; i++) await create(someone, valid());
  assert.match(String(await errorOf(create(someone, valid()))), /too_many/);
});

test("the admin panel's counts add up", async () => {
  const o = await asService<{ x: { total: number; byStatus: Record<string, number>; daily: unknown[]; categories: number } }>(db, "select public.admin_services_overview() as x");
  const x = o.rows[0].x;
  const sum = Object.values(x.byStatus).reduce((a, b) => a + b, 0);
  assert.equal(sum, x.total);
  assert.equal(x.daily.length, 30);
  assert.equal(x.categories, 14);
});
