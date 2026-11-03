"use client";

import Link from "next/link";
import { useState, type ReactNode } from "react";
import { useAdmin } from "../_components/context";
import { useFeedback } from "../_components/feedback";
import { Icon, type IconName } from "../_components/icons";
import {
  Badge, Button, Callout, Chips, Empty, LoadError, PageHeader, Pager, PersonBlock, SearchInput, SkeletonRows, StatusBadge, Toolbar, cx,
} from "../_components/ui";
import { qs, useList, useQuery, useSearchText } from "../_lib/api";
import { ago, full, humanize, jod, plural, titleOf, when } from "../_lib/format";
import { LISTING_STATUS, REVIEW } from "../_lib/labels";
import type { DailyRow } from "../_lib/types";

/*
 * The daily-rental review queue (GET/PATCH /api/admin/daily). A daily rental
 * stays hidden until it is approved here. The database does the rest: an
 * approved listing becomes public with the verified badge, and the owner is
 * told about every decision.
 */

const DEFAULTS = { review: "pending", q: "", page: "0" };
type Action = "approve" | "reject" | "suspend" | "revoke" | "reinstate" | "reviewed";

const DONE: Record<Action, string> = {
  approve: "Approved: now public, with the verified badge",
  reject: "Rejected: the owner can see why",
  suspend: "Suspended: hidden from the site",
  revoke: "Approval taken back: hidden and back in the queue",
  reinstate: "Reinstated: public again",
  reviewed: "Changes marked as reviewed",
};

const publicUrl = (id: string) => `/en/property/${id}`;

export default function DailyRentalsPage() {
  const { api, overview, refreshOverview } = useAdmin();
  const { toast, ask } = useFeedback();
  const [query, setQuery] = useQuery(DEFAULTS);
  const [text, setText] = useSearchText(query.q, q => setQuery({ q, page: "0" }));
  const page = Number(query.page) || 0;
  const list = useList<DailyRow>(api, "/api/admin/daily", "listings", qs({ review: query.review, q: query.q, page }));
  const [busy, setBusy] = useState<string | null>(null);
  const counts = overview?.dailyRentals?.review;

  async function act(r: DailyRow, action: Action) {
    let note: string | undefined;
    if (action === "reject" || action === "suspend" || action === "revoke") {
      const v = await ask(
        action === "reject"
          ? {
              title: "Reject this daily rental?",
              body: "The owner sees your reason. When they save a fix, the listing comes back to this queue.",
              label: "Reason for the owner",
              placeholder: "For example: the photos don't show the bedrooms. Add a photo of every room.",
              required: true,
              confirm: "Reject",
              danger: true,
            }
          : action === "suspend"
            ? {
                title: "Suspend this daily rental?",
                body: "It is hidden at once and stays hidden until you reinstate it. The owner sees your reason.",
                label: "Reason for the owner",
                required: true,
                confirm: "Suspend",
                danger: true,
              }
            : {
                title: "Take back the approval?",
                body: "The listing is hidden and goes back to the review queue.",
                label: "Note for the owner",
                confirm: "Take back approval",
                danger: true,
              },
      );
      if (v === null) return;
      note = v;
    }
    setBusy(r.id);
    try {
      await api("/api/admin/daily", { method: "PATCH", body: { id: r.id, action, note } });
      toast({ tone: "good", title: DONE[action], body: titleOf(r) });
      await list.reload();
      void refreshOverview();
    } catch (e) {
      toast({ tone: "bad", title: "Couldn't save the decision", body: (e as Error).message });
    } finally {
      setBusy(null);
    }
  }

  const rows = list.rows;
  return (
    <>
      <PageHeader
        title="Daily rentals"
        subtitle="A daily rental stays hidden until it is approved here. Approving makes it public everywhere with the verified badge, and the owner is told about every decision."
      />

      <Chips
        label="Review"
        value={query.review}
        onChange={review => setQuery({ review, page: "0" })}
        options={[
          { value: "pending", label: "Waiting for review", count: counts?.pending, urgent: true },
          { value: "changed", label: "Edited since approval", count: counts?.changed, urgent: true },
          { value: "approved", label: "Approved", count: counts?.approved },
          { value: "rejected", label: "Rejected", count: counts?.rejected },
          { value: "suspended", label: "Suspended", count: counts?.suspended },
          { value: "all", label: "All" },
        ]}
      />
      <Toolbar>
        <SearchInput value={text} onChange={setText} placeholder="Search titles, or paste a listing id" label="Search daily rentals" />
        {query.review === "pending" && <span className="adm-toolbar-note"><Icon name="clock" size={14} /> Oldest first</span>}
      </Toolbar>

      {list.error && <LoadError error={list.error} onRetry={() => void list.reload()} />}

      {!rows ? (
        <div className="adm-card"><SkeletonRows rows={3} cols={4} /></div>
      ) : rows.length === 0 ? (
        <div className="adm-card">
          <Empty
            icon={query.review === "pending" ? "circleCheck" : "bed"}
            title={query.q ? "Nothing matches" : query.review === "pending" ? "The queue is empty" : "Nothing here"}
            body={query.review === "pending" && !query.q ? "New daily rentals land here for review." : undefined}
          />
        </div>
      ) : (
        <div className={cx("adm-reviews", list.loading && "is-busy")}>
          {rows.map(r => (
            <ReviewCard key={r.id} r={r} busy={busy === r.id} onAct={a => void act(r, a)} />
          ))}
        </div>
      )}
      {rows && rows.length > 0 && (
        <div className="adm-card adm-pager-card">
          <Pager page={page} pageSize={list.pageSize} total={list.total} onPage={p => setQuery({ page: String(p) })} />
        </div>
      )}
    </>
  );
}

