"use client";

import Link from "next/link";
import { useEffect, useState } from "react";
import { useAdmin } from "../_components/context";
import { useFeedback } from "../_components/feedback";
import { Icon } from "../_components/icons";
import {
  Avatar, Badge, ButtonLink, Card, Chips, Drawer, Empty, KV, LoadError, PageHeader, Pager, SearchInput, Section, Segmented,
  SkeletonRows, StatusBadge, TableScroll, Toolbar, cx,
} from "../_components/ui";
import { qs, useList, useQuery, useSearchText } from "../_lib/api";
import { ago, titleOf, when, whatsapp } from "../_lib/format";
import { INQUIRY_STATUS, LISTING_STATUS } from "../_lib/labels";
import type { InquiryRow } from "../_lib/types";

/* Every message sent to a listing's owner (GET/PATCH /api/admin/inquiries). */

const DEFAULTS = { q: "", status: "", property: "", page: "0" };
const STATUSES = ["new", "read", "replied", "closed"];

export default function InquiriesPage() {
  const { api, overview, refreshOverview } = useAdmin();
  const { toast } = useFeedback();
  const [query, setQuery] = useQuery(DEFAULTS);
  const [text, setText] = useSearchText(query.q, q => setQuery({ q, page: "0" }));
  const page = Number(query.page) || 0;
  const list = useList<InquiryRow>(api, "/api/admin/inquiries", "inquiries", qs({ q: query.q, status: query.status, property: query.property, page }));
  const [openId, setOpenId] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  const rows = list.rows;
  const open = rows?.find(r => r.id === openId) ?? null;
  const filtered = !!(query.q || query.status || query.property);

  useEffect(() => setOpenId(null), [query.property]);

  async function setStatus(r: InquiryRow, status: string) {
    if (status === r.status) return;
    setBusy(true);
    try {
      await api("/api/admin/inquiries", { method: "PATCH", body: { id: r.id, status } });
      toast({ tone: "good", title: `Marked as ${INQUIRY_STATUS[status].label.toLowerCase()}` });
      await list.reload();
      void refreshOverview();
    } catch (e) {
      toast({ tone: "bad", title: "Couldn't change the status", body: (e as Error).message });
    } finally {
      setBusy(false);
    }
  }

  return (
    <>
      <PageHeader title="Inquiries" subtitle="Every message sent to a listing's owner from the website or the app, newest first." />

      <Chips
        label="Status"
        value={query.status}
        onChange={status => setQuery({ status, page: "0" })}
        options={[
          { value: "", label: "All", count: overview?.inquiries.total },
          ...STATUSES.map(s => ({ value: s, label: INQUIRY_STATUS[s].label, count: s === "new" ? overview?.inquiries.new : undefined })),
        ]}
      />
      <Toolbar>
        <SearchInput value={text} onChange={setText} placeholder="Search name, email, phone or message" label="Search inquiries" />
        {query.property && (
          <button type="button" className="adm-filter-pill" onClick={() => setQuery({ property: "", page: "0" })}>
            One listing&apos;s inquiries <Icon name="x" size={13} />
          </button>
        )}
      </Toolbar>

      {list.error && <LoadError error={list.error} onRetry={() => void list.reload()} />}

      <Card flush>
        {!rows ? (
          <SkeletonRows cols={5} />
        ) : rows.length === 0 ? (
          <Empty icon="inbox" title={filtered ? "No inquiries match" : "No inquiries yet"} body={filtered ? "Try another search or status." : "Messages to owners appear here."} />
        ) : (
          <TableScroll label="Inquiries" busy={list.loading}>
            <table className="adm-table">
              <thead>
                <tr>
                  <th scope="col">From</th>
                  <th scope="col">Message</th>
                  <th scope="col">Listing</th>
                  <th scope="col">Received</th>
                  <th scope="col">Status</th>
                </tr>
              </thead>
              <tbody>
                {rows.map(r => (
                  <tr key={r.id} className={cx("is-clickable", r.status === "new" && "is-unread")} onClick={() => setOpenId(r.id)}>
                    <td>
                      <div className="adm-person">
                        <Avatar name={r.name} email={r.email} seed={r.email ?? r.name} size={32} />
                        <div className="adm-person-text">
                          <button type="button" className="adm-row-title" onClick={e => { e.stopPropagation(); setOpenId(r.id); }}>
                            {r.name}
                          </button>
                          <div className="adm-cell-sub">{r.email || r.phone || (r.sender_id ? "Signed in" : "Guest")}</div>
                        </div>
                      </div>
                    </td>
                    <td>
                      <div className="adm-clamp" dir="auto">{r.message}</div>
                    </td>
                    <td>
                      <div className="adm-cell-strong adm-ellipsis">{titleOf(r.properties)}</div>
                      {r.properties && r.properties.status !== "active" && <StatusBadge map={LISTING_STATUS} value={r.properties.status} />}
                    </td>
                    <td className="adm-nowrap" title={when(r.created_at)}>{ago(r.created_at)}</td>
                    <td><StatusBadge map={INQUIRY_STATUS} value={r.status} /></td>
                  </tr>
                ))}
              </tbody>
            </table>
          </TableScroll>
        )}
        {rows && rows.length > 0 && <Pager page={page} pageSize={list.pageSize} total={list.total} onPage={p => setQuery({ page: String(p) })} />}
      </Card>

      <Drawer
        open={!!open}
        onClose={() => setOpenId(null)}
        title={open ? `From ${open.name}` : ""}
        subtitle={open ? `Received ${when(open.created_at)}` : undefined}
      >
        {open && (
          <>
            <Section title="Status">
              <Segmented
                label="Status"
                value={open.status}
                onChange={s => void setStatus(open, s)}
                options={STATUSES.map(s => ({ value: s, label: INQUIRY_STATUS[s].label }))}
              />
              {busy && <p className="adm-hint">Saving…</p>}
              <p className="adm-hint">Owners answer inquiries themselves; this status is for tracking them here.</p>
            </Section>

            <Section title="Message">
              <blockquote className="adm-quote" dir="auto">{open.message}</blockquote>
            </Section>

            <Section title="Sender">
              <KV
                items={[
                  { k: "Name", v: <>{open.name} {open.sender_id ? <Badge tone="info">Signed in</Badge> : <Badge>Guest</Badge>}</> },
                  { k: "Email", v: open.email ? <a href={`mailto:${open.email}`}>{open.email}</a> : "—" },
                  { k: "Phone", v: open.phone ? <span dir="ltr">{open.phone}</span> : "—" },
                ]}
              />
              <div className="adm-actions">
                {open.email && <ButtonLink href={`mailto:${open.email}`} external icon="mail" size="sm">Email</ButtonLink>}
                {open.phone && <ButtonLink href={`tel:${open.phone}`} external icon="phone" size="sm">Call</ButtonLink>}
                {open.phone && <ButtonLink href={whatsapp(open.phone)} external icon="message" size="sm">WhatsApp</ButtonLink>}
              </div>
            </Section>

            <Section title="Listing" aside={<Link className="adm-section-link" href={`/admin/listings?q=${open.property_id}`}>Open listing</Link>}>
              <KV
                items={[
                  { k: "Listing", v: titleOf(open.properties) },
                  ...(open.properties ? [{ k: "Status", v: <StatusBadge map={LISTING_STATUS} value={open.properties.status} /> }] : []),
                  { k: "Owner", v: open.owner?.full_name || "—" },
                  { k: "Owner's phone", v: open.owner?.phone ? <span dir="ltr">{open.owner.phone}</span> : "—" },
                  { k: "All its inquiries", v: <Link href={`/admin/inquiries?property=${open.property_id}`}>See all</Link> },
                ]}
              />
            </Section>
          </>
        )}
      </Drawer>
    </>
  );
}
