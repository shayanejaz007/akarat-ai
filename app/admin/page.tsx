"use client";

/**
 * akarat.ai/admin — the admin panel.
 *
 * Signs in with the same Supabase session the website keeps (storage key
 * 'akarat.auth'), so an admin already signed in on the site lands straight
 * in. Every figure comes from /api/admin/*, which verifies the session and
 * the account's admin role server-side before reading anything; this page
 * holds no privileged key and decides nothing about access.
 */

import { useCallback, useEffect, useMemo, useRef, useState, type FormEvent, type ReactNode } from "react";
import { createClient, type Session, type SupabaseClient } from "@supabase/supabase-js";

// Same project and publishable key as the website (lib/supabase.js), which
// falls back to these literals when the env vars are absent.
const SUPABASE_URL = process.env.NEXT_PUBLIC_SUPABASE_URL || "https://ppqftdcdpshfokjqnuhq.supabase.co";
const SUPABASE_KEY =
  process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY ||
  process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY ||
  "sb_publishable_Xrp8dp25j0fk4-XNpbS5eQ_hXZnIfrH";

let client: SupabaseClient | null = null;
function supabase(): SupabaseClient {
  return (client ??= createClient(SUPABASE_URL, SUPABASE_KEY, {
    auth: { persistSession: true, autoRefreshToken: true, storageKey: "akarat.auth" },
  }));
}

/* ── Formatting ──────────────────────────────────────────────────────── */

const fmt = (n: number | null | undefined) => {
  const v = Number(n ?? 0);
  if (Math.abs(v) >= 1e6) return `${(v / 1e6).toFixed(v >= 1e7 ? 0 : 1)}M`;
  if (Math.abs(v) >= 1e4) return `${(v / 1e3).toFixed(v >= 1e5 ? 0 : 1)}K`;
  return v.toLocaleString("en-US");
};
const full = (n: number | null | undefined) => Number(n ?? 0).toLocaleString("en-US");
const jod = (n: number | null | undefined) => `${full(n)} JOD`;

function ago(iso: string | null | undefined): string {
  if (!iso) return "never";
  const s = Math.max(0, (Date.now() - new Date(iso).getTime()) / 1000);
  if (s < 90) return "just now";
  if (s < 3600) return `${Math.round(s / 60)} min ago`;
  if (s < 86400) return `${Math.round(s / 3600)} h ago`;
  if (s < 86400 * 30) return `${Math.round(s / 86400)} d ago`;
  return new Date(iso).toLocaleDateString("en-GB", { day: "numeric", month: "short", year: "numeric" });
}
const when = (iso: string | null | undefined) =>
  iso ? new Date(iso).toLocaleString("en-GB", { day: "numeric", month: "short", hour: "2-digit", minute: "2-digit" }) : "—";

const title = (r: { title_en?: string | null; title_ar?: string | null } | null | undefined) =>
  r?.title_en || r?.title_ar || "Untitled";

const listingUrl = (id: string) => `/en/property/${id}`;

/* ── API ─────────────────────────────────────────────────────────────── */

type Api = <T>(path: string, init?: { method?: string; body?: unknown }) => Promise<T>;

function useApi(session: Session | null): Api {
  return useCallback(
    async <T,>(path: string, init?: { method?: string; body?: unknown }): Promise<T> => {
      // Always the current token: supabase-js refreshes it in the background.
      const { data } = await supabase().auth.getSession();
      const token = data.session?.access_token ?? session?.access_token;
      const res = await fetch(path, {
        method: init?.method ?? "GET",
        headers: {
          Authorization: `Bearer ${token}`,
          ...(init?.body !== undefined ? { "Content-Type": "application/json" } : {}),
        },
        body: init?.body !== undefined ? JSON.stringify(init.body) : undefined,
        cache: "no-store",
      });
      const body = await res.json().catch(() => ({}));
      if (!res.ok) throw Object.assign(new Error(body.error || `Request failed (${res.status})`), { status: res.status });
      return body as T;
    },
    [session],
  );
}

/* ── Page ────────────────────────────────────────────────────────────── */

type Tab = "overview" | "listings" | "inquiries" | "users" | "reports";
const TABS: { id: Tab; label: string }[] = [
  { id: "overview", label: "Overview" },
  { id: "listings", label: "Listings" },
  { id: "inquiries", label: "Inquiries" },
  { id: "users", label: "Users" },
  { id: "reports", label: "Reports" },
];

export default function AdminPage() {
  const [session, setSession] = useState<Session | null>(null);
  const [ready, setReady] = useState(false);

  useEffect(() => {
    const sb = supabase();
    sb.auth.getSession().then(({ data }) => {
      setSession(data.session);
      setReady(true);
    });
    const { data } = sb.auth.onAuthStateChange((_e, s) => setSession(s));
    return () => data.subscription.unsubscribe();
  }, []);

  if (!ready) return <div className="adm adm-gate"><p className="adm-muted">Loading…</p></div>;
  if (!session) return <SignIn />;
  return <Panel session={session} />;
}

