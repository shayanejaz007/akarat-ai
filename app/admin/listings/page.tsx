"use client";

import Link from "next/link";
import { useEffect, useState } from "react";
import { useAdmin } from "../_components/context";
import { CopyButton, useFeedback } from "../_components/feedback";
import { Icon } from "../_components/icons";
import {
  Badge, ButtonLink, Button, Card, Chips, Drawer, Empty, Figure, KV, LoadError, Menu, MenuItem, MenuSep, PageHeader, Pager,
  SearchInput, Section, Select, SkeletonRows, StatusBadge, Switch, TableScroll, Thumb, Toolbar,
} from "../_components/ui";
import { qs, useList, useQuery, useSearchText } from "../_lib/api";
import { ago, compact, full, humanize, jod, titleOf, when, whatsapp } from "../_lib/format";
import { DEAL, LISTING_STATUS, ROLES, labelOf } from "../_lib/labels";
import type { ListingRow } from "../_lib/types";
import { QUALITY_PARTS } from "@/lib/listing-score.js";

/* Every listing on Akarat.ai, whatever its status or owner
   (GET/PATCH/DELETE /api/admin/listings). */

const DEFAULTS = { q: "", status: "", sort: "created", page: "0", owner: "" };
const STATUSES = ["active", "pending", "draft", "paused", "sold", "rented", "rejected", "archived"];
const SORTS = [
  { value: "created", label: "Newest first" },
  { value: "score", label: "Best score" },
  { value: "score-asc", label: "Lowest score" },
  { value: "views", label: "Most viewed" },
  { value: "inquiries", label: "Most inquired" },
  { value: "saves", label: "Most saved" },
  { value: "price", label: "Highest price" },
];

const isUuid = (v: string) => /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(v);
const publicUrl = (id: string) => `/en/property/${id}`;
const per = (deal: string) => (deal === "rent" ? "/ month" : deal === "daily" ? "/ night" : "");
// The listing quality score's parts, in plain words.
const PART_LABEL: Record<string, string> = {
  photos: "Photos", video: "Video", description: "Description", languages: "English and Arabic",
  facts: "Property facts", location: "Location", price: "Published price", amenities: "Amenities", contact: "Phone number",
};
const PART_TIP: Record<string, string> = {
  photos: "Add more photos: ten or more earns full marks.",
  video: "Add a short video walk-through.",
  description: "Write a fuller description: 400 characters or more.",
  languages: "Give the title and description in both English and Arabic.",
  facts: "Fill in the rooms, area and year built.",
  location: "Choose the neighbourhood and place a pin on the map.",
  price: "Publish a price instead of \u201cprice on request\u201d.",
  amenities: "Tick at least three amenities.",
  contact: "Add a phone number.",
};
const scoreTone = (n: number | null) => (n == null ? "neutral" : n >= 80 ? "good" : n >= 60 ? "gold" : n >= 40 ? "warn" : "bad");
const shownPrice = (r: ListingRow) => (r.price_on_request ? "On request" : jod(r.price_jod));

const place = (r: { city_id: string | null; neighborhood_id?: string | null }) =>
  [r.city_id, r.neighborhood_id].filter(Boolean).map(humanize).join(" · ");

