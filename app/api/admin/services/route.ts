import { NextResponse, type NextRequest } from "next/server";
import { fail, isUuid, paging, people, requireAdmin, searchTerm } from "@/lib/admin";

/**
 * /api/admin/services — service requests (0024_services.sql).
 *
 *   GET   ?status=&category=&governorate=&city=&urgency=&from=&to=&q=&page=
 *         The list, newest first (the open queue oldest first). `q` matches
 *         the reference (SR-000123) or the customer's name, phone or email.
 *   GET   ?id=   One request in full: the customer, the photos (signed for
 *         an hour), the whole history including internal notes.
 *   GET   ?staff=1   Who requests can be assigned to.
 *   PATCH { id, status?, note?, notePublic?, assignee?, unassign? }
 *         Through admin_service_update(): the change, the history and the
 *         customer's notification in one transaction.
 *
 * Only behind the admin session; the customer's contact details never leave
 * this route except to the panel.
 */

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

const PAGE = 30;
const STATUSES = ["pending", "under_review", "accepted", "in_progress", "completed", "rejected", "cancelled"];
const OPEN = ["pending", "under_review", "accepted", "in_progress"];
const URGENCY = ["normal", "urgent", "emergency"];
const LIST_COLUMNS =
  "id,ref,status,category_id,custom_service,description,governorate_id,city_id,neighborhood_id,address," +
  "preferred_date,preferred_window,urgency,photos,contact_name,contact_phone,contact_email,assigned_to," +
  "lang,platform,created_at,updated_at,status_at,user_id";
const isDay = (v: string | null): v is string => !!v && /^\d{4}-\d{2}-\d{2}$/.test(v);
const missing = (code?: string) => code === "42P01" || code === "PGRST205" || code === "42883" || code === "PGRST202";
const SETUP = "Run supabase/migrations/0024_services.sql first.";

export async function GET(request: NextRequest) {
  const admin = await requireAdmin(request);
  if (admin instanceof NextResponse) return admin;
  const url = new URL(request.url);

  const id = url.searchParams.get("id");
  if (id) return detail(admin.db, id);
  if (url.searchParams.get("staff") === "1") return staff(admin.db);

  const { from, to } = paging(url, PAGE);
  let query = admin.db.from("service_requests").select(LIST_COLUMNS, { count: "exact" });
  const status = url.searchParams.get("status");
  if (status === "open") query = query.in("status", OPEN);
  else if (status && STATUSES.includes(status)) query = query.eq("status", status);
  const category = url.searchParams.get("category");
  if (category && /^[a-z0-9_-]{1,40}$/.test(category)) query = query.eq("category_id", category);
  const governorate = url.searchParams.get("governorate");
  if (governorate && /^[a-z0-9-]{1,40}$/.test(governorate)) query = query.eq("governorate_id", governorate);
  const city = url.searchParams.get("city");
  if (city && /^[a-z0-9-]{1,40}$/.test(city)) query = query.eq("city_id", city);
  const urgency = url.searchParams.get("urgency");
  // "high": urgent or emergency, what the overview counts as urgent.
  if (urgency === "high") query = query.in("urgency", ["urgent", "emergency"]);
  else if (urgency && URGENCY.includes(urgency)) query = query.eq("urgency", urgency);
  const fromDay = url.searchParams.get("from");
  if (isDay(fromDay)) query = query.gte("created_at", `${fromDay}T00:00:00+03:00`);
  const toDay = url.searchParams.get("to");
  if (isDay(toDay)) query = query.lte("created_at", `${toDay}T23:59:59.999+03:00`);
  const q = searchTerm(url);
  if (q) {
    query = /^sr-?\d+$/i.test(q)
      ? query.ilike("ref", `%${q.replace(/^sr-?/i, "")}%`)
      : query.or(`ref.ilike.*${q}*,contact_name.ilike.*${q}*,contact_phone.ilike.*${q}*,contact_email.ilike.*${q}*`);
  }
  // The open queue is first come, first served; everything else newest first.
  query = status === "open" || status === "pending"
    ? query.order("created_at", { ascending: true })
    : query.order("created_at", { ascending: false });

  const { data, error, count } = await query.range(from, to);
  if (error) return fail(missing(error.code) ? SETUP : error.message, missing(error.code) ? 501 : 500);
  const rows = (data ?? []) as unknown as Record<string, unknown>[];
  const assignees = await people(admin.db, rows.map(r => r.assigned_to as string | null));
  const requests = rows.map(({ assigned_to, user_id, ...r }) => ({
    ...r,
    photoCount: Array.isArray(r.photos) ? r.photos.length : 0,
    photos: undefined,
    assignee: assigned_to ? { id: assigned_to, name: assignees.get(assigned_to as string)?.name ?? null } : null,
    signedIn: !!user_id,
  }));
  return NextResponse.json({ requests, total: count ?? requests.length, pageSize: PAGE });
}