function SignIn() {
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState("");

  async function submit(e: FormEvent) {
    e.preventDefault();
    setBusy(true);
    setError("");
    const { error } = await supabase().auth.signInWithPassword({ email: email.trim(), password });
    setBusy(false);
    if (error) setError(error.message);
  }

  return (
    <div className="adm adm-gate">
      <form onSubmit={submit} className="adm-card">
        <div>
          <div className="adm-brand">Akarat.ai <span>admin</span></div>
          <p className="adm-sub" style={{ margin: "4px 0 0" }}>Sign in with an admin account.</p>
        </div>
        {error && <div className="adm-error" style={{ margin: 0 }}>{error}</div>}
        <input className="adm-input" type="email" autoComplete="email" placeholder="Email" value={email} onChange={e => setEmail(e.target.value)} required />
        <input className="adm-input" type="password" autoComplete="current-password" placeholder="Password" value={password} onChange={e => setPassword(e.target.value)} required />
        <button className="adm-btn primary" disabled={busy}>{busy ? "Signing in…" : "Sign in"}</button>
        <p className="adm-muted" style={{ margin: 0 }}>
          Signed in on akarat.ai with Google or a phone number? Open the site, sign in there, then come back to /admin.
        </p>
      </form>
    </div>
  );
}

type Overview = {
  live: { total: number; web: number; android: number; ios: number; signedIn: number };
  active: { today: number; week: number; month: number };
  users: { total: number; week: number; admins: number; owners: number };
  listings: { total: number; week: number; byStatus: Record<string, number> };
  inquiries: { total: number; today: number; week: number; new: number };
  views: { total: number; today: number; week: number };
  saves: number;
  openReports: number;
  daily: { day: string; views: number; inquiries: number; signups: number; listings: number; viewers: number }[];
  topViewed: { id: string; title_en: string; title_ar: string | null; status: string; n: number }[];
  topInquired: { id: string; title_en: string; title_ar: string | null; status: string; n: number }[];
  byCity: { city: string; n: number }[];
  generatedAt: string;
};

function Panel({ session }: { session: Session }) {
  const api = useApi(session);
  const [tab, setTab] = useState<Tab>(() => {
    if (typeof window === "undefined") return "overview";
    const h = window.location.hash.slice(1) as Tab;
    return TABS.some(t => t.id === h) ? h : "overview";
  });
  const [overview, setOverview] = useState<Overview | null>(null);
  const [error, setError] = useState<{ message: string; status?: number } | null>(null);
  const [inquiryFilter, setInquiryFilter] = useState<string | null>(null);

  const go = (t: Tab) => {
    setTab(t);
    history.replaceState(null, "", `#${t}`);
  };

  const loadOverview = useCallback(async () => {
    try {
      setOverview(await api<Overview>("/api/admin/overview"));
      setError(null);
    } catch (e) {
      setError({ message: (e as Error).message, status: (e as { status?: number }).status });
    }
  }, [api]);

  // Live: refreshed every 15 seconds while the tab is visible.
  useEffect(() => {
    loadOverview();
    const t = setInterval(() => {
      if (document.visibilityState === "visible") loadOverview();
    }, 15000);
    return () => clearInterval(t);
  }, [loadOverview]);

  const denied = error?.status === 401 || error?.status === 403;

  return (
    <div className="adm">
      <header className="adm-top">
        <div className="adm-brand">Akarat.ai <span>admin</span></div>
        <nav className="adm-tabs" role="tablist">
          {TABS.map(t => (
            <button key={t.id} role="tab" aria-selected={tab === t.id} className="adm-tab" onClick={() => go(t.id)}>
              {t.label}
              {t.id === "inquiries" && !!overview?.inquiries.new && <span className="adm-count">{overview.inquiries.new}</span>}
              {t.id === "reports" && !!overview?.openReports && <span className="adm-count">{overview.openReports}</span>}
            </button>
          ))}
        </nav>
        <div className="adm-me">
          <span>{session.user.email ?? session.user.phone}</span>
          <a href="/">Site</a>
          <button className="adm-btn" onClick={() => supabase().auth.signOut()}>Sign out</button>
        </div>
      </header>
      <main className="adm-main">
        {error && (
          <div className="adm-error">
            {error.message}
            {denied && " Ask an existing admin to give this account the admin role (see supabase/migrations/0018_admin_analytics.sql)."}
          </div>
        )}
        {!denied && tab === "overview" && <OverviewView data={overview} onOpen={go} />}
        {!denied && tab === "listings" && (
          <ListingsView api={api} onInquiries={id => { setInquiryFilter(id); go("inquiries"); }} />
        )}
        {!denied && tab === "inquiries" && (
          <InquiriesView api={api} property={inquiryFilter} clearProperty={() => setInquiryFilter(null)} onChange={loadOverview} />
        )}
        {!denied && tab === "users" && <UsersView api={api} me={session.user.id} />}
        {!denied && tab === "reports" && <ReportsView api={api} onChange={loadOverview} />}
      </main>
    </div>
  );
}

/* ── Overview ────────────────────────────────────────────────────────── */

