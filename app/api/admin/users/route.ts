import { NextResponse, type NextRequest } from "next/server";
import { fail, isUuid, requireAdmin } from "@/lib/admin";

/**
 * /api/admin/users — every account: who they are, how they sign in, what
 * they have listed and when they were last seen.
 *
 *   GET    ?q=&role=&page=
 *   PATCH  { id, role?, verified? }
 *
 * Email addresses live in auth.users, which only the Auth admin API reads,
 * so accounts are fetched there and joined to profiles here. Filtering and
 * sorting happen in memory: fine for thousands of accounts. Past that, this
 * wants a security-definer view instead.
 */

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

const ROLES = ["user", "property_owner", "agent", "admin"];
const PAGE = 50;

export async function GET(request: NextRequest) {
  const admin = await requireAdmin(request);
  if (admin instanceof NextResponse) return admin;
  const url = new URL(request.url);
  const page = Math.max(0, Number(url.searchParams.get("page")) || 0);
  const q = (url.searchParams.get("q") ?? "").trim().toLowerCase();
  const role = url.searchParams.get("role");

  // All accounts, 1000 at a time.
  const accounts = [];
  for (let p = 1; p <= 20; p++) {
    const { data, error } = await admin.db.auth.admin.listUsers({ page: p, perPage: 1000 });
    if (error) return fail(error.message);
    accounts.push(...data.users);
    if (data.users.length < 1000) break;
  }

  const ids = accounts.map(a => a.id);
  const [profiles, listings, seen] = await Promise.all([
    admin.db.from("profiles").select("id,full_name,phone,role,verified,agency,locale,created_at"),
    admin.db.from("properties").select("owner_id,status"),
    ids.length ? admin.db.rpc("admin_last_seen", { p_ids: ids }) : Promise.resolve({ data: [] }),
  ]);
  const profileBy = new Map((profiles.data ?? []).map(p => [p.id, p]));
  const listingCount = new Map<string, { total: number; active: number }>();
  for (const l of listings.data ?? []) {
    const c = listingCount.get(l.owner_id) ?? { total: 0, active: 0 };
    c.total++;
    if (l.status === "active") c.active++;
    listingCount.set(l.owner_id, c);
  }
  const seenBy = new Map(((seen.data ?? []) as Record<string, unknown>[]).map(s => [s.user_id, s]));

  let users = accounts.map(a => {
    const p = profileBy.get(a.id);
    const s = seenBy.get(a.id);
    return {
      id: a.id,
      email: a.email ?? null,
      phone: a.phone || p?.phone || null,
      name: p?.full_name || (a.user_metadata?.full_name as string | undefined) || null,
      role: p?.role ?? "user",
      verified: !!p?.verified,
      agency: p?.agency ?? null,
      providers: (a.identities ?? []).map(i => i.provider),
      createdAt: a.created_at,
      lastSignIn: a.last_sign_in_at ?? null,
      lastSeen: (s?.last_seen as string | undefined) ?? null,
      lastPlatform: (s?.platform as string | undefined) ?? null,
      listings: listingCount.get(a.id) ?? { total: 0, active: 0 },
    };
  });

  if (role && ROLES.includes(role)) users = users.filter(u => u.role === role);
  if (q) {
    users = users.filter(u =>
      [u.email, u.phone, u.name, u.agency, u.id].some(v => v && String(v).toLowerCase().includes(q)),
    );
  }
  users.sort((a, b) => String(b.createdAt).localeCompare(String(a.createdAt)));

  return NextResponse.json({
    users: users.slice(page * PAGE, page * PAGE + PAGE),
    total: users.length,
    pageSize: PAGE,
  });
}

export async function PATCH(request: NextRequest) {
  const admin = await requireAdmin(request);
  if (admin instanceof NextResponse) return admin;
  const b = (await request.json().catch(() => ({}))) as Record<string, unknown>;
  if (!isUuid(b.id)) return fail("id required", 400);

  const changes: Record<string, unknown> = {};
  if (typeof b.role === "string") {
    if (!ROLES.includes(b.role)) return fail("Unknown role", 400);
    // An admin removing their own role would lock themselves out mid-session.
    if (b.id === admin.user.id && b.role !== "admin") return fail("You cannot remove your own admin role.", 400);
    changes.role = b.role;
  }
  if (typeof b.verified === "boolean") changes.verified = b.verified;
  if (!Object.keys(changes).length) return fail("Nothing to change", 400);

  const { error } = await admin.db.from("profiles").update(changes).eq("id", b.id);
  if (error) return fail(error.message);
  return NextResponse.json({ ok: true });
}
