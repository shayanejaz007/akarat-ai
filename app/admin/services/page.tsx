"use client";

import Link from "next/link";
import { useCallback, useEffect, useState } from "react";
import { ALL_CITIES, ALL_NEIGHBORHOODS, GOVERNORATES } from "../../../lib/reference";
import { useAdmin } from "../_components/context";
import { CopyButton, useFeedback } from "../_components/feedback";
import { Icon } from "../_components/icons";
import {
  Badge, Button, Callout, Card, Chips, Drawer, Empty, Figure, KV, LoadError, PageHeader, Pager, SearchInput, Section, Select,
  Skeleton, SkeletonRows, StatusBadge, TableScroll, Toolbar, cx,
} from "../_components/ui";
import { ApiError, qs, useList, useQuery, useSearchText } from "../_lib/api";
import { ago, dayLong, full, humanize, when, whatsapp } from "../_lib/format";
import { PLATFORM, SERVICE_NEXT, SERVICE_STATUS, TIME_WINDOW, URGENCY, labelOf } from "../_lib/labels";
import type { ServiceCategory, ServiceDetail, ServiceEvent, ServiceRow } from "../_lib/types";

/*
 * Service requests (GET/PATCH /api/admin/services, 0024_services.sql): what
 * customers asked for, where and when, and what the team has done about it.
 * Every change goes through admin_service_update(), which records it in the
 * request's history and tells the customer when it is meant for them. No
 * price, contractor or promise reaches the customer unless an admin writes
 * it in a note for them.
 */

const DEFAULTS = { status: "open", q: "", category: "", governorate: "", urgency: "", from: "", to: "", page: "0" };

const nameOf = (list: { id: string; en: string }[], id: string | null | undefined) =>
  id ? list.find(p => p.id === id)?.en ?? humanize(id) : null;
const placeOf = (r: { city_id: string; neighborhood_id: string | null; governorate_id: string }) =>
  [nameOf(ALL_NEIGHBORHOODS, r.neighborhood_id), nameOf(ALL_CITIES, r.city_id)].filter(Boolean).join(" · ") ||
  nameOf(GOVERNORATES, r.governorate_id) ||
  "—";