const STATUS_LABEL: Record<string, string> = {
  active: "Active", draft: "Draft", pending: "Pending review", paused: "Paused", sold: "Sold",
  rented: "Rented", rejected: "Rejected", archived: "Archived",
};

function OverviewView({ data, onOpen }: { data: Overview | null; onOpen: (t: Tab) => void }) {
  if (!data) return <p className="adm-muted">Loading figures…</p>;
  const statuses = Object.entries(data.listings.byStatus).sort((a, b) => b[1] - a[1]);
  return (
    <>
      <h1 className="adm-h1">Overview</h1>
      <p className="adm-sub">Updated {ago(data.generatedAt)} · refreshes every 15 seconds · days are Amman time</p>

      <section className="adm-card adm-hero" aria-label="People on Akarat.ai right now">
        <div>
          <div className="adm-live"><span className="adm-dot" aria-hidden /> On Akarat.ai right now</div>
          <div className="adm-big">{full(data.live.total)}</div>
        </div>
        <div className="adm-split">
          <div><b>{full(data.live.web)}</b>Website</div>
          <div><b>{full(data.live.android)}</b>Android</div>
          <div><b>{full(data.live.ios)}</b>iPhone</div>
          <div><b>{full(data.live.signedIn)}</b>Signed in</div>
        </div>
        <div className="adm-split" style={{ marginLeft: "auto" }}>
          <div><b>{fmt(data.active.today)}</b>Active today</div>
          <div><b>{fmt(data.active.week)}</b>Last 7 days</div>
          <div><b>{fmt(data.active.month)}</b>Last 30 days</div>
        </div>
      </section>

      <div className="adm-grid tiles">
        <Tile label="Accounts" value={data.users.total} note={`+${full(data.users.week)} this week`} />
        <Tile label="Listings" value={data.listings.total} note={`+${full(data.listings.week)} this week`} onClick={() => onOpen("listings")} />
        <Tile label="Live listings" value={data.listings.byStatus.active ?? 0} note={`${full(data.users.owners)} owners`} />
        <Tile label="Inquiries" value={data.inquiries.total} note={`${full(data.inquiries.today)} today · ${full(data.inquiries.new)} unread`} onClick={() => onOpen("inquiries")} />
        <Tile label="Listing views" value={data.views.total} note={`${full(data.views.today)} today · ${full(data.views.week)} this week`} />
        <Tile label="Saved by users" value={data.saves} note="hearts across all listings" />
        <Tile label="Open reports" value={data.openReports} note={data.openReports ? "need a decision" : "nothing waiting"} onClick={() => onOpen("reports")} />
      </div>

      <div className="adm-grid three">
        <ChartCard title="Listing views" caption="Per day, last 30 days" data={data.daily} field="views" />
        <ChartCard title="Inquiries" caption="Per day, last 30 days" data={data.daily} field="inquiries" />
        <ChartCard title="New accounts" caption="Per day, last 30 days" data={data.daily} field="signups" />
      </div>

      <div className="adm-grid two">
        <RankCard title="Most viewed" caption="Views, last 30 days" rows={data.topViewed.map(r => ({ key: r.id, label: title(r), n: r.n, href: listingUrl(r.id), status: r.status }))} />
        <RankCard title="Most inquired" caption="Inquiries, last 30 days" rows={data.topInquired.map(r => ({ key: r.id, label: title(r), n: r.n, href: listingUrl(r.id), status: r.status }))} />
      </div>

      <div className="adm-grid two">
        <RankCard title="Listings by status" caption="All listings" rows={statuses.map(([s, n]) => ({ key: s, label: STATUS_LABEL[s] ?? s, n }))} />
        <RankCard title="Listings by city" caption="All listings" rows={data.byCity.map(c => ({ key: c.city, label: c.city, n: c.n }))} />
      </div>
    </>
  );
}

function Tile({ label, value, note, onClick }: { label: string; value: number; note?: string; onClick?: () => void }) {
  const body = (
    <>
      <div className="adm-label">{label}</div>
      <div className="adm-value">{fmt(value)}</div>
      {note && <div className="adm-note">{note}</div>}
    </>
  );
  return onClick ? (
    <button className="adm-card adm-tile" onClick={onClick} style={{ textAlign: "left", cursor: "pointer" }}>{body}</button>
  ) : (
    <div className="adm-card adm-tile">{body}</div>
  );
}

/** One series, one hue: columns per day, value on hover, the table one click
 *  away for exact numbers. No legend: the card's title names the series. */
