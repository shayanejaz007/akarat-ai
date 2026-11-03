"use client";

import Link from "next/link";
import { useState } from "react";
import { useAdmin } from "../_components/context";
import { useFeedback } from "../_components/feedback";
import { Icon } from "../_components/icons";
import {
  Badge, Button, Callout, Card, Chips, Empty, LoadError, Menu, MenuItem, PageHeader, Pager, SkeletonRows, StatusBadge, TableScroll,
} from "../_components/ui";
import { qs, useList, useQuery } from "../_lib/api";
import { ago, titleOf, when } from "../_lib/format";
import { LISTING_STATUS, REPORT_REASON, REPORT_STATUS } from "../_lib/labels";
import { hoursSince } from "../_lib/stats";
import type { ReportRow } from "../_lib/types";

/* Listings people reported from the app (GET/PATCH /api/admin/reports).
   Both app stores expect reports acted on within a day. */

const DEFAULTS = { status: "open", page: "0" };
const DUE_HOURS = 24;

const DONE: Record<string, string> = {
  removed: "Listing taken down: paused, not deleted",
  reviewed: "Marked as reviewed",
  dismissed: "Report dismissed",
  open: "Report reopened",
};

export default function ReportsPage() {
  const { api, overview, refreshOverview } = useAdmin();
  const { toast, confirm } = useFeedback();
  const [query, setQuery] = useQuery(DEFAULTS);
  const page = Number(query.page) || 0;
  const list = useList<ReportRow>(api, "/api/admin/reports", "reports", qs({ status: query.status, page }));
  const [busy, setBusy] = useState<string | null>(null);
  const rows = list.rows;

  async function decide(r: ReportRow, status: string) {
    if (status === "removed") {
      const ok = await confirm({
        title: "Take this listing off the site?",
        body: (
          <>
            <b>{titleOf(r.properties)}</b> is paused: hidden everywhere, but not deleted. The owner keeps their work and an
            admin can make it active again from Listings.
          </>
        ),
        confirm: "Take it down",
        danger: true,
      });
      if (!ok) return;
    }
    setBusy(r.id);
    try {
      await api("/api/admin/reports", { method: "PATCH", body: { id: r.id, status } });
      toast({ tone: "good", title: DONE[status] ?? "Saved", body: titleOf(r.properties) });
      await list.reload();
      void refreshOverview();
    } catch (e) {
      toast({ tone: "bad", title: "Couldn't save the decision", body: (e as Error).message });
    } finally {
      setBusy(null);
    }
  }

  return (
    <>
      <PageHeader
        title="Reports"
        subtitle="Listings people reported from the app. The app stores expect these handled within a day."
      />

      <Chips
        label="Status"
        value={query.status}
        onChange={status => setQuery({ status, page: "0" })}
        options={[
          { value: "open", label: "Open", count: overview?.openReports, urgent: true },
          { value: "reviewed", label: "Reviewed" },
          { value: "removed", label: "Taken down" },
          { value: "dismissed", label: "Dismissed" },
          { value: "", label: "All" },
        ]}
      />

      {list.error && <LoadError error={list.error} onRetry={() => void list.reload()} />}

      {list.extra.notSetUp ? (
        <Callout tone="warn" title="Reports aren't set up yet">
          Run <code>supabase/migrations/0015_listing_reports.sql</code> in Supabase so the app&apos;s “Report this listing” is saved here.
        </Callout>
      ) : (
        <Card flush>
          {!rows ? (
            <SkeletonRows cols={5} />
          ) : rows.length === 0 ? (
            <Empty
              icon={query.status === "open" ? "circleCheck" : "flag"}
              title={query.status === "open" ? "No open reports" : "Nothing here"}
              body={query.status === "open" ? "Every report has been dealt with." : undefined}
            />
          ) : (
            <TableScroll label="Reports" busy={list.loading}>
              <table className="adm-table">
                <thead>
                  <tr>
                    <th scope="col">Reported</th>
                    <th scope="col">Listing</th>
                    <th scope="col">Reason</th>
                    <th scope="col">Details</th>
                    <th scope="col">Status</th>
                    <th scope="col" className="adm-th-actions"><span className="adm-sr">Decision</span></th>
                  </tr>
                </thead>
                <tbody>
                  {rows.map(r => {
                    const overdue = r.status === "open" && hoursSince(r.created_at) > DUE_HOURS;
                    return (
                      <tr key={r.id}>
                        <td className="adm-nowrap">
                          <div className="adm-cell-strong" title={when(r.created_at)}>{ago(r.created_at)}</div>
                          {overdue && <Badge tone="bad" icon="clock">Over a day old</Badge>}
                        </td>
                        <td>
                          <Link className="adm-row-title" href={`/admin/listings?q=${r.property_id}`}>{titleOf(r.properties)}</Link>
                          {r.properties && <div><StatusBadge map={LISTING_STATUS} value={r.properties.status} /></div>}
                        </td>
                        <td>
                          <Badge tone={r.reason === "scam" ? "bad" : r.reason === "offensive" ? "warn" : "neutral"}>
                            {REPORT_REASON[r.reason] ?? r.reason}
                          </Badge>
                        </td>
                        <td>
                          {r.details ? <div className="adm-clamp" dir="auto">{r.details}</div> : <span className="adm-cell-sub">No details given</span>}
                        </td>
                        <td><StatusBadge map={REPORT_STATUS} value={r.status} /></td>
                        <td className="adm-cell-actions">
                          {r.status === "open" ? (
                            <div className="adm-actions is-nowrap">
                              <Button size="sm" variant="danger" icon="pause" loading={busy === r.id} onClick={() => void decide(r, "removed")}>Take down</Button>
                              <Menu label="More decisions" trigger={<Icon name="more" size={18} />}>
                                <MenuItem icon="check" onSelect={() => void decide(r, "reviewed")}>Reviewed: nothing wrong</MenuItem>
                                <MenuItem icon="x" onSelect={() => void decide(r, "dismissed")}>Dismiss</MenuItem>
                                <MenuItem icon="eye" href={`/en/property/${r.property_id}`} external>View on the site</MenuItem>
                              </Menu>
                            </div>
                          ) : (
                            <Button size="sm" variant="ghost" icon="refresh" disabled={busy === r.id} onClick={() => void decide(r, "open")}>Reopen</Button>
                          )}
                        </td>
                      </tr>
                    );
                  })}
                </tbody>
              </table>
            </TableScroll>
          )}
          {rows && rows.length > 0 && <Pager page={page} pageSize={list.pageSize} total={list.total} onPage={p => setQuery({ page: String(p) })} />}
        </Card>
      )}
    </>
  );
}