export default function ServicesPage() {
  const { api, overview, refreshOverview } = useAdmin();
  const [query, setQuery] = useQuery(DEFAULTS);
  const [text, setText] = useSearchText(query.q, q => setQuery({ q, page: "0" }));
  const page = Number(query.page) || 0;
  const list = useList<ServiceRow>(
    api,
    "/api/admin/services",
    "requests",
    qs({
      status: query.status === "all" ? "" : query.status, q: query.q, category: query.category, governorate: query.governorate,
      urgency: query.urgency, from: query.from, to: query.to, page,
    }),
  );
  const [categories, setCategories] = useState<ServiceCategory[]>([]);
  const [openId, setOpenId] = useState<string | null>(null);
  const s = overview?.services;
  const counts = s?.byStatus;
  const rows = list.rows;
  const filtered = !!(query.q || query.category || query.governorate || query.urgency || query.from || query.to);
  const notSetUp = list.error?.status === 501;

  useEffect(() => {
    api<{ categories: ServiceCategory[] }>("/api/admin/service-categories")
      .then(r => setCategories(r.categories))
      .catch(() => setCategories([]));
  }, [api]);

  // A link to one request (/admin/services?q=SR-000123) opens it.
  useEffect(() => {
    if (rows?.length === 1 && query.q && rows[0].ref.toLowerCase() === query.q.toLowerCase()) setOpenId(rows[0].id);
  }, [rows, query.q]);

  const catName = (id: string) => categories.find(c => c.id === id)?.name_en ?? humanize(id);
  const changed = useCallback(async () => {
    await list.reload();
    void refreshOverview();
  }, [list, refreshOverview]);

  return (
    <>
      <PageHeader
        title="Service requests"
        subtitle="Customers are told about status changes and the notes you write for them."
        actions={<Button icon="refresh" variant="ghost" onClick={() => void changed()} loading={list.loading && !!rows}>Refresh</Button>}
      />

      {s && (
        <div className="adm-figures is-4 adm-sv-figures">
          <Figure label="New" value={full(counts?.pending ?? 0)} sub={s.oldestPending ? `oldest ${ago(s.oldestPending)}` : "none waiting"} />
          <Figure label="Being handled" value={full((counts?.under_review ?? 0) + (counts?.accepted ?? 0) + (counts?.in_progress ?? 0))} sub="reviewed, accepted or in progress" />
          <Figure label="Urgent, open" value={full(s.urgentOpen)} sub="urgent or emergency" />
          <Figure label="Today" value={full(s.today)} sub={`${full(s.week)} this week`} />
        </div>
      )}

      <Chips
        label="Status"
        value={query.status}
        onChange={status => setQuery({ status, page: "0" })}
        options={[
          { value: "open", label: "Open", count: counts ? counts.pending + counts.under_review + counts.accepted + counts.in_progress : undefined },
          { value: "pending", label: "New", count: counts?.pending, urgent: true },
          { value: "under_review", label: "Under review", count: counts?.under_review },
          { value: "accepted", label: "Accepted", count: counts?.accepted },
          { value: "in_progress", label: "In progress", count: counts?.in_progress },
          { value: "completed", label: "Completed", count: counts?.completed },
          { value: "rejected", label: "Rejected", count: counts?.rejected },
          { value: "cancelled", label: "Cancelled", count: counts?.cancelled },
          { value: "all", label: "All", count: s?.total },
        ]}
      />
      <Toolbar>
        <SearchInput value={text} onChange={setText} placeholder="Reference (SR-000123), name, phone or email" label="Search service requests" />
        <Select
          small
          label="Category"
          value={query.category}
          onChange={category => setQuery({ category, page: "0" })}
          options={[{ value: "", label: "Every category" }, ...categories.map(c => ({ value: c.id, label: c.active ? c.name_en : `${c.name_en} (off)` }))]}
        />
        <Select
          small
          label="Governorate"
          value={query.governorate}
          onChange={governorate => setQuery({ governorate, page: "0" })}
          options={[{ value: "", label: "Every governorate" }, ...GOVERNORATES.map(g => ({ value: g.id, label: g.en }))]}
        />
        <Select
          small
          label="Urgency"
          value={query.urgency}
          onChange={urgency => setQuery({ urgency, page: "0" })}
          options={[
            { value: "", label: "Any urgency" },
            { value: "high", label: "Urgent or emergency" },
            ...Object.entries(URGENCY).map(([value, u]) => ({ value, label: u.label })),
          ]}
        />
        <label className="adm-date">
          <span>From</span>
          <input type="date" value={query.from} max={query.to || undefined} onChange={e => setQuery({ from: e.target.value, page: "0" })} />
        </label>
        <label className="adm-date">
          <span>To</span>
          <input type="date" value={query.to} min={query.from || undefined} onChange={e => setQuery({ to: e.target.value, page: "0" })} />
        </label>
        {filtered && (
          <Button size="sm" variant="ghost" icon="x" onClick={() => { setText(""); setQuery({ q: "", category: "", governorate: "", urgency: "", from: "", to: "", page: "0" }); }}>
            Clear filters
          </Button>
        )}
        {(query.status === "open" || query.status === "pending") && <span className="adm-toolbar-note"><Icon name="clock" size={14} /> Oldest first</span>}
      </Toolbar>

      {list.error && !notSetUp && <LoadError error={list.error} onRetry={() => void list.reload()} />}

      <Card flush>
        {notSetUp ? (
          <Empty
            icon="wrench"
            title="Not set up yet"
            body={<>Run <code>supabase/migrations/0023_locations.sql</code> and then <code>0024_services.sql</code> in Supabase → SQL Editor.</>}
          />
        ) : !rows ? (
          <SkeletonRows cols={6} />
        ) : rows.length === 0 ? (
          <Empty
            icon={query.status === "pending" || query.status === "open" ? "circleCheck" : "wrench"}
            title={filtered ? "No requests match" : query.status === "open" ? "Nothing open" : "Nothing here"}
            body={filtered ? "Try other filters." : query.status === "open" ? "New requests from the website and the app land here." : undefined}
          />
        ) : (
          <TableScroll label="Service requests" busy={list.loading}>
            <table className="adm-table">
              <thead>
                <tr>
                  <th scope="col">Request</th>
                  <th scope="col">Customer</th>
                  <th scope="col">Where</th>
                  <th scope="col">Preferred</th>
                  <th scope="col">Status</th>
                  <th scope="col">Received</th>
                </tr>
              </thead>
              <tbody>
                {rows.map(r => (
                  <tr key={r.id} className={cx("is-clickable", r.status === "pending" && "is-unread")} onClick={() => setOpenId(r.id)}>
                    <td>
                      <div className="adm-sv-cell">
                        <div className="adm-sv-cell-top">
                          <button type="button" className="adm-row-title" onClick={e => { e.stopPropagation(); setOpenId(r.id); }}>
                            {r.custom_service || catName(r.category_id)}
                          </button>
                          {r.urgency !== "normal" && <StatusBadge map={URGENCY} value={r.urgency} />}
                        </div>
                        <div className="adm-cell-sub adm-sv-desc" dir="auto">{r.description}</div>
                        <div className="adm-cell-sub">
                          <span className="adm-mono">{r.ref}</span>
                          {r.photoCount > 0 && <> · <Icon name="image" size={12} /> {r.photoCount}</>}
                          {r.assignee && <> · {r.assignee.name || "Assigned"}</>}
                        </div>
                      </div>
                    </td>
                    <td>
                      <div className="adm-cell-strong">{r.contact_name}</div>
                      <div className="adm-cell-sub" dir="ltr">{r.contact_phone}</div>
                    </td>
                    <td>
                      <div>{placeOf(r)}</div>
                      <div className="adm-cell-sub">{nameOf(GOVERNORATES, r.governorate_id)}</div>
                    </td>
                    <td className="adm-nowrap">
                      <div>{dayLong(r.preferred_date)}</div>
                      <div className="adm-cell-sub">{TIME_WINDOW[r.preferred_window] ?? r.preferred_window}</div>
                    </td>
                    <td><StatusBadge map={SERVICE_STATUS} value={r.status} /></td>
                    <td className="adm-nowrap" title={when(r.created_at)}>
                      {ago(r.created_at)}
                      <div className="adm-cell-sub">{PLATFORM[r.platform ?? ""] ?? "—"}</div>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </TableScroll>
        )}
        {rows && rows.length > 0 && <Pager page={page} pageSize={list.pageSize} total={list.total} onPage={p => setQuery({ page: String(p) })} />}
      </Card>

      <RequestDrawer id={openId} onClose={() => setOpenId(null)} onChanged={changed} catName={catName} />
    </>
  );
}

/* ── One request ──────────────────────────────────────────────────────── */

type Staff = { id: string; name: string | null; email: string | null };

function RequestDrawer({ id, onClose, onChanged, catName }: {
  id: string | null; onClose: () => void; onChanged: () => Promise<void>; catName: (id: string) => string;
}) {
  const { api } = useAdmin();
  const { toast, confirm } = useFeedback();
  const [r, setR] = useState<ServiceDetail | null>(null);
  const [error, setError] = useState<ApiError | null>(null);
  const [staff, setStaff] = useState<Staff[] | null>(null);
  const [busy, setBusy] = useState(false);
  const [next, setNext] = useState("");
  const [publicNote, setPublicNote] = useState("");
  const [internal, setInternal] = useState("");
  const [shown, setShown] = useState<number | null>(null);

  const load = useCallback(async (which: string) => {
    setError(null);
    try {
      const body = await api<{ request: ServiceDetail }>(`/api/admin/services?id=${which}`);
      setR(body.request);
    } catch (e) {
      setError(e instanceof ApiError ? e : new ApiError(String(e), 0));
    }
  }, [api]);

  useEffect(() => {
    setR(null);
    setNext("");
    setPublicNote("");
    setInternal("");
    setShown(null);
    if (id) void load(id);
  }, [id, load]);

  useEffect(() => {
    if (!id || staff) return;
    api<{ staff: Staff[] }>("/api/admin/services?staff=1").then(b => setStaff(b.staff)).catch(() => setStaff([]));
  }, [id, staff, api]);

  async function save(body: Record<string, unknown>, done: string) {
    if (!r) return false;
    setBusy(true);
    try {
      await api("/api/admin/services", { method: "PATCH", body: { id: r.id, ...body } });
      toast({ tone: "good", title: done, body: r.ref });
      await Promise.all([load(r.id), onChanged()]);
      return true;
    } catch (e) {
      toast({ tone: "bad", title: "Couldn't save", body: (e as Error).message });
      return false;
    } finally {
      setBusy(false);
    }
  }

  async function changeStatus() {
    if (!r || !next) return;
    const to = labelOf(SERVICE_STATUS, next).label;
    if (next === "rejected" && !publicNote.trim()) {
      toast({ tone: "bad", title: "Say why, for the customer", body: "A rejected request needs a note the customer will read." });
      return;
    }
    if (next === "rejected" || next === "completed") {
      const ok = await confirm({
        title: next === "rejected" ? "Reject this request?" : "Mark it completed?",
        body: next === "rejected"
          ? "The customer is told, with your note. It can be reopened later if this was a mistake."
          : "The customer is told the work is done.",
        confirm: next === "rejected" ? "Reject" : "Mark completed",
        danger: next === "rejected",
      });
      if (!ok) return;
    }
    const ok = await save({ status: next, note: publicNote.trim() || undefined, notePublic: !!publicNote.trim() }, `Now ${to.toLowerCase()}`);
    if (ok) {
      setNext("");
      setPublicNote("");
    }
  }

  const title = r ? `${r.ref} · ${r.custom_service || r.category?.name_en || catName(r.category_id)}` : id ? "Loading…" : "";
  const moves = r ? SERVICE_NEXT[r.status] ?? [] : [];
  const photo = r && shown !== null ? r.photoUrls[shown] : null;

  return (
    <Drawer
      open={!!id}
      onClose={onClose}
      title={title}
      subtitle={r ? <>Received {when(r.created_at)} · {PLATFORM[r.platform ?? ""] ?? "Unknown platform"} · written in {r.lang === "ar" ? "Arabic" : "English"}</> : undefined}
    >
      {error ? (
        <LoadError error={error} onRetry={() => id && void load(id)} />
      ) : !r ? (
        <div className="adm-sv-loading">
          <Skeleton h={22} w="60%" />
          <Skeleton h={80} />
          <Skeleton h={120} />
        </div>
      ) : (
        <>
          <div className="adm-badges">
            <StatusBadge map={SERVICE_STATUS} value={r.status} />
            <StatusBadge map={URGENCY} value={r.urgency} />
            {r.assignee ? <Badge icon="user">{r.assignee.name || r.assignee.email || "Assigned"}</Badge> : <Badge>Not assigned</Badge>}
          </div>

          <Section title="What they need">
            {r.custom_service && <div className="adm-cell-strong">{r.custom_service}</div>}
            <p className="adm-sv-text" dir="auto">{r.description}</p>
            <div className="adm-figures is-2">
              <Figure label="Preferred day" value={dayLong(r.preferred_date)} sub={TIME_WINDOW[r.preferred_window] ?? r.preferred_window} />
              <Figure label="Category" value={r.category?.name_en ?? catName(r.category_id)} sub={r.category?.name_ar} />
            </div>
          </Section>

          {r.photoUrls.length > 0 && (
            <Section title={`Photos (${r.photoUrls.length})`} aside={<span className="adm-cell-sub">Links last an hour</span>}>
              <div className="adm-sv-photos">
                {r.photoUrls.map((p, i) => (
                  <button key={p.url} type="button" className="adm-sv-photo" onClick={() => setShown(i)} aria-label={`Open photo ${i + 1}`}>
                    <img src={p.url} alt="" loading="lazy" />
                  </button>
                ))}
              </div>
              {photo && (
                <div className="adm-sv-photo-big">
                  <img src={photo.url} alt={`Photo ${(shown ?? 0) + 1} of ${r.photoUrls.length}`} />
                  <div className="adm-sv-photo-bar">
                    <a href={photo.url} target="_blank" rel="noreferrer">Open full size <Icon name="external" size={13} /></a>
                    <Button size="sm" variant="ghost" icon="x" onClick={() => setShown(null)}>Close</Button>
                  </div>
                </div>
              )}
            </Section>
          )}

          <Section title="Where">
            <KV
              items={[
                { k: "Area", v: placeOf(r) },
                { k: "Governorate", v: nameOf(GOVERNORATES, r.governorate_id) ?? "—" },
                { k: "Address", v: <span dir="auto">{r.address}</span> },
                {
                  k: "Map pin",
                  v: r.lat != null && r.lng != null ? (
                    <a href={`https://www.google.com/maps?q=${r.lat},${r.lng}`} target="_blank" rel="noreferrer">
                      <span dir="ltr">{r.lat.toFixed(5)}, {r.lng.toFixed(5)}</span> <Icon name="external" size={13} />
                    </a>
                  ) : "Not dropped",
                },
              ]}
            />
          </Section>

          <Section title="Customer">
            <KV
              items={[
                { k: "Name", v: r.contact_name },
                {
                  k: "Phone",
                  v: (
                    <span className="adm-sv-contact">
                      <a href={`tel:${r.contact_phone.replace(/[^\d+]/g, "")}`} dir="ltr">{r.contact_phone}</a>
                      <a href={whatsapp(r.contact_phone)} target="_blank" rel="noreferrer">WhatsApp</a>
                    </span>
                  ),
                },
                { k: "Email", v: r.contact_email ? <a href={`mailto:${encodeURIComponent(r.contact_email)}?subject=${encodeURIComponent(`Akarat.ai ${r.ref}`)}`}>{r.contact_email}</a> : "—" },
                { k: "Account", v: <Link href={`/admin/users?q=${r.user_id}`}>{r.customer?.name || r.customer?.email || "Open the account"}</Link> },
                { k: "Reference", v: <span className="adm-id">{r.ref}<CopyButton text={r.ref} label="Copy the reference" /></span> },
              ]}
            />
          </Section>

          {r.status === "cancelled" ? (
            <Callout tone="neutral" title="Cancelled by the customer">
              {r.cancel_reason ? <span dir="auto">“{r.cancel_reason}”</span> : "No reason given."}
            </Callout>
          ) : (
            <Section title="Change the status">
              <div className="adm-field-row">
                <span className="adm-field-label">Move to</span>
                <Select
                  label="New status"
                  value={next}
                  disabled={busy || moves.length === 0}
                  onChange={setNext}
                  options={[{ value: "", label: moves.length ? "Choose…" : "No further step" }, ...moves.map(m => ({ value: m, label: SERVICE_STATUS[m].label }))]}
                />
              </div>
              <label className="adm-field">
                <span className="adm-field-label">
                  Note for the customer <small>{next === "rejected" ? "(needed: why)" : "(optional; they will read it)"}</small>
                </span>
                <textarea
                  value={publicNote}
                  maxLength={1000}
                  onChange={e => setPublicNote(e.target.value)}
                  placeholder={next === "rejected" ? "For example: we don't cover Aqaba yet." : "For example: a technician will call you before 11."}
                  aria-invalid={next === "rejected" && !publicNote.trim() ? true : undefined}
                  dir="auto"
                />
                <span className="adm-field-hint">Don&apos;t promise a price, a technician or a finish date unless it has been agreed.</span>
              </label>
              <Button variant="primary" icon="check" disabled={!next} loading={busy && !!next} onClick={() => void changeStatus()}>
                {next ? `Move to ${SERVICE_STATUS[next].label.toLowerCase()}` : "Change status"}
              </Button>
            </Section>
          )}

          <Section title="Internal note">
            <label className="adm-field">
              <span className="adm-field-label">Only admins see this</span>
              <textarea value={internal} maxLength={1000} onChange={e => setInternal(e.target.value)} placeholder="Called them at 10:20, no answer." dir="auto" />
            </label>
            <Button
              icon="message"
              disabled={!internal.trim() || busy}
              onClick={() => void save({ note: internal.trim(), notePublic: false }, "Note added").then(ok => ok && setInternal(""))}
            >
              Add note
            </Button>
          </Section>

          <Section title="Assigned to">
            <div className="adm-field-row">
              <span className="adm-field-label">Admin</span>
              <Select
                label="Assign to"
                value={r.assigned_to ?? ""}
                disabled={busy || !staff}
                onChange={v => void (v ? save({ assignee: v }, "Assigned") : save({ unassign: true }, "Unassigned"))}
                options={[
                  { value: "", label: staff ? "Nobody" : "Loading…" },
                  ...(staff ?? []).map(p => ({ value: p.id, label: p.name || p.email || p.id.slice(0, 8) })),
                  ...(r.assigned_to && staff && !staff.some(p => p.id === r.assigned_to) ? [{ value: r.assigned_to, label: "A former admin" }] : []),
                ]}
              />
            </div>
            {staff && staff.length === 0 && (
              <p className="adm-hint">No account has the admin role yet. Give one in <Link href="/admin/users?role=admin">Users</Link> to assign requests to it.</p>
            )}
            <p className="adm-hint">For the team only: the customer never sees who is assigned.</p>
          </Section>

          <Section title="History">
            <Timeline events={r.events} />
          </Section>
        </>
      )}
    </Drawer>
  );
}

function eventText(e: ServiceEvent): string {
  if (e.kind === "created") return "Request sent";
  if (e.kind === "status") {
    if (e.to_status === "cancelled") return "Cancelled by the customer";
    return `${labelOf(SERVICE_STATUS, e.from_status ?? "").label} → ${labelOf(SERVICE_STATUS, e.to_status ?? "").label}`;
  }
  if (e.kind === "assigned") return e.note ? `Assigned to ${e.note}` : e.note === "" ? "Assigned" : "Unassigned";
  return e.public ? "Note to the customer" : "Internal note";
}

function Timeline({ events }: { events: ServiceEvent[] }) {
  if (!events.length) return <p className="adm-hint">Nothing yet.</p>;
  return (
    <ol className="adm-timeline">
      {[...events].reverse().map(e => (
        <li key={e.id} className={cx(`is-${e.kind}`, !e.public && "is-internal")}>
          <span className="adm-timeline-dot" aria-hidden="true" />
          <div>
            <div className="adm-timeline-head">
              <b>{eventText(e)}</b>
              {e.kind !== "assigned" && !e.public && <Badge>Internal</Badge>}
              {e.kind === "status" && e.public && e.to_status !== "cancelled" && <Badge tone="info">Customer told</Badge>}
            </div>
            {e.note && e.kind !== "assigned" && <p dir="auto">{e.note}</p>}
            <div className="adm-cell-sub">{when(e.at)} · {e.actor === "customer" ? "the customer" : e.actor === "system" ? "automatic" : "admin"}</div>
          </div>
        </li>
      ))}
    </ol>
  );
}