function ChartCard({ title: heading, caption, data, field }: {
  title: string; caption: string; data: Overview["daily"]; field: "views" | "inquiries" | "signups";
}) {
  const [hover, setHover] = useState<number | null>(null);
  const W = 600, H = 170, padL = 34, padB = 22, padT = 8;
  const values = data.map(d => Number(d[field]) || 0);
  const max = niceMax(Math.max(1, ...values));
  const band = (W - padL) / Math.max(1, data.length);
  const barW = Math.min(14, band * 0.66);
  const y = (v: number) => padT + (H - padT - padB) * (1 - v / max);
  const total = values.reduce((a, b) => a + b, 0);
  const label = (iso: string) => new Date(`${iso}T12:00:00`).toLocaleDateString("en-GB", { day: "numeric", month: "short" });

  return (
    <section className="adm-card">
      <h2>{heading} <span className="adm-muted" style={{ fontWeight: 400 }}>· {full(total)} total</span></h2>
      <p className="adm-cap">{caption}</p>
      <div className="adm-chart" onMouseLeave={() => setHover(null)}>
        <svg viewBox={`0 0 ${W} ${H}`} role="img" aria-label={`${heading}, ${caption}: ${full(total)} in total`}>
          {[0, 0.5, 1].map(f => (
            <g key={f}>
              <line x1={padL} x2={W} y1={y(max * f)} y2={y(max * f)} stroke="var(--grid)" strokeWidth={1} />
              <text x={padL - 6} y={y(max * f) + 3} textAnchor="end" className="tick">{fmt(max * f)}</text>
            </g>
          ))}
          {values.map((v, i) => {
            const x = padL + band * i + (band - barW) / 2;
            const top = y(v), base = y(0), h = base - top, r = Math.min(4, h);
            return (
              <g key={data[i].day}>
                {v > 0 && (
                  <path
                    d={`M${x},${base} V${top + r} Q${x},${top} ${x + r},${top} H${x + barW - r} Q${x + barW},${top} ${x + barW},${top + r} V${base} Z`}
                    fill="var(--chart)"
                    opacity={hover === null || hover === i ? 1 : 0.45}
                  />
                )}
                {/* Hit target: the whole column, not just the bar. */}
                <rect x={padL + band * i} y={padT} width={band} height={H - padT - padB} fill="transparent" onMouseEnter={() => setHover(i)} />
              </g>
            );
          })}
          {[0, Math.floor((data.length - 1) / 2), data.length - 1].map(i =>
            data[i] ? (
              <text key={i} x={padL + band * i + band / 2} y={H - 6} textAnchor="middle" className="tick">{label(data[i].day)}</text>
            ) : null,
          )}
        </svg>
        {hover !== null && data[hover] && (
          <div className="adm-tip" style={{ left: `${((padL + band * hover + band / 2) / W) * 100}%`, top: `${(y(values[hover]) / H) * 100}%` }}>
            {label(data[hover].day)} · <b>{full(values[hover])}</b>
          </div>
        )}
      </div>
      <details className="adm-table-toggle">
        <summary>Show as table</summary>
        <table className="adm-table" style={{ marginTop: 8 }}>
          <tbody>
            {[...data].reverse().map(d => (
              <tr key={d.day}><td>{label(d.day)}</td><td className="num">{full(Number(d[field]))}</td></tr>
            ))}
          </tbody>
        </table>
      </details>
    </section>
  );
}

function niceMax(v: number): number {
  const p = Math.pow(10, Math.floor(Math.log10(v)));
  for (const m of [1, 2, 2.5, 5, 10]) if (m * p >= v) return Math.max(2, m * p);
  return v;
}

function RankCard({ title: heading, caption, rows }: {
  title: string; caption: string; rows: { key: string; label: string; n: number; href?: string; status?: string }[];
}) {
  const max = Math.max(1, ...rows.map(r => r.n));
  return (
    <section className="adm-card">
      <h2>{heading}</h2>
      <p className="adm-cap">{caption}</p>
      {rows.length === 0 ? (
        <div className="adm-empty">Nothing yet.</div>
      ) : (
        <div className="adm-bars">
          {rows.map(r => (
            <div className="adm-bar-row" key={r.key}>
              <div className="name" title={r.label}>
                {r.href ? <a href={r.href} target="_blank" rel="noreferrer">{r.label}</a> : r.label}
                {r.status && r.status !== "active" && <> <StatusPill status={r.status} /></>}
              </div>
              <div className="num">{full(r.n)}</div>
              <div className="adm-bar-track"><div className="adm-bar-fill" style={{ width: `${(r.n / max) * 100}%` }} /></div>
            </div>
          ))}
        </div>
      )}
    </section>
  );
}

function StatusPill({ status }: { status: string }) {
  const tone = status === "active" ? "good" : ["pending", "paused", "draft"].includes(status) ? "warn" : ["rejected"].includes(status) ? "bad" : "";
  return <span className={`adm-pill ${tone}`}>{STATUS_LABEL[status] ?? status}</span>;
}

/* ── Shared list plumbing ────────────────────────────────────────────── */

