"use client";

import Link from "next/link";
import { useEffect, useState } from "react";
import { SERVICE_ICON_NAMES } from "../../../lib/service-icons.js";
import { ServiceGlyph } from "../_components/ServiceGlyph";
import { useAdmin } from "../_components/context";
import { useFeedback } from "../_components/feedback";
import { Badge, Button, Card, Drawer, Empty, LoadError, PageHeader, SkeletonRows, Switch, TableScroll, cx } from "../_components/ui";
import { useList } from "../_lib/api";
import { full, humanize } from "../_lib/format";
import type { ServiceCategory } from "../_lib/types";

/*
 * What customers can ask for (GET/POST/PATCH/DELETE /api/admin/service-
 * categories). The website and the apps read the categories that are on
 * straight from the database, so a change here shows everywhere at once.
 */

type Draft = { id: string; name_en: string; name_ar: string; examples_en: string; examples_ar: string; icon: string; sort: string; custom: boolean };
const BLANK: Draft = { id: "", name_en: "", name_ar: "", examples_en: "", examples_ar: "", icon: "maintenance", sort: "500", custom: false };

export default function ServiceCategoriesPage() {
  const { api } = useAdmin();
  const { toast, confirm } = useFeedback();
  const list = useList<ServiceCategory>(api, "/api/admin/service-categories", "categories", "");
  const [editing, setEditing] = useState<ServiceCategory | "new" | null>(null);
  const [busy, setBusy] = useState<string | null>(null);
  const rows = list.rows;
  const notSetUp = list.error?.status === 501;

  async function toggle(c: ServiceCategory, active: boolean) {
    setBusy(c.id);
    try {
      await api("/api/admin/service-categories", { method: "PATCH", body: { id: c.id, active } });
      toast({ tone: "good", title: active ? "Switched on: customers can choose it" : "Switched off: hidden from customers", body: c.name_en });
      await list.reload();
    } catch (e) {
      toast({ tone: "bad", title: "Couldn't save", body: (e as Error).message });
    } finally {
      setBusy(null);
    }
  }

  async function remove(c: ServiceCategory) {
    const ok = await confirm({
      title: `Delete “${c.name_en}”?`,
      body: "Nobody has asked for it yet, so it can go completely. This can't be undone.",
      confirm: "Delete",
      danger: true,
    });
    if (!ok) return;
    setBusy(c.id);
    try {
      await api(`/api/admin/service-categories?id=${encodeURIComponent(c.id)}`, { method: "DELETE" });
      toast({ tone: "good", title: "Category deleted", body: c.name_en });
      setEditing(null);
      await list.reload();
    } catch (e) {
      toast({ tone: "bad", title: "Couldn't delete", body: (e as Error).message });
    } finally {
      setBusy(null);
    }
  }

  return (
    <>
      <PageHeader
        eyebrow="Services"
        title="Service categories"
        subtitle="What customers can ask for, in the order they see it. Switching one off hides it from new requests."
        actions={!notSetUp && <Button variant="primary" icon="plus" onClick={() => setEditing("new")}>Add a category</Button>}
      />

      {list.error && !notSetUp && <LoadError error={list.error} onRetry={() => void list.reload()} />}

      <Card flush>
        {notSetUp ? (
          <Empty icon="tag" title="Not set up yet" body={<>Run <code>supabase/migrations/0024_services.sql</code> in Supabase → SQL Editor.</>} />
        ) : !rows ? (
          <SkeletonRows cols={5} rows={8} />
        ) : rows.length === 0 ? (
          <Empty icon="tag" title="No categories" body="Add one so customers can ask for it." />
        ) : (
          <TableScroll label="Service categories" busy={list.loading}>
            <table className="adm-table">
              <thead>
                <tr>
                  <th scope="col">Category</th>
                  <th scope="col">Arabic</th>
                  <th scope="col" className="num">Order</th>
                  <th scope="col" className="num">Requests</th>
                  <th scope="col">Shown</th>
                </tr>
              </thead>
              <tbody>
                {rows.map(c => (
                  <tr key={c.id} className={cx("is-clickable", !c.active && "is-off")} onClick={() => setEditing(c)}>
                    <td>
                      <div className="adm-sv-cat">
                        <span className="adm-sv-cat-icon"><ServiceGlyph name={c.icon} /></span>
                        <div className="adm-cell-text">
                          <button type="button" className="adm-row-title" onClick={e => { e.stopPropagation(); setEditing(c); }}>{c.name_en}</button>
                          <div className="adm-cell-sub">{c.examples_en || "—"}</div>
                        </div>
                        {c.custom && <Badge tone="info" title="Customers name the service themselves">Free text</Badge>}
                      </div>
                    </td>
                    <td dir="rtl" lang="ar">
                      <div className="adm-cell-strong">{c.name_ar}</div>
                      <div className="adm-cell-sub">{c.examples_ar}</div>
                    </td>
                    <td className="num">{c.sort}</td>
                    <td className="num">
                      {c.requests ? <Link href={`/admin/services?status=all&category=${c.id}`} onClick={e => e.stopPropagation()}>{full(c.requests)}</Link> : "0"}
                    </td>
                    <td onClick={e => e.stopPropagation()}>
                      <button
                        type="button"
                        role="switch"
                        aria-checked={c.active}
                        aria-label={`Show ${c.name_en} to customers`}
                        className="adm-switch"
                        disabled={busy === c.id}
                        onClick={() => void toggle(c, !c.active)}
                      >
                        <span />
                      </button>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </TableScroll>
        )}
      </Card>

      <CategoryDrawer
        editing={editing}
        onClose={() => setEditing(null)}
        onSaved={async () => { setEditing(null); await list.reload(); }}
        onDelete={c => void remove(c)}
        busy={busy}
      />
    </>
  );
}

function CategoryDrawer({ editing, onClose, onSaved, onDelete, busy }: {
  editing: ServiceCategory | "new" | null; onClose: () => void; onSaved: () => Promise<void>; onDelete: (c: ServiceCategory) => void; busy: string | null;
}) {
  const { api } = useAdmin();
  const { toast } = useFeedback();
  const [d, setD] = useState<Draft>(BLANK);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState("");
  const isNew = editing === "new";
  const c = editing && editing !== "new" ? editing : null;

  useEffect(() => {
    setError("");
    if (editing === "new") setD(BLANK);
    else if (editing) {
      setD({
        id: editing.id, name_en: editing.name_en, name_ar: editing.name_ar, examples_en: editing.examples_en,
        examples_ar: editing.examples_ar, icon: editing.icon, sort: String(editing.sort), custom: editing.custom,
      });
    }
  }, [editing]);

  const set = (patch: Partial<Draft>) => setD(prev => ({ ...prev, ...patch }));

  async function save() {
    const sort = Number(d.sort);
    if (!d.name_en.trim() || !d.name_ar.trim()) return setError("Both names are needed: customers see the one in their language.");
    if (isNew && !/^[a-z0-9][a-z0-9_-]{1,40}$/.test(d.id.trim())) return setError("The id is 2–41 lower-case letters, digits, - or _. It never changes.");
    if (!Number.isInteger(sort) || sort < 0 || sort > 10000) return setError("Order is a whole number from 0 to 10,000.");
    setSaving(true);
    setError("");
    try {
      const body = {
        name_en: d.name_en, name_ar: d.name_ar, examples_en: d.examples_en, examples_ar: d.examples_ar, icon: d.icon, sort, custom: d.custom,
      };
      await api("/api/admin/service-categories", { method: isNew ? "POST" : "PATCH", body: isNew ? { id: d.id.trim(), ...body } : { id: d.id, ...body } });
      toast({ tone: "good", title: isNew ? "Category added" : "Category saved", body: d.name_en });
      await onSaved();
    } catch (e) {
      setError((e as Error).message);
    } finally {
      setSaving(false);
    }
  }

  return (
    <Drawer
      open={!!editing}
      onClose={onClose}
      title={isNew ? "New category" : c?.name_en ?? ""}
      subtitle={c ? <>id <code>{c.id}</code> · {c.requests ? `${full(c.requests)} requests` : "not used yet"}</> : "Shown to customers once saved, unless switched off"}
      footer={
        <>
          <Button variant="primary" icon="check" loading={saving} onClick={() => void save()}>{isNew ? "Add category" : "Save"}</Button>
          <Button variant="ghost" onClick={onClose}>Cancel</Button>
          {c && c.requests === 0 && (
            <Button variant="danger-ghost" icon="trash" disabled={busy === c.id} onClick={() => onDelete(c)}>Delete</Button>
          )}
        </>
      }
    >
      {isNew && (
        <label className="adm-field">
          <span className="adm-field-label">Id <small>(for links and the database; can&apos;t be changed later)</small></span>
          <input className="adm-input" value={d.id} onChange={e => set({ id: e.target.value.toLowerCase() })} placeholder="solar" spellCheck={false} dir="ltr" />
        </label>
      )}
      <div className="adm-sv-names">
        <label className="adm-field">
          <span className="adm-field-label">Name in English</span>
          <input className="adm-input" value={d.name_en} maxLength={60} onChange={e => set({ name_en: e.target.value })} placeholder="Solar panels" />
        </label>
        <label className="adm-field">
          <span className="adm-field-label">الاسم بالعربية</span>
          <input className="adm-input" value={d.name_ar} maxLength={60} onChange={e => set({ name_ar: e.target.value })} placeholder="الألواح الشمسية" dir="rtl" lang="ar" />
        </label>
        <label className="adm-field">
          <span className="adm-field-label">Examples in English <small>(under the name)</small></span>
          <input className="adm-input" value={d.examples_en} maxLength={200} onChange={e => set({ examples_en: e.target.value })} placeholder="Cleaning, repairs, installation" />
        </label>
        <label className="adm-field">
          <span className="adm-field-label">أمثلة بالعربية</span>
          <input className="adm-input" value={d.examples_ar} maxLength={200} onChange={e => set({ examples_ar: e.target.value })} dir="rtl" lang="ar" />
        </label>
      </div>

      <div className="adm-field">
        <span className="adm-field-label" id="sv-icon-label">Icon</span>
        <div className="adm-sv-icons" role="radiogroup" aria-labelledby="sv-icon-label">
          {SERVICE_ICON_NAMES.map(name => (
            <button
              key={name}
              type="button"
              role="radio"
              aria-checked={d.icon === name}
              aria-label={humanize(name)}
              title={humanize(name)}
              className="adm-sv-icon-opt"
              onClick={() => set({ icon: name })}
            >
              <ServiceGlyph name={name} />
            </button>
          ))}
        </div>
      </div>

      <label className="adm-field">
        <span className="adm-field-label">Order <small>(smaller comes first)</small></span>
        <input className="adm-input is-short" type="number" min={0} max={10000} step={10} value={d.sort} onChange={e => set({ sort: e.target.value })} />
      </label>

      <Switch
        checked={d.custom}
        onChange={custom => set({ custom })}
        label="Customers name the service"
        hint="For “something else”: the form asks what they need in their own words."
      />

      {error && <p className="adm-field-hint is-bad" role="alert">{error}</p>}
    </Drawer>
  );
}