function Fact({ icon, label, children }: { icon: IconName; label: string; children: ReactNode }) {
  return (
    <div className="adm-fact">
      <Icon name={icon} size={16} />
      <div>
        <div className="adm-fact-label">{label}</div>
        <div className="adm-fact-value">{children}</div>
      </div>
    </div>
  );
}

function ReviewCard({ r, busy, onAct }: { r: DailyRow; busy: boolean; onAct: (a: Action) => void }) {
  const [shown, setShown] = useState(0);
  const live = r.daily_review === "approved" && r.status === "active";
  const asked = Object.values(r.requests).reduce((a, b) => a + b, 0);
  const media = r.media;
  const current = media[Math.min(shown, media.length - 1)];
  const place = [r.city_id, r.neighborhood_id].filter(Boolean).map(humanize).join(" · ");

  return (
    <article className="adm-card adm-review">
      <div className="adm-review-gallery">
        {!current ? (
          <div className="adm-review-nophoto">
            <Icon name="image" size={28} />
            <span>No photos</span>
          </div>
        ) : (
          <>
            <a className="adm-review-main" href={current.url} target="_blank" rel="noreferrer" title="Open full size">
              {current.video ? (
                <video src={current.url} muted controls preload="metadata" />
              ) : (
                <img src={current.url} alt={`Photo ${shown + 1} of ${media.length}`} loading="lazy" />
              )}
            </a>
            {media.length > 1 && (
              <div className="adm-review-thumbs">
                {media.slice(0, 8).map((m, i) => (
                  <button
                    key={m.url + i}
                    type="button"
                    className={cx("adm-review-thumb", i === shown && "is-active")}
                    onClick={() => setShown(i)}
                    aria-label={`Show ${m.video ? "video" : "photo"} ${i + 1}`}
                    aria-pressed={i === shown}
                  >
                    {m.video ? <span className="adm-review-video"><Icon name="play" size={14} /></span> : <img src={m.url} alt="" loading="lazy" />}
                  </button>
                ))}
                {media.length > 8 && <span className="adm-review-more">+{media.length - 8}</span>}
              </div>
            )}
          </>
        )}
      </div>

      <div className="adm-review-body">
        <div className="adm-review-head">
          <div className="adm-review-titles">
            <h3>{live ? <a href={publicUrl(r.id)} target="_blank" rel="noreferrer">{titleOf(r)}</a> : titleOf(r)}</h3>
            {r.title_ar && r.title_ar !== r.title_en && <p className="adm-ar" dir="rtl" lang="ar">{r.title_ar}</p>}
          </div>
          <div className="adm-badges">
            <StatusBadge map={REVIEW} value={r.daily_review} />
            {live ? (
              <Badge tone="good" dot>Live</Badge>
            ) : (
              <Badge title={`Listing status: ${LISTING_STATUS[r.status]?.label ?? r.status}`}>Not on the site</Badge>
            )}
          </div>
        </div>

        <div className="adm-facts">
          <Fact icon="dollar" label="Per night">{jod(r.price_jod)}</Fact>
          <Fact icon="users" label="Guests">Up to {r.max_guests ?? "—"}</Fact>
          <Fact icon="clock" label="Minimum stay">{plural(r.min_nights ?? 1, "night")}</Fact>
          <Fact icon="bed" label="Rooms">
            {r.bedrooms ?? "—"} bed · {r.bathrooms ?? "—"} bath{r.area_sqm ? ` · ${full(r.area_sqm)} m²` : ""}
          </Fact>
          <Fact icon="building" label="Type">{humanize(r.property_type)}</Fact>
          <Fact icon="pin" label="Place">
            {place || "—"}
            {r.lat != null && r.lng != null && (
              <>
                {" · "}
                <a href={`https://www.google.com/maps?q=${r.lat},${r.lng}`} target="_blank" rel="noreferrer">Map</a>
                <span className="adm-cell-sub"> ({r.location_precision === "exact" ? "exact" : "approximate"})</span>
              </>
            )}
          </Fact>
        </div>

        <details className="adm-disclosure" open={r.daily_review === "pending"}>
          <summary>Descriptions{r.amenities.length ? ` and ${r.amenities.length} amenities` : ""}</summary>
          <div className="adm-disclosure-body">
            {r.description_en && <p dir="auto">{r.description_en}</p>}
            {r.description_ar && <p dir="rtl" lang="ar">{r.description_ar}</p>}
            {!r.description_en && !r.description_ar && <p className="adm-cell-sub">No description.</p>}
            {r.amenities.length > 0 && (
              <div className="adm-badges">
                {r.amenities.map(a => <Badge key={a}>{humanize(a)}</Badge>)}
              </div>
            )}
          </div>
        </details>

        <div className="adm-review-meta">
          <div>
            <div className="adm-meta-label">Owner</div>
            <PersonBlock p={r.owner} />
            {r.owner?.joined && <div className="adm-cell-sub">Joined {ago(r.owner.joined)}</div>}
          </div>
          <div>
            <div className="adm-meta-label">Submitted</div>
            <div>{when(r.created_at)}</div>
            {r.daily_reviewed_at && <div className="adm-cell-sub">Last decision {ago(r.daily_reviewed_at)}</div>}
            {r.daily_changed_at && <div className="adm-cell-sub is-warn">Edited by the owner {ago(r.daily_changed_at)}</div>}
          </div>
          <div>
            <div className="adm-meta-label">Booking requests</div>
            {asked ? (
              <Link href={`/admin/bookings?property=${r.id}`}>
                {full(asked)} · {full(r.requests.confirmed ?? 0)} confirmed
              </Link>
            ) : (
              <div>None yet</div>
            )}
            <div className="adm-cell-sub">{full(r.views)} views · {full(r.saves)} saves</div>
          </div>
        </div>

        {r.publicPhone && (
          <Callout tone="warn" title="A phone number shows publicly">
            This listing shows <span dir="ltr">{r.publicPhone}</span>. A daily rental should share a number only after the owner approves a request.
          </Callout>
        )}
        {r.daily_review_note && <Callout tone="info" title="Note to the owner">{r.daily_review_note}</Callout>}

        <div className="adm-review-actions">
          {(r.daily_review === "pending" || r.daily_review === "rejected") && (
            <Button variant="primary" icon="check" loading={busy} onClick={() => onAct("approve")}>Approve</Button>
          )}
          {r.daily_review === "approved" && r.daily_changed_at && (
            <Button variant="primary" icon="check" loading={busy} onClick={() => onAct("reviewed")}>Changes look fine</Button>
          )}
          {r.daily_review === "suspended" && (
            <Button variant="primary" icon="play" loading={busy} onClick={() => onAct("reinstate")}>Reinstate</Button>
          )}
          {r.daily_review === "pending" && (
            <Button variant="danger-ghost" icon="x" disabled={busy} onClick={() => onAct("reject")}>Reject…</Button>
          )}
          {r.daily_review === "approved" && (
            <Button icon="arrowDown" disabled={busy} onClick={() => onAct("revoke")}>Take back approval…</Button>
          )}
          {r.daily_review !== "suspended" && (
            <Button variant="danger-ghost" icon="pause" disabled={busy} onClick={() => onAct("suspend")}>Suspend…</Button>
          )}
        </div>
      </div>
    </article>
  );
}