function useList<T>(api: Api, path: string, params: Record<string, string | number | null | undefined>) {
  const [rows, setRows] = useState<T[] | null>(null);
  const [total, setTotal] = useState(0);
  const [pageSize, setPageSize] = useState(50);
  const [error, setError] = useState("");
  const [extra, setExtra] = useState<Record<string, unknown>>({});
  const query = useMemo(() => {
    const u = new URLSearchParams();
    for (const [k, v] of Object.entries(params)) if (v !== null && v !== undefined && v !== "") u.set(k, String(v));
    return u.toString();
  }, [params]);
  const seq = useRef(0);

  const reload = useCallback(async () => {
    const n = ++seq.current;
    try {
      const body = await api<Record<string, unknown>>(`${path}?${query}`);
      if (n !== seq.current) return; // a newer search has started
      const key = Object.keys(body).find(k => Array.isArray(body[k]))!;
      setRows(body[key] as T[]);
      setTotal(Number(body.total) || 0);
      setPageSize(Number(body.pageSize) || 50);
      setExtra(body);
      setError("");
    } catch (e) {
      if (n === seq.current) setError((e as Error).message);
    }
  }, [api, path, query]);

  useEffect(() => { reload(); }, [reload]);
  return { rows, total, pageSize, error, reload, extra };
}

function useDebounced(value: string, ms = 300) {
  const [v, setV] = useState(value);
  useEffect(() => {
    const t = setTimeout(() => setV(value), ms);
    return () => clearTimeout(t);
  }, [value, ms]);
  return v;
}

function Pager({ page, setPage, total, pageSize }: { page: number; setPage: (p: number) => void; total: number; pageSize: number }) {
  const pages = Math.max(1, Math.ceil(total / pageSize));
  return (
    <div className="adm-pager">
      <span>{full(total)} total · page {page + 1} of {pages}</span>
      <button className="adm-btn" disabled={page === 0} onClick={() => setPage(page - 1)}>Previous</button>
      <button className="adm-btn" disabled={page + 1 >= pages} onClick={() => setPage(page + 1)}>Next</button>
    </div>
  );
}

function ListHeader({ heading, sub, children }: { heading: string; sub: string; children?: ReactNode }) {
  return (
    <>
      <h1 className="adm-h1">{heading}</h1>
      <p className="adm-sub">{sub}</p>
      <div className="adm-toolbar">{children}</div>
    </>
  );
}

/* ── Listings ────────────────────────────────────────────────────────── */

type ListingRow = {
  id: string; status: string; deal: string; property_type: string; city_id: string | null; price_jod: number;
  bedrooms: number | null; area_sqm: number | null; title_en: string; title_ar: string | null;
  views: number; saves: number; inquiries_count: number; featured: boolean; verified: boolean;
  created_at: string; cover: string | null; media: number; phone: string | null;
  views7d: number; views30d: number; lastInquiry: string | null;
  owner: { id: string; full_name: string | null; phone: string | null } | null;
};

