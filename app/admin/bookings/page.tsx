"use client";

import Link from "next/link";
import { useEffect, useState } from "react";
import { useAdmin } from "../_components/context";
import { Icon } from "../_components/icons";
import {
  Card, Chips, Drawer, Empty, Figure, KV, LoadError, PageHeader, Pager, PersonBlock, SearchInput, Section, SkeletonRows,
  StatTile, StatusBadge, TableScroll, Toolbar,
} from "../_components/ui";
import { qs, useList, useQuery, useSearchText } from "../_lib/api";
import { ago, compact, dayLabel, dayLong, full, humanize, jod, plural, titleOf, when } from "../_lib/format";
import { BOOKING_STATUS, LISTING_STATUS, REVIEW } from "../_lib/labels";
import type { BookingRow } from "../_lib/types";

/* Every daily-rental booking request (GET /api/admin/bookings). Read only:
   approving, rejecting and confirming belong to the owner. */

const DEFAULTS = { q: "", status: "", property: "", page: "0" };

export default function BookingsPage() {
  const { api, overview } = useAdmin();
  const [query, setQuery] = useQuery(DEFAULTS);
  const [text, setText] = useSearchText(query.q, q => setQuery({ q, page: "0" }));
  const page = Number(query.page) || 0;
  const list = useList<BookingRow>(api, "/api/admin/bookings", "bookings", qs({ q: query.q, status: query.status, property: query.property, page }));
  const [open, setOpen] = useState<BookingRow | null>(null);
  const req = overview?.dailyRentals?.requests;
  const rows = list.rows;
  const filtered = !!(query.q || query.status || query.property);

  useEffect(() => setOpen(null), [query.property]);

  return (
    <>
      <PageHeader
        title="Bookings"
        subtitle="Every daily-rental booking request. The owner approves a request (their number is then shown to the renter) and confirms the stay once it is agreed; confirmed nights close on the calendar."
      />

      {req && (
        <div className="adm-grid g-4">
          <StatTile label="Booking requests" icon="calendar" tone="info" value={compact(req.total)} note={`${full(req.week)} in the last 7 days`} />
          <StatTile label="Waiting on owners" icon="clock" tone="warn" value={compact(req.pending)} note="not answered yet" />
          <StatTile label="Approved" icon="phone" tone="neutral" value={compact(req.approved)} note="number shared, stay not confirmed" />
          <StatTile label="Confirmed stays" icon="circleCheck" tone="good" value={compact(req.confirmed)} note={`${plural(req.nightsConfirmed, "night")} booked`} />
        </div>
      )}

      <Chips
        label="Status"
        value={query.status}
        onChange={status => setQuery({ status, page: "0" })}
        options={[
          { value: "", label: "All", count: req?.total },
          { value: "pending", label: "Waiting for the owner", count: req?.pending },
          { value: "approved", label: "Approved", count: req?.approved },
          { value: "confirmed", label: "Confirmed", count: req?.confirmed },
          { value: "rejected", label: "Rejected" },
          { value: "cancelled", label: "Cancelled" },
        ]}
      />
      <Toolbar>
        <SearchInput value={text} onChange={setText} placeholder="Search the renter's name or message" label="Search bookings" />
        {query.property && (
          <button type="button" className="adm-filter-pill" onClick={() => setQuery({ property: "", page: "0" })}>
            One listing&apos;s requests <Icon name="x" size={13} />
          </button>
        )}
      </Toolbar>

      {list.error && <LoadError error={list.error} onRetry={() => void list.reload()} />}

      <Card flush>
        {!rows ? (
          <SkeletonRows cols={6} />
        ) : rows.length === 0 ? (
          <Empty icon="calendar" title={filtered ? "No requests match" : "No booking requests yet"} body={filtered ? "Try another search or status." : "Requests appear here as renters send them."} />
        ) : (
          <TableScroll label="Booking requests" busy={list.loading}>
            <table className="adm-table">
              <thead>
                <tr>
                  <th scope="col">Listing</th>
                  <th scope="col">Renter</th>
                  <th scope="col">Dates</th>
                  <th scope="col" className="num">Guests</th>
                  <th scope="col" className="num">Total</th>
                  <th scope="col">Status</th>
                  <th scope="col">Asked</th>
                </tr>
              </thead>
              <tbody>
                {rows.map(b => (
                  <tr key={b.id} className="is-clickable" onClick={() => setOpen(b)}>
                    <td>
                      <button type="button" className="adm-row-title" onClick={e => { e.stopPropagation(); setOpen(b); }}>
                        {b.properties ? titleOf(b.properties) : "Deleted listing"}
                      </button>
                      <div className="adm-cell-sub">{b.properties?.city_id ? humanize(b.properties.city_id) : ""}</div>
                    </td>
                    <td><PersonBlock p={b.renter} fallback={b.renter_name} /></td>
                    <td className="adm-nowrap">
                      <div className="adm-cell-strong" title={`${dayLong(b.check_in)} to ${dayLong(b.check_out)}`}>
                        {dayLabel(b.check_in)} → {dayLabel(b.check_out)}
                      </div>
                      <div className="adm-cell-sub">{plural(b.nights, "night")}</div>
                    </td>
                    <td className="num">{full(b.guests)}</td>
                    <td className="num">
                      <div className="adm-cell-strong">{jod(b.total_price)}</div>
                      <div className="adm-cell-sub">{jod(b.nightly_price)} / night</div>
                    </td>
                    <td><StatusBadge map={BOOKING_STATUS} value={b.status} /></td>
                    <td className="adm-nowrap" title={when(b.created_at)}>{ago(b.created_at)}</td>
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
        onClose={() => setOpen(null)}
        title={open?.properties ? titleOf(open.properties) : "Booking request"}
        subtitle={open ? <StatusBadge map={BOOKING_STATUS} value={open.status} /> : undefined}
      >
        {open && <BookingDetail b={open} />}
      </Drawer>
    </>
  );
}

function BookingDetail({ b }: { b: BookingRow }) {
  return (
    <>
      <div className="adm-figures is-3">
        <Figure label="Check-in" value={dayLong(b.check_in)} />
        <Figure label="Check-out" value={dayLong(b.check_out)} />
        <Figure label="Stay" value={plural(b.nights, "night")} sub={plural(b.guests, "guest")} />
      </div>
      <div className="adm-figures is-2">
        <Figure label="Total" value={jod(b.total_price)} />
        <Figure label="Per night" value={jod(b.nightly_price)} />
      </div>

      {b.message && (
        <Section title="Renter's message">
          <blockquote className="adm-quote" dir="auto">{b.message}</blockquote>
        </Section>
      )}

      <Section title="Status">
        <KV
          items={[
            { k: "Now", v: <StatusBadge map={BOOKING_STATUS} value={b.status} /> },
            { k: "Asked", v: when(b.created_at) },
            { k: "Answered", v: b.responded_at ? `${when(b.responded_at)} (${ago(b.responded_at)})` : "Not yet" },
            ...(b.response_note ? [{ k: "Owner's note", v: <span dir="auto">{b.response_note}</span> }] : []),
            ...(b.closed_reason === "dates_taken" ? [{ k: "Closed", v: "The dates went to another guest" }] : []),
            ...(b.cancelled_by ? [{ k: "Cancelled by", v: `The ${b.cancelled_by}` }] : []),
          ]}
        />
      </Section>

      <Section title="Renter">
        <PersonBlock p={b.renter} fallback={b.renter_name} />
      </Section>
      <Section title="Owner">
        <PersonBlock p={b.owner} />
        {b.owner_phone && <p className="adm-hint" dir="ltr">Number shared with the renter: {b.owner_phone}</p>}
      </Section>

      {b.properties && (
        <Section title="Listing" aside={<Link className="adm-section-link" href={`/admin/listings?q=${b.property_id}`}>Open listing</Link>}>
          <KV
            items={[
              { k: "Listing", v: titleOf(b.properties) },
              { k: "Status", v: <StatusBadge map={LISTING_STATUS} value={b.properties.status} /> },
              ...(b.properties.daily_review ? [{ k: "Review", v: <StatusBadge map={REVIEW} value={b.properties.daily_review} /> }] : []),
              { k: "Requests for it", v: <Link href={`/admin/bookings?property=${b.property_id}`}>See all</Link> },
            ]}
          />
        </Section>
      )}
    </>
  );
}