export default function ListingsPage() {
  const { api, overview, refreshOverview } = useAdmin();
  const { toast, confirm } = useFeedback();
  const [query, setQuery] = useQuery(DEFAULTS);
  const [text, setText] = useSearchText(query.q, q => setQuery({ q, page: "0" }));
  const page = Number(query.page) || 0;
  const list = useList<ListingRow>(
    api,
    "/api/admin/listings",
    "listings",
    qs({
      q: query.q, status: query.status, owner: query.owner, page,
      sort: query.sort.replace(/-asc$/, ""), dir: query.sort.endsWith("-asc") ? "asc" : "",
    }),
  );
  const [openId, setOpenId] = useState<string | null>(null);
  const [snapshot, setSnapshot] = useState<ListingRow | null>(null);
  const [busy, setBusy] = useState<string | null>(null);
  const rows = list.rows;
  const open = (openId && (rows?.find(r => r.id === openId) ?? (snapshot?.id === openId ? snapshot : null))) || null;

  // A link straight to one listing (/admin/listings?q=<id>) opens it.
  useEffect(() => {
    if (isUuid(query.q) && rows?.length === 1 && rows[0].id === query.q) {
      setOpenId(rows[0].id);
      setSnapshot(rows[0]);
    }
  }, [rows, query.q]);

  // Following a link inside the panel to another owner's listings closes it.
  useEffect(() => setOpenId(null), [query.owner]);

  const show = (r: ListingRow) => {
    setSnapshot(r);
    setOpenId(r.id);
  };

  async function patch(r: ListingRow, body: Partial<ListingRow>, done: string, undo?: Partial<ListingRow>) {
    setBusy(r.id);
    try {
      await api("/api/admin/listings", { method: "PATCH", body: { id: r.id, ...body } });
      setSnapshot(s => (s && s.id === r.id ? { ...s, ...body } : s));
      toast({
        tone: "good",
        title: done,
        body: titleOf(r),
        action: undo ? { label: "Undo", run: () => void patch({ ...r, ...body }, undo, "Change undone") } : undefined,
      });
      await list.reload();
      void refreshOverview();
    } catch (e) {
      toast({ tone: "bad", title: "Couldn't save the change", body: (e as Error).message });
    } finally {
      setBusy(null);
    }
  }

  const setStatus = (r: ListingRow, status: string) =>
    status !== r.status && patch(r, { status }, `Now ${labelOf(LISTING_STATUS, status).label.toLowerCase()}`, { status: r.status });
  const feature = (r: ListingRow, featured: boolean) =>
    patch(r, { featured }, featured ? "Listing featured" : "No longer featured", { featured: r.featured });
  const verify = (r: ListingRow, verified: boolean) =>
    patch(r, { verified }, verified ? "Marked as verified" : "Verified badge removed", { verified: r.verified });

  async function rescore() {
    const ok = await confirm({
      title: "Re-score every listing?",
      body: "Every listing's quality score is worked out again from what is stored now. Use this after the scoring rules change; saves are scored automatically.",
      confirm: "Re-score all",
    });
    if (!ok) return;
    setBusy("rescore");
    try {
      const res = await api<{ scored: number }>("/api/admin/listings", { method: "POST", body: { action: "rescore" } });
      toast({ tone: "good", title: "Scores updated", body: `${full(res.scored)} listings scored.` });
      await list.reload();
    } catch (e) {
      toast({ tone: "bad", title: "Couldn't re-score", body: (e as Error).message });
    } finally {
      setBusy(null);
    }
  }

  async function remove(r: ListingRow) {
    const ok = await confirm({
      title: "Delete this listing for good?",
      body: (
        <>
          <b>{titleOf(r)}</b> and its inquiries, views and reports are deleted, and this cannot be undone. To take it
          off the site and keep the owner&apos;s work, pause it instead.
        </>
      ),
      confirm: "Delete listing",
      danger: true,
    });
    if (!ok) return;
    setBusy(r.id);
    try {
      await api(`/api/admin/listings?id=${r.id}`, { method: "DELETE" });
      toast({ tone: "good", title: "Listing deleted", body: titleOf(r) });
      setOpenId(null);
      await list.reload();
      void refreshOverview();
    } catch (e) {
      toast({ tone: "bad", title: "Couldn't delete the listing", body: (e as Error).message });
    } finally {
      setBusy(null);
    }
  }

  const counts = overview?.listings.byStatus ?? {};
  const filtered = !!(query.q || query.status || query.owner);

  return (
    <>
      <PageHeader
        title="Listings"
        subtitle="Every listing, whatever its status or owner. The score is how complete a listing is; the best scores are shown first on the site."
        actions={
          <Button icon="refresh" onClick={() => void rescore()} disabled={busy === "rescore"}>
            {busy === "rescore" ? "Scoring\u2026" : "Re-score all"}
          </Button>
        }
      />

      <Chips
        label="Status"
        value={query.status}
        onChange={status => setQuery({ status, page: "0" })}
        options={[
          { value: "", label: "All", count: overview?.listings.total },
          ...STATUSES.map(s => ({ value: s, label: LISTING_STATUS[s].label, count: overview ? counts[s] ?? 0 : null })),
        ]}
      />

      <Toolbar>
        <SearchInput value={text} onChange={setText} placeholder="Search titles, or paste a listing id" label="Search listings" />
        <Select label="Sort" value={query.sort} onChange={sort => setQuery({ sort, page: "0" })} options={SORTS} />
        {query.owner && (
          <button type="button" className="adm-filter-pill" onClick={() => setQuery({ owner: "", page: "0" })}>
            One owner&apos;s listings <Icon name="x" size={13} />
          </button>
        )}
      </Toolbar>

      {list.error && <LoadError error={list.error} onRetry={() => void list.reload()} />}

      <Card flush>
        {!rows ? (
          <SkeletonRows cols={7} />
        ) : rows.length === 0 ? (
          <Empty
            icon="building"
            title={filtered ? "No listings match" : "No listings yet"}
            body={filtered ? "Try another search or status." : "Listings appear here as soon as owners create them."}
          />
        ) : (
          <TableScroll label="Listings" busy={list.loading}>
            <table className="adm-table">
              <thead>
                <tr>
                  <th scope="col">Listing</th>
                  <th scope="col">Owner</th>
                  <th scope="col">Status</th>
                  <th scope="col" className="num">Score</th>
                  <th scope="col" className="num">Price</th>
                  <th scope="col" className="num">Views <span className="adm-th-sub">7 days</span></th>
                  <th scope="col" className="num">Inquiries</th>
                  <th scope="col">Listed</th>
                  <th scope="col" className="adm-th-actions"><span className="adm-sr">Actions</span></th>
                </tr>
              </thead>
              <tbody>
                {rows.map(r => (
                  <tr key={r.id} className="is-clickable" onClick={() => show(r)}>
                    <td>
                      <div className="adm-cell-main">
                        <Thumb src={r.cover} />
                        <div className="adm-cell-text">
                          <button type="button" className="adm-row-title" onClick={e => { e.stopPropagation(); show(r); }}>
                            {titleOf(r)}
                          </button>
                          <div className="adm-cell-sub">
                            {DEAL[r.deal] ?? humanize(r.deal)} · {humanize(r.property_type)}
                            {r.city_id ? ` · ${humanize(r.city_id)}` : ""}
                          </div>
                        </div>
                      </div>
                    </td>
                    <td className="adm-cell-owner">
                      <div className="adm-cell-strong">{r.owner?.full_name || "—"}</div>
                      <div className="adm-cell-sub" dir="ltr">{r.phone || r.owner?.phone || ""}</div>
                    </td>
                    <td>
                      <div className="adm-badges">
                        <StatusBadge map={LISTING_STATUS} value={r.status} />
                        {r.featured && <Badge tone="gold" icon="star">Featured</Badge>}
                        {r.verified && <Badge tone="good" icon="shield">Verified</Badge>}
                      </div>
                    </td>
                    <td className="num">
                      <ScoreCell q={r.quality} />
                    </td>
                    <td className="num">
                      <div className="adm-cell-strong">{shownPrice(r)}</div>
                      <div className="adm-cell-sub">{r.price_on_request ? "" : per(r.deal)}</div>
                    </td>
                    <td className="num">
                      <div className="adm-cell-strong">{full(r.views7d)}</div>
                      <div className="adm-cell-sub">{compact(r.views)} in all</div>
                    </td>
                    <td className="num">
                      <div className="adm-cell-strong">
                        {r.inquiries_count ? (
                          <Link href={`/admin/inquiries?property=${r.id}`} onClick={e => e.stopPropagation()}>{full(r.inquiries_count)}</Link>
                        ) : (
                          "0"
                        )}
                      </div>
                      <div className="adm-cell-sub">{compact(r.saves)} saved</div>
                    </td>
                    <td className="adm-nowrap">
                      <span title={when(r.created_at)}>{ago(r.created_at)}</span>
                    </td>
                    <td className="adm-cell-actions" onClick={e => e.stopPropagation()}>
                      <RowMenu r={r} busy={busy === r.id} onOpen={() => show(r)} onStatus={s => void setStatus(r, s)} onFeature={() => void feature(r, !r.featured)} onVerify={() => void verify(r, !r.verified)} onDelete={() => void remove(r)} />
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </TableScroll>
        )}
        {rows && rows.length > 0 && (
          <Pager page={page} pageSize={list.pageSize} total={list.total} onPage={p => setQuery({ page: String(p) })} />
        )}
      </Card>

      <Drawer
        open={!!open}
        onClose={() => setOpenId(null)}
        title={open ? titleOf(open) : ""}
        subtitle={open ? `${DEAL[open.deal] ?? humanize(open.deal)} · ${humanize(open.property_type)}${open.city_id ? ` · ${humanize(open.city_id)}` : ""}` : undefined}
        footer={
          open && (
            <>
              <Button variant="danger-ghost" icon="trash" onClick={() => void remove(open)} disabled={busy === open.id}>Delete</Button>
              <span className="adm-grow" />
              <ButtonLink href={publicUrl(open.id)} external icon="external">View on the site</ButtonLink>
            </>
          )
        }
      >
        {open && (
          <ListingDetail
            r={open}
            busy={busy === open.id}
            onStatus={s => void setStatus(open, s)}
            onFeature={v => void feature(open, v)}
            onVerify={v => void verify(open, v)}
          />
        )}
      </Drawer>
    </>
  );
}

function RowMenu({ r, busy, onOpen, onStatus, onFeature, onVerify, onDelete }: {
  r: ListingRow; busy: boolean; onOpen: () => void; onStatus: (s: string) => void; onFeature: () => void; onVerify: () => void; onDelete: () => void;
}) {
  return (
    <Menu label={`Actions for ${titleOf(r)}`} trigger={<Icon name="more" size={18} />}>
      <MenuItem icon="eye" onSelect={onOpen}>Open details</MenuItem>
      <MenuItem icon="external" href={publicUrl(r.id)} external>View on the site</MenuItem>
      {r.inquiries_count > 0 && <MenuItem icon="inbox" href={`/admin/inquiries?property=${r.id}`}>Inquiries ({full(r.inquiries_count)})</MenuItem>}
      <MenuSep />
      {r.status === "active" ? (
        <MenuItem icon="pause" onSelect={() => onStatus("paused")} disabled={busy}>Pause (take off the site)</MenuItem>
      ) : (
        <MenuItem icon="play" onSelect={() => onStatus("active")} disabled={busy}>Make active</MenuItem>
      )}
      <MenuItem icon="star" onSelect={onFeature} disabled={busy}>{r.featured ? "Stop featuring" : "Feature"}</MenuItem>
      {/* A daily rental's badge follows its review, on the Daily rentals page. */}
      {r.deal !== "daily" && (
        <MenuItem icon="shield" onSelect={onVerify} disabled={busy}>{r.verified ? "Remove verified badge" : "Mark as verified"}</MenuItem>
      )}
      <MenuSep />
      <MenuItem icon="trash" danger onSelect={onDelete} disabled={busy}>Delete…</MenuItem>
    </Menu>
  );
}

function ListingDetail({ r, busy, onStatus, onFeature, onVerify }: {
  r: ListingRow; busy: boolean; onStatus: (s: string) => void; onFeature: (v: boolean) => void; onVerify: (v: boolean) => void;
}) {
  const phone = r.phone || r.owner?.phone || null;
  return (
    <>
      <div className="adm-detail-hero">
        <Thumb src={r.cover} size="lg" />
        <div className="adm-detail-hero-text">
          {r.title_ar && r.title_ar !== r.title_en && <p className="adm-ar" dir="rtl" lang="ar">{r.title_ar}</p>}
          <div className="adm-price">
            {shownPrice(r)} <small>{r.price_on_request ? "" : per(r.deal)}</small>
          </div>
          <div className="adm-badges">
            <StatusBadge map={LISTING_STATUS} value={r.status} />
            {r.featured && <Badge tone="gold" icon="star">Featured</Badge>}
            {r.verified && <Badge tone="good" icon="shield">Verified</Badge>}
          </div>
        </div>
      </div>

      <div className="adm-figures is-4">
        <Figure label="Views" value={compact(r.views)} sub={`${full(r.views7d)} this week`} />
        <Figure label="30 days" value={compact(r.views30d)} sub="views" />
        <Figure label="Inquiries" value={compact(r.inquiries_count)} sub={r.lastInquiry ? `last ${ago(r.lastInquiry)}` : "none yet"} />
        <Figure label="Saves" value={compact(r.saves)} sub="people saved it" />
      </div>

      <Section
        title="Listing score"
        aside={<span className="adm-cell-sub">{r.quality.scoredAt ? `Scored ${ago(r.quality.scoredAt)}` : "Not scored yet"}</span>}
      >
        <ScoreDetail q={r.quality} />
      </Section>

      <Section title="Manage">
        <div className="adm-field-row">
          <span className="adm-field-label">Status</span>
          <Select
            label="Status"
            value={r.status}
            onChange={onStatus}
            disabled={busy}
            options={STATUSES.map(s => ({ value: s, label: LISTING_STATUS[s].label }))}
          />
        </div>
        <Switch checked={r.featured} onChange={onFeature} disabled={busy} label="Featured" hint="Shown among the featured listings on the home page." />
        {r.deal === "daily" ? (
          <p className="adm-hint">A daily rental&apos;s verified badge follows its review on the <Link href="/admin/daily-rentals">Daily rentals</Link> page.</p>
        ) : (
          <Switch checked={r.verified} onChange={onVerify} disabled={busy} label="Verified" hint="Checked by Akarat.ai; shows the verified badge." />
        )}
      </Section>

      <Section title="Details">
        <KV
          items={[
            { k: "Place", v: place(r) || "—" },
            { k: "Rooms", v: `${r.bedrooms ?? "—"} bedrooms · ${r.bathrooms ?? "—"} bathrooms` },
            { k: "Area", v: r.area_sqm ? `${full(r.area_sqm)} m²` : "—" },
            { k: "Photos and videos", v: full(r.media) },
            { k: "Listed", v: when(r.created_at) },
            { k: "Last edited", v: when(r.updated_at) },
            { k: "Listing id", v: <span className="adm-id">{r.id.slice(0, 8)}…<CopyButton text={r.id} label="Copy the listing id" /></span> },
          ]}
        />
      </Section>

      <Section
        title="Owner"
        aside={r.owner_id && <Link className="adm-section-link" href={`/admin/users?q=${r.owner_id}`}>Open account</Link>}
      >
        <KV
          items={[
            { k: "Name", v: r.owner?.full_name || "—" },
            { k: "Role", v: r.owner?.role ? labelOf(ROLES, r.owner.role).label : "—" },
            {
              k: "Phone",
              v: phone ? (
                <span className="adm-inline-links" dir="ltr">
                  <a href={`tel:${phone}`}>{phone}</a>
                  <a href={whatsapp(phone)} target="_blank" rel="noreferrer">WhatsApp</a>
                </span>
              ) : (
                "—"
              ),
            },
            { k: "Their listings", v: <Link href={`/admin/listings?owner=${r.owner_id}`}>See all</Link> },
          ]}
        />
      </Section>
    </>
  );
}

/** The score in a table cell: the number in its band's colour, and a bar. */
function ScoreCell({ q }: { q: ListingRow["quality"] }) {
  const n = q.score ?? null;
  return (
    <div className="adm-score-cell" title={n == null ? "Not scored yet" : `${n} out of 100`}>
      <span className={`adm-score-n is-${scoreTone(n)}`}>{n == null ? "\u2014" : n}</span>
      <span className="adm-score-track" aria-hidden="true">
        <span className={`is-${scoreTone(n)}`} style={{ width: `${n ?? 0}%` }} />
      </span>
    </div>
  );
}

/** Each part of the score with its points, and what would raise it. */
function ScoreDetail({ q }: { q: ListingRow["quality"] }) {
  const parts = Object.entries(QUALITY_PARTS) as [string, number][];
  const n = q.score ?? q.current;
  return (
    <>
      <div className="adm-score-head">
        <span className={`adm-score-big is-${scoreTone(n)}`}>{n}</span>
        <span className="adm-cell-sub">
          out of 100{q.score == null ? ". Worked out now; it is stored at the next save or the nightly run." : ""}
        </span>
      </div>
      <ul className="adm-score-parts">
        {parts.map(([k, max]) => {
          const got = Number(q.parts?.[k] ?? 0);
          return (
            <li key={k}>
              <span className="adm-score-part-label">{PART_LABEL[k] ?? humanize(k)}</span>
              <span className="adm-score-track" aria-hidden="true">
                <span className={got >= max ? "is-good" : got > 0 ? "is-gold" : "is-bad"} style={{ width: `${(got / max) * 100}%` }} />
              </span>
              <span className="adm-score-part-n">{got}<small>/{max}</small></span>
            </li>
          );
        })}
      </ul>
      {q.missing.length > 0 && (
        <div className="adm-score-tips">
          <p className="adm-hint">To raise it, the owner can:</p>
          <ul>
            {q.missing.slice(0, 4).map(k => <li key={k}>{PART_TIP[k] ?? humanize(k)}</li>)}
          </ul>
        </div>
      )}
    </>
  );
}