function ListingsView({ api, onInquiries }: { api: Api; onInquiries: (id: string) => void }) {
  const [q, setQ] = useState("");
  const [status, setStatus] = useState("");
  const [sort, setSort] = useState("created");
  const [page, setPage] = useState(0);
  const dq = useDebounced(q);
  const params = useMemo(() => ({ q: dq, status, sort, page }), [dq, status, sort, page]);
  const { rows, total, pageSize, error, reload } = useList<ListingRow>(api, "/api/admin/listings", params);
  const [busy, setBusy] = useState<string | null>(null);
  useEffect(() => setPage(0), [dq, status, sort]);

  async function change(id: string, body: Record<string, unknown>) {
    setBusy(id);
    try { await api("/api/admin/listings", { method: "PATCH", body: { id, ...body } }); await reload(); }
    catch (e) { alert((e as Error).message); }
    setBusy(null);
  }
  async function remove(r: ListingRow) {
    if (!confirm(`Delete "${title(r)}" for good? Its inquiries, views and reports go with it. To hide it instead, set it to Paused.`)) return;
    setBusy(r.id);
    try { await api(`/api/admin/listings?id=${r.id}`, { method: "DELETE" }); await reload(); }
    catch (e) { alert((e as Error).message); }
    setBusy(null);
  }

  return (
    <>
      <ListHeader heading="Listings" sub="Every listing on Akarat.ai, whatever its status or owner.">
        <input className="adm-input" placeholder="Search titles, or paste a listing id" value={q} onChange={e => setQ(e.target.value)} />
        <select className="adm-select" value={status} onChange={e => setStatus(e.target.value)} aria-label="Status">
          <option value="">All statuses</option>
          {Object.entries(STATUS_LABEL).map(([k, v]) => <option key={k} value={k}>{v}</option>)}
        </select>
        <select className="adm-select" value={sort} onChange={e => setSort(e.target.value)} aria-label="Sort">
          <option value="created">Newest</option>
          <option value="views">Most viewed</option>
          <option value="inquiries">Most inquired</option>
          <option value="saves">Most saved</option>
          <option value="price">Highest price</option>
        </select>
      </ListHeader>
      {error && <div className="adm-error">{error}</div>}
      {!rows ? <p className="adm-muted">Loading…</p> : (
        <div className="adm-tablewrap">
          <table className="adm-table">
            <thead>
              <tr>
                <th></th><th>Listing</th><th>Owner</th><th>Status</th>
                <th className="num">Price</th><th className="num">Views (7d / all)</th><th className="num">Inquiries</th><th className="num">Saves</th>
                <th>Actions</th>
              </tr>
            </thead>
            <tbody>
              {rows.map(r => (
                <tr key={r.id}>
                  <td>{r.cover ? <img className="adm-thumb" src={r.cover} alt="" loading="lazy" /> : <div className="adm-thumb" />}</td>
                  <td>
                    <div className="adm-title"><a href={listingUrl(r.id)} target="_blank" rel="noreferrer">{title(r)}</a></div>
                    {r.title_ar && r.title_ar !== r.title_en && <div className="adm-muted" dir="rtl">{r.title_ar}</div>}
                    <div className="adm-muted">
                      {r.deal === "rent" ? "Rent" : "Sale"} · {r.property_type}{r.city_id ? ` · ${r.city_id}` : ""}
                      {r.bedrooms ? ` · ${r.bedrooms} bd` : ""}{r.area_sqm ? ` · ${r.area_sqm} m²` : ""} · {r.media} media · listed {ago(r.created_at)}
                    </div>
                  </td>
                  <td>
                    <div>{r.owner?.full_name || "—"}</div>
                    <div className="adm-muted">{r.phone || r.owner?.phone || ""}</div>
                  </td>
                  <td>
                    <StatusPill status={r.status} />
                    {r.featured && <> <span className="adm-pill good">Featured</span></>}
                    {r.verified && <> <span className="adm-pill good">Verified</span></>}
                  </td>
                  <td className="num">{jod(r.price_jod)}{r.deal === "rent" ? <div className="adm-muted">/ month</div> : null}</td>
                  <td className="num">{full(r.views7d)} / {full(r.views)}</td>
                  <td className="num">
                    {r.inquiries_count ? <a href="#inquiries" onClick={e => { e.preventDefault(); onInquiries(r.id); }}>{full(r.inquiries_count)}</a> : 0}
                    {r.lastInquiry && <div className="adm-muted">{ago(r.lastInquiry)}</div>}
                  </td>
                  <td className="num">{full(r.saves)}</td>
                  <td>
                    <div className="adm-actions">
                      <select className="adm-select" style={{ minHeight: 32, padding: "4px 8px" }} value={r.status} disabled={busy === r.id}
                        onChange={e => change(r.id, { status: e.target.value })} aria-label="Change status">
                        {Object.entries(STATUS_LABEL).map(([k, v]) => <option key={k} value={k}>{v}</option>)}
                      </select>
                      <button className="adm-btn" disabled={busy === r.id} onClick={() => change(r.id, { featured: !r.featured })}>
                        {r.featured ? "Unfeature" : "Feature"}
                      </button>
                      <button className="adm-btn" disabled={busy === r.id} onClick={() => change(r.id, { verified: !r.verified })}>
                        {r.verified ? "Unverify" : "Verify"}
                      </button>
                      <button className="adm-btn danger" disabled={busy === r.id} onClick={() => remove(r)}>Delete</button>
                    </div>
                  </td>
                </tr>
              ))}
              {rows.length === 0 && <tr><td colSpan={9} className="adm-empty">No listings match.</td></tr>}
            </tbody>
          </table>
        </div>
      )}
      <Pager page={page} setPage={setPage} total={total} pageSize={pageSize} />
    </>
  );
}

/* ── Inquiries ───────────────────────────────────────────────────────── */

type InquiryRow = {
  id: string; property_id: string; sender_id: string | null; name: string; email: string | null; phone: string | null;
  message: string; status: string; created_at: string;
  properties: { title_en: string; title_ar: string | null; status: string } | null;
  owner: { full_name: string | null; phone: string | null } | null;
};

const INQUIRY_STATUS: Record<string, string> = { new: "New", read: "Read", replied: "Replied", closed: "Closed" };

