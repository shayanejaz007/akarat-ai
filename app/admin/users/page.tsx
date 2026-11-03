"use client";

import Link from "next/link";
import { useEffect, useState } from "react";
import { useAdmin } from "../_components/context";
import { CopyButton, useFeedback } from "../_components/feedback";
import {
  Avatar, Badge, Card, Chips, Drawer, Empty, Figure, KV, LoadError, PageHeader, Pager, SearchInput, Section, Select, SkeletonRows,
  StatusBadge, Switch, TableScroll, Toolbar,
} from "../_components/ui";
import { qs, useList, useQuery, useSearchText } from "../_lib/api";
import { ago, full, when } from "../_lib/format";
import { PLATFORM, PROVIDER, ROLES, labelOf } from "../_lib/labels";
import type { UserRow } from "../_lib/types";

/* Every account: who they are, how they sign in, what they have listed and
   when they were last seen (GET/PATCH /api/admin/users). */

const DEFAULTS = { q: "", role: "", page: "0" };
const ROLE_KEYS = ["user", "property_owner", "agent", "admin"];
const ONLINE_MS = 2 * 60_000;

export default function UsersPage() {
  const { api, overview } = useAdmin();
  const { toast, confirm } = useFeedback();
  const [query, setQuery] = useQuery(DEFAULTS);
  const [text, setText] = useSearchText(query.q, q => setQuery({ q, page: "0" }));
  const page = Number(query.page) || 0;
  const list = useList<UserRow>(api, "/api/admin/users", "users", qs({ q: query.q, role: query.role, page }));
  const [openId, setOpenId] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  const rows = list.rows;
  const open = rows?.find(u => u.id === openId) ?? null;
  const filtered = !!(query.q || query.role);

  // A link to one account (/admin/users?q=<id>) opens it.
  useEffect(() => {
    if (rows?.length === 1 && rows[0].id === query.q) setOpenId(rows[0].id);
  }, [rows, query.q]);

  async function change(u: UserRow, body: { role?: string; verified?: boolean }, done: string) {
    if (body.role === "admin") {
      const ok = await confirm({
        title: "Make this account an admin?",
        body: (
          <>
            <b>{u.name || u.email || "This account"}</b> gets the admin role on the website and in the app. This panel still
            needs the admin password.
          </>
        ),
        confirm: "Make admin",
        danger: true,
      });
      if (!ok) return;
    }
    setBusy(true);
    try {
      await api("/api/admin/users", { method: "PATCH", body: { id: u.id, ...body } });
      toast({ tone: "good", title: done, body: u.name || u.email || undefined });
      await list.reload();
    } catch (e) {
      toast({ tone: "bad", title: "Couldn't save the change", body: (e as Error).message });
    } finally {
      setBusy(false);
    }
  }

  return (
    <>
      <PageHeader title="Users" subtitle="Every account, how it signs in, what it has listed and when it was last seen on the website or the app." />

      <Chips
        label="Role"
        value={query.role}
        onChange={role => setQuery({ role, page: "0" })}
        options={[
          { value: "", label: "All", count: overview?.users.total },
          { value: "user", label: "Users" },
          { value: "property_owner", label: "Owners" },
          { value: "agent", label: "Agents" },
          { value: "admin", label: "Admins", count: overview?.users.admins },
        ]}
      />
      <Toolbar>
        <SearchInput value={text} onChange={setText} placeholder="Search name, email, phone or agency" label="Search accounts" />
      </Toolbar>

      {list.error && <LoadError error={list.error} onRetry={() => void list.reload()} />}

      <Card flush>
        {!rows ? (
          <SkeletonRows cols={6} />
        ) : rows.length === 0 ? (
          <Empty icon="users" title={filtered ? "No accounts match" : "No accounts yet"} body={filtered ? "Try another search or role." : undefined} />
        ) : (
          <TableScroll label="Accounts" busy={list.loading}>
            <table className="adm-table">
              <thead>
                <tr>
                  <th scope="col">Account</th>
                  <th scope="col">Signs in with</th>
                  <th scope="col" className="num">Listings</th>
                  <th scope="col">Joined</th>
                  <th scope="col">Last seen</th>
                  <th scope="col">Role</th>
                </tr>
              </thead>
              <tbody>
                {rows.map(u => (
                  <tr key={u.id} className="is-clickable" onClick={() => setOpenId(u.id)}>
                    <td>
                      <div className="adm-person">
                        <Avatar name={u.name} email={u.email} seed={u.id} size={34} />
                        <div className="adm-person-text">
                          <button type="button" className="adm-row-title" onClick={e => { e.stopPropagation(); setOpenId(u.id); }}>
                            {u.name || u.email || u.phone || "Unnamed account"}
                          </button>
                          <div className="adm-cell-sub">{u.name ? u.email || u.phone : u.agency}</div>
                        </div>
                        {u.verified && <Badge tone="good" icon="shield" title="Verified">Verified</Badge>}
                      </div>
                    </td>
                    <td>
                      <div className="adm-badges">
                        {u.providers.length ? u.providers.map(p => <Badge key={p}>{PROVIDER[p] ?? p}</Badge>) : <span className="adm-cell-sub">—</span>}
                      </div>
                    </td>
                    <td className="num">
                      <div className="adm-cell-strong">{full(u.listings.total)}</div>
                      {u.listings.total > 0 && <div className="adm-cell-sub">{full(u.listings.active)} live</div>}
                    </td>
                    <td className="adm-nowrap" title={when(u.createdAt)}>{ago(u.createdAt)}</td>
                    <td className="adm-nowrap"><Seen u={u} /></td>
                    <td><StatusBadge map={ROLES} value={u.role} /></td>
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
        title={open ? open.name || open.email || "Account" : ""}
        subtitle={open ? <>Joined {when(open.createdAt)}</> : undefined}
      >
        {open && (
          <>
            <div className="adm-profile">
              <Avatar name={open.name} email={open.email} seed={open.id} size={56} />
              <div>
                <div className="adm-profile-name">{open.name || "No name given"}</div>
                <div className="adm-badges">
                  <StatusBadge map={ROLES} value={open.role} />
                  {open.verified && <Badge tone="good" icon="shield">Verified</Badge>}
                  <Seen u={open} />
                </div>
              </div>
            </div>

            <div className="adm-figures is-3">
              <Figure label="Listings" value={full(open.listings.total)} sub={`${full(open.listings.active)} live`} />
              <Figure label="Last seen" value={open.lastSeen ? ago(open.lastSeen) : "—"} sub={open.lastPlatform ? `on ${PLATFORM[open.lastPlatform] ?? open.lastPlatform}` : undefined} />
              <Figure label="Last sign-in" value={open.lastSignIn ? ago(open.lastSignIn) : "—"} />
            </div>

            <Section title="Manage">
              <div className="adm-field-row">
                <span className="adm-field-label">Role</span>
                <Select
                  label="Role"
                  value={open.role}
                  disabled={busy}
                  onChange={role => void change(open, { role }, `Role set to ${labelOf(ROLES, role).label}`)}
                  options={ROLE_KEYS.map(r => ({ value: r, label: ROLES[r].label }))}
                />
              </div>
              <Switch
                checked={open.verified}
                disabled={busy}
                onChange={verified => void change(open, { verified }, verified ? "Account verified" : "Verified badge removed")}
                label="Verified"
                hint="Shows the verified badge on their profile and listings."
              />
            </Section>

            <Section title="Contact">
              <KV
                items={[
                  { k: "Email", v: open.email ? <a href={`mailto:${open.email}`}>{open.email}</a> : "—" },
                  { k: "Phone", v: open.phone ? <span dir="ltr">{open.phone}</span> : "—" },
                  { k: "Agency", v: open.agency || "—" },
                  { k: "Signs in with", v: open.providers.map(p => PROVIDER[p] ?? p).join(", ") || "—" },
                ]}
              />
            </Section>

            <Section title="On Akarat.ai">
              <KV
                items={[
                  { k: "Listings", v: open.listings.total ? <Link href={`/admin/listings?owner=${open.id}`}>See their {full(open.listings.total)} listings</Link> : "None" },
                  { k: "Account id", v: <span className="adm-id">{open.id.slice(0, 8)}…<CopyButton text={open.id} label="Copy the account id" /></span> },
                ]}
              />
            </Section>
          </>
        )}
      </Drawer>
    </>
  );
}

function Seen({ u }: { u: UserRow }) {
  const online = !!u.lastSeen && Date.now() - new Date(u.lastSeen).getTime() < ONLINE_MS;
  if (online) return <Badge tone="good" dot>Online now</Badge>;
  const at = u.lastSeen ?? u.lastSignIn;
  return (
    <span title={at ? when(at) : undefined}>
      {at ? ago(at) : "Never"}
      {u.lastPlatform && <span className="adm-cell-sub"> · {PLATFORM[u.lastPlatform] ?? u.lastPlatform}</span>}
    </span>
  );
}