/** Who a request can be assigned to: accounts whose profile has the admin
 *  role (admin_service_update() checks the same). */
async function staff(db: import("@supabase/supabase-js").SupabaseClient) {
  const { data, error } = await db.from("profiles").select("id").eq("role", "admin").limit(100);
  if (error) return fail(error.message);
  const who = await people(db, ((data ?? []) as { id: string }[]).map(r => r.id));
  return NextResponse.json({ staff: [...who.values()].map(p => ({ id: p.id, name: p.name, email: p.email })) });
}

async function detail(db: import("@supabase/supabase-js").SupabaseClient, id: string) {
  if (!isUuid(id)) return fail("id required", 400);
  const { data: row, error } = await db.from("service_requests").select("*").eq("id", id).maybeSingle();
  if (error) return fail(missing(error.code) ? SETUP : error.message, missing(error.code) ? 501 : 500);
  if (!row) return fail("No such request.", 404);

  const [events, who, photos, category] = await Promise.all([
    db.from("service_request_events").select("id,at,kind,from_status,to_status,note,public,actor").eq("request_id", id).order("at").order("id"),
    people(db, [row.user_id, row.assigned_to]),
    (row.photos as string[]).length
      ? db.storage.from("service-photos").createSignedUrls(row.photos as string[], 3600)
      : Promise.resolve({ data: [] as { path: string | null; signedUrl: string }[] }),
    db.from("service_categories").select("id,name_en,name_ar,icon,custom").eq("id", row.category_id).maybeSingle(),
  ]);
  return NextResponse.json({
    request: {
      ...row,
      category: category.data ?? null,
      customer: who.get(row.user_id) ?? null,
      assignee: row.assigned_to ? who.get(row.assigned_to) ?? { id: row.assigned_to } : null,
      photoUrls: ((photos.data ?? []) as { path: string | null; signedUrl: string }[]).filter(p => p.signedUrl).map(p => ({ path: p.path, url: p.signedUrl })),
      events: events.data ?? [],
    },
  });
}

export async function PATCH(request: NextRequest) {
  const admin = await requireAdmin(request);
  if (admin instanceof NextResponse) return admin;
  const b = (await request.json().catch(() => ({}))) as Record<string, unknown>;
  if (!isUuid(b.id)) return fail("id required", 400);
  if (b.status !== undefined && (typeof b.status !== "string" || !STATUSES.includes(b.status))) return fail("Unknown status", 400);
  if (b.note !== undefined && (typeof b.note !== "string" || b.note.length > 1000)) return fail("A note is at most 1,000 characters.", 400);
  if (b.assignee !== undefined && b.assignee !== null && !isUuid(b.assignee)) return fail("Unknown assignee", 400);
  if (b.status === "rejected" && !(b.notePublic === true && typeof b.note === "string" && b.note.trim())) {
    return fail("Say why, so the customer knows.", 400);
  }

  const { data, error } = await admin.db.rpc("admin_service_update", {
    p_id: b.id,
    p_status: typeof b.status === "string" ? b.status : null,
    p_note: typeof b.note === "string" ? b.note : null,
    p_note_public: b.notePublic === true,
    p_assignee: typeof b.assignee === "string" ? b.assignee : null,
    p_unassign: b.unassign === true,
  });
  if (error) {
    if (missing(error.code)) return fail(SETUP, 501);
    if (/not_found/.test(error.message)) return fail("No such request.", 404);
    if (/invalid:assignee/.test(error.message)) return fail("Only an account with the admin role can be assigned.", 400);
    return fail(error.message);
  }
  return NextResponse.json({ ok: true, request: data });
}