function InquiriesView({ api, property, clearProperty, onChange }: {
  api: Api; property: string | null; clearProperty: () => void; onChange: () => void;
}) {
  const [q, setQ] = useState("");
  const [status, setStatus] = useState("");
  const [page, setPage] = useState(0);
  const dq = useDebounced(q);
  const params = useMemo(() => ({ q: dq, status, property, page }), [dq, status, property, page]);
  const { rows, total, pageSize, error, reload } = useList<InquiryRow>(api, "/api/admin/inquiries", params);
  useEffect(() => setPage(0), [dq, status, property]);

  async function set(id: string, s: string) {
    try { await api("/api/admin/inquiries", { method: "PATCH", body: { id, status: s } }); await reload(); onChange(); }
    catch (e) { alert((e as Error).message); }
  }
  const wa = (phone: string) => `https://wa.me/${phone.replace(/[^\d]/g, "").replace(/^0/, "962")}`;

  return (
    <>
      <ListHeader heading="Inquiries" sub="Every message sent to a listing owner, newest first.">
        <input className="adm-input" placeholder="Search name, email, phone or message" value={q} onChange={e => setQ(e.target.value)} />
        <select className="adm-select" value={status} onChange={e => setStatus(e.target.value)} aria-label="Status">
          <option value="">All</option>
          {Object.entries(INQUIRY_STATUS).map(([k, v]) => <option key={k} value={k}>{v}</option>)}
        </select>
        {property && <button className="adm-btn" onClick={clearProperty}>Showing one listing · show all</button>}
      </ListHeader>
      {error && <div className="adm-error">{error}</div>}
      {!rows ? <p className="adm-muted">Loading…</p> : (
        <div className="adm-tablewrap">
          <table className="adm-table">
            <thead><tr><th>Received</th><th>From</th><th>Message</th><th>Listing</th><th>Owner</th><th>Status</th></tr></thead>
            <tbody>
              {rows.map(r => (
                <tr key={r.id} style={r.status === "new" ? { background: "var(--accent-wash)" } : undefined}>
                  <td style={{ whiteSpace: "nowrap" }}>{when(r.created_at)}<div className="adm-muted">{ago(r.created_at)}</div></td>
                  <td>
                    <div>{r.name}</div>
                    {r.email && <div><a href={`mailto:${r.email}`}>{r.email}</a></div>}
                    {r.phone && <div><a href={`tel:${r.phone}`}>{r.phone}</a> · <a href={wa(r.phone)} target="_blank" rel="noreferrer">WhatsApp</a></div>}
                    <div className="adm-muted">{r.sender_id ? "Signed in" : "Guest"}</div>
                  </td>
                  <td><div className="adm-msg">{r.message}</div></td>
                  <td>
                    <a href={listingUrl(r.property_id)} target="_blank" rel="noreferrer">{title(r.properties)}</a>
                    {r.properties && r.properties.status !== "active" && <> <StatusPill status={r.properties.status} /></>}
                  </td>
                  <td>{r.owner?.full_name || "—"}<div className="adm-muted">{r.owner?.phone || ""}</div></td>
                  <td>
                    <select className="adm-select" style={{ minHeight: 32, padding: "4px 8px" }} value={r.status} onChange={e => set(r.id, e.target.value)} aria-label="Status">
                      {Object.entries(INQUIRY_STATUS).map(([k, v]) => <option key={k} value={k}>{v}</option>)}
                      {!INQUIRY_STATUS[r.status] && <option value={r.status}>{r.status}</option>}
                    </select>
                  </td>
                </tr>
              ))}
              {rows.length === 0 && <tr><td colSpan={6} className="adm-empty">No inquiries match.</td></tr>}
            </tbody>
          </table>
        </div>
      )}
      <Pager page={page} setPage={setPage} total={total} pageSize={pageSize} />
    </>
  );
}

/* ── Users ───────────────────────────────────────────────────────────── */

type UserRow = {
  id: string; email: string | null; phone: string | null; name: string | null; role: string; verified: boolean;
  agency: string | null; providers: string[]; createdAt: string; lastSignIn: string | null; lastSeen: string | null;
  lastPlatform: string | null; listings: { total: number; active: number };
};

const ROLES: Record<string, string> = { user: "User", property_owner: "Owner", agent: "Agent", admin: "Admin" };
const PLATFORM: Record<string, string> = { web: "website", android: "Android", ios: "iPhone" };

function UsersView({ api, me }: { api: Api; me: string }) {
  const [q, setQ] = useState("");
  const [role, setRole] = useState("");
  const [page, setPage] = useState(0);
  const dq = useDebounced(q);
  const params = useMemo(() => ({ q: dq, role, page }), [dq, role, page]);
  const { rows, total, pageSize, error, reload } = useList<UserRow>(api, "/api/admin/users", params);
  useEffect(() => setPage(0), [dq, role]);

  async function change(id: string, body: Record<string, unknown>) {
    if (body.role === "admin" && !confirm("Give this account full admin access, including this panel?")) return;
    try { await api("/api/admin/users", { method: "PATCH", body: { id, ...body } }); await reload(); }
    catch (e) { alert((e as Error).message); }
  }

  return (
    <>
      <ListHeader heading="Users" sub="Every account, how it signs in, and when it was last seen on the website or the app.">
        <input className="adm-input" placeholder="Search name, email, phone or agency" value={q} onChange={e => setQ(e.target.value)} />
        <select className="adm-select" value={role} onChange={e => setRole(e.target.value)} aria-label="Role">
          <option value="">All roles</option>
          {Object.entries(ROLES).map(([k, v]) => <option key={k} value={k}>{v}</option>)}
        </select>
      </ListHeader>
      {error && <div className="adm-error">{error}</div>}
      {!rows ? <p className="adm-muted">Loading…</p> : (
        <div className="adm-tablewrap">
          <table className="adm-table">
            <thead><tr><th>Account</th><th>Signs in with</th><th className="num">Listings</th><th>Joined</th><th>Last seen</th><th>Role</th><th></th></tr></thead>
            <tbody>
              {rows.map(u => {
                const online = u.lastSeen && Date.now() - new Date(u.lastSeen).getTime() < 120000;
                return (
                  <tr key={u.id}>
                    <td>
                      <div>{u.name || "—"} {u.verified && <span className="adm-pill good">Verified</span>}</div>
                      {u.email && <div><a href={`mailto:${u.email}`}>{u.email}</a></div>}
                      {u.phone && <div className="adm-muted">{u.phone}</div>}
                      {u.agency && <div className="adm-muted">{u.agency}</div>}
                    </td>
                    <td className="adm-muted">{u.providers.join(", ") || "—"}</td>
                    <td className="num">{full(u.listings.total)}<div className="adm-muted">{full(u.listings.active)} live</div></td>
                    <td style={{ whiteSpace: "nowrap" }}>{ago(u.createdAt)}</td>
                    <td style={{ whiteSpace: "nowrap" }}>
                      {online ? <span className="adm-pill good">Online now</span> : ago(u.lastSeen ?? u.lastSignIn)}
                      {u.lastPlatform && <div className="adm-muted">on {PLATFORM[u.lastPlatform] ?? u.lastPlatform}</div>}
                    </td>
                    <td>
                      <select className="adm-select" style={{ minHeight: 32, padding: "4px 8px" }} value={u.role} disabled={u.id === me}
                        onChange={e => change(u.id, { role: e.target.value })} aria-label="Role">
                        {Object.entries(ROLES).map(([k, v]) => <option key={k} value={k}>{v}</option>)}
                      </select>
                    </td>
                    <td>
                      <button className="adm-btn" onClick={() => change(u.id, { verified: !u.verified })}>{u.verified ? "Unverify" : "Verify"}</button>
                    </td>
                  </tr>
                );
              })}
              {rows.length === 0 && <tr><td colSpan={7} className="adm-empty">No accounts match.</td></tr>}
            </tbody>
          </table>
        </div>
      )}
      <Pager page={page} setPage={setPage} total={total} pageSize={pageSize} />
    </>
  );
}

/* ── Reports ─────────────────────────────────────────────────────────── */

type ReportRow = {
  id: string; property_id: string; reason: string; details: string | null; status: string; created_at: string;
  properties: { title_en: string; title_ar: string | null; status: string } | null;
};

const REASON: Record<string, string> = {
  scam: "Scam or fraud", wrong_details: "Wrong details", unavailable: "No longer available", offensive: "Offensive", other: "Other",
};

function ReportsView({ api, onChange }: { api: Api; onChange: () => void }) {
  const [status, setStatus] = useState("open");
  const [page, setPage] = useState(0);
  const params = useMemo(() => ({ status, page }), [status, page]);
  const { rows, total, pageSize, error, reload, extra } = useList<ReportRow>(api, "/api/admin/reports", params);
  useEffect(() => setPage(0), [status]);

  async function act(id: string, s: string) {
    if (s === "removed" && !confirm("Take this listing off the site? It is paused, not deleted: the owner keeps it.")) return;
    try { await api("/api/admin/reports", { method: "PATCH", body: { id, status: s } }); await reload(); onChange(); }
    catch (e) { alert((e as Error).message); }
  }

  return (
    <>
      <ListHeader heading="Reports" sub="Listings people reported from the app. The app stores expect these handled within a day.">
        <select className="adm-select" value={status} onChange={e => setStatus(e.target.value)} aria-label="Status">
          <option value="open">Open</option><option value="reviewed">Reviewed</option>
          <option value="removed">Removed</option><option value="dismissed">Dismissed</option><option value="">All</option>
        </select>
      </ListHeader>
      {error && <div className="adm-error">{error}</div>}
      {extra.notSetUp ? (
        <div className="adm-note-box">Reports are not set up yet: run supabase/migrations/0015_listing_reports.sql.</div>
      ) : !rows ? <p className="adm-muted">Loading…</p> : (
        <div className="adm-tablewrap">
          <table className="adm-table">
            <thead><tr><th>Reported</th><th>Listing</th><th>Reason</th><th>Details</th><th>Status</th><th>Decision</th></tr></thead>
            <tbody>
              {rows.map(r => (
                <tr key={r.id}>
                  <td style={{ whiteSpace: "nowrap" }}>{when(r.created_at)}<div className="adm-muted">{ago(r.created_at)}</div></td>
                  <td>
                    <a href={listingUrl(r.property_id)} target="_blank" rel="noreferrer">{title(r.properties)}</a>
                    {r.properties && <> <StatusPill status={r.properties.status} /></>}
                  </td>
                  <td>{REASON[r.reason] ?? r.reason}</td>
                  <td><div className="adm-msg">{r.details || <span className="adm-muted">—</span>}</div></td>
                  <td><span className={`adm-pill ${r.status === "open" ? "bad" : ""}`}>{r.status}</span></td>
                  <td>
                    <div className="adm-actions">
                      <button className="adm-btn danger" onClick={() => act(r.id, "removed")}>Take listing down</button>
                      <button className="adm-btn" onClick={() => act(r.id, "reviewed")}>Reviewed</button>
                      <button className="adm-btn" onClick={() => act(r.id, "dismissed")}>Dismiss</button>
                    </div>
                  </td>
                </tr>
              ))}
              {rows.length === 0 && <tr><td colSpan={6} className="adm-empty">Nothing here.</td></tr>}
            </tbody>
          </table>
        </div>
      )}
      <Pager page={page} setPage={setPage} total={total} pageSize={pageSize} />
    </>
  );
}
