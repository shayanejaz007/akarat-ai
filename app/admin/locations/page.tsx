"use client";

import { useEffect, useMemo, useState } from "react";
import { ALL_CITIES, GOVERNORATES } from "../../../lib/reference";
import { useAdmin } from "../_components/context";
import { useFeedback } from "../_components/feedback";
import {
  Badge, Button, Callout, Card, Chips, Drawer, Empty, LoadError, PageHeader, Pager, SearchInput, Segmented, Select, SkeletonRows,
  Switch, TableScroll, Toolbar, cx,
} from "../_components/ui";
import { qs, useList, useQuery, useSearchText } from "../_lib/api";
import { full, humanize, when } from "../_lib/format";
import type { PlaceRow } from "../_lib/types";

/*
 * Every place the website and the apps offer (GET/POST/PATCH /api/admin/
 * locations, 0023_locations.sql): the 12 governorates, their cities, towns
 * and villages, and the neighbourhoods inside them. A change made here marks
 * the place as edited, so rebuilding the dataset never undoes it, and the
 * website and the apps lay it over the list they ship with. Nothing is
 * deleted: a listing may point at any of these, so a wrong one is switched
 * off instead.
 */

type Level = "gov" | "city" | "hood";
const DEFAULTS = { level: "city", gov: "", city: "", show: "", q: "", page: "0" };
const LEVEL_NAME: Record<Level, string> = { gov: "governorate", city: "city or town", hood: "neighbourhood" };

const govName = (id: string | null | undefined) => (id ? GOVERNORATES.find(g => g.id === id)?.en ?? humanize(id) : "—");
const cityName = (id: string | null | undefined) => (id ? ALL_CITIES.find(c => c.id === id)?.en ?? humanize(id) : "—");

export default function LocationsPage() {
  const { api } = useAdmin();
  const [query, setQuery] = useQuery(DEFAULTS);
  const [text, setText] = useSearchText(query.q, q => setQuery({ q, page: "0" }));
  const level = (["gov", "city", "hood"].includes(query.level) ? query.level : "city") as Level;
  const page = Number(query.page) || 0;
  const list = useList<PlaceRow>(
    api,
    "/api/admin/locations",
    "rows",
    qs({
      level, q: query.q, page,
      gov: level === "city" ? query.gov : "",
      city: level === "hood" ? query.city : "",
      edited: query.show === "edited" ? 1 : "",
      inactive: query.show === "off" ? 1 : "",
    }),
  );
  const [editing, setEditing] = useState<PlaceRow | "new" | null>(null);
  const rows = list.rows;
  const notSetUp = list.error?.status === 501;
  const citiesOfGov = useMemo(
    () => ALL_CITIES.filter(c => !query.gov || c.gov === query.gov).sort((a, b) => a.en.localeCompare(b.en)),
    [query.gov],
  );

  return (
    <>
      <PageHeader
        eyebrow="Marketplace"
        title="Locations"
        subtitle="The places listings, searches and service requests use. Changes show on the website and in the apps at once."
        actions={!notSetUp && level !== "gov" && <Button variant="primary" icon="plus" onClick={() => setEditing("new")}>Add a {LEVEL_NAME[level]}</Button>}
      />

      <Toolbar>
        <Segmented
          label="Level"
          value={level}
          onChange={l => setQuery({ level: l, page: "0", q: "" })}
          options={[
            { value: "gov", label: "Governorates" },
            { value: "city", label: "Cities and towns" },
            { value: "hood", label: "Neighbourhoods" },
          ]}
        />
      </Toolbar>
      <Chips
        label="Show"
        value={query.show}
        onChange={show => setQuery({ show, page: "0" })}
        options={[
          { value: "", label: "All" },
          { value: "edited", label: "Changed by an admin" },
          { value: "off", label: "Switched off" },
        ]}
      />
      <Toolbar>
        <SearchInput value={text} onChange={setText} placeholder="Name in English or Arabic, or the id" label="Search places" />
        {level !== "gov" && (
          <Select
            small
            label="Governorate"
            value={query.gov}
            onChange={gov => setQuery({ gov, city: "", page: "0" })}
            options={[{ value: "", label: "Every governorate" }, ...GOVERNORATES.map(g => ({ value: g.id, label: g.en }))]}
          />
        )}
        {level === "hood" && (
          <Select
            small
            label="City"
            value={query.city}
            onChange={city => setQuery({ city, page: "0" })}
            options={[{ value: "", label: "Every city" }, ...citiesOfGov.map(c => ({ value: c.id, label: c.en }))]}
          />
        )}
      </Toolbar>

      {list.error && !notSetUp && <LoadError error={list.error} onRetry={() => void list.reload()} />}

      <Card flush>
        {notSetUp ? (
          <Empty icon="map" title="Not set up yet" body={<>Run <code>supabase/migrations/0023_locations.sql</code> in Supabase → SQL Editor.</>} />
        ) : !rows ? (
          <SkeletonRows cols={5} />
        ) : rows.length === 0 ? (
          <Empty icon="map" title="No places match" body={query.q ? "Try the other language, or a shorter part of the name." : undefined} />
        ) : (
          <TableScroll label="Places" busy={list.loading}>
            <table className="adm-table">
              <thead>
                <tr>
                  <th scope="col">Name</th>
                  <th scope="col">Arabic</th>
                  {level !== "gov" && <th scope="col">{level === "city" ? "Governorate" : "City"}</th>}
                  {level !== "gov" && <th scope="col" className="num">Listings</th>}
                  <th scope="col">Source</th>
                </tr>
              </thead>
              <tbody>
                {rows.map(p => (
                  <tr key={p.id} className={cx("is-clickable", !p.active && "is-off")} onClick={() => setEditing(p)}>
                    <td>
                      <button type="button" className="adm-row-title" onClick={e => { e.stopPropagation(); setEditing(p); }}>{p.name_en}</button>
                      <div className="adm-cell-sub adm-mono">{p.id}</div>
                    </td>
                    <td dir="rtl" lang="ar" className="adm-cell-strong">{p.name_ar}</td>
                    {level !== "gov" && <td>{level === "city" ? govName(p.governorate_id) : cityName(p.city_id)}</td>}
                    {level !== "gov" && <td className="num">{full(p.listings)}</td>}
                    <td>
                      <div className="adm-badges">
                        {!p.active && <Badge tone="warn">Switched off</Badge>}
                        {p.edited ? <Badge tone="info">Changed by an admin</Badge> : p.geonames_id ? <Badge>GeoNames</Badge> : <Badge tone="good">Hand-checked</Badge>}
                      </div>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </TableScroll>
        )}
        {rows && rows.length > 0 && <Pager page={page} pageSize={list.pageSize} total={list.total} onPage={p => setQuery({ page: String(p) })} />}
      </Card>

      <p className="adm-hint adm-attrib">
        Place names beyond the hand-checked set are from <a href="https://www.geonames.org/" target="_blank" rel="noreferrer">GeoNames</a>, licensed CC BY 4.0.
      </p>

      <PlaceDrawer
        level={level}
        editing={editing}
        defaultGov={query.gov}
        defaultCity={query.city}
        onClose={() => setEditing(null)}
        onSaved={async () => { setEditing(null); await list.reload(); }}
      />
    </>
  );
}

type Draft = { name_en: string; name_ar: string; aliases: string; lat: string; lng: string; governorate_id: string; city_id: string; active: boolean };

function PlaceDrawer({ level, editing, defaultGov, defaultCity, onClose, onSaved }: {
  level: Level; editing: PlaceRow | "new" | null; defaultGov: string; defaultCity: string; onClose: () => void; onSaved: () => Promise<void>;
}) {
  const { api } = useAdmin();
  const { toast, confirm } = useFeedback();
  const [d, setD] = useState<Draft>({ name_en: "", name_ar: "", aliases: "", lat: "", lng: "", governorate_id: "", city_id: "", active: true });
  const [gov, setGov] = useState("");
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState("");
  const isNew = editing === "new";
  const p = editing && editing !== "new" ? editing : null;

  useEffect(() => {
    setError("");
    if (!editing) return;
    if (editing === "new") {
      const city = defaultCity ? ALL_CITIES.find(c => c.id === defaultCity) : null;
      setGov(city?.gov ?? defaultGov);
      setD({ name_en: "", name_ar: "", aliases: "", lat: "", lng: "", governorate_id: defaultGov, city_id: defaultCity, active: true });
    } else {
      const city = editing.city_id ? ALL_CITIES.find(c => c.id === editing.city_id) : null;
      setGov(city?.gov ?? editing.governorate_id ?? "");
      setD({
        name_en: editing.name_en, name_ar: editing.name_ar, aliases: (editing.aliases ?? []).join(", "),
        lat: editing.lat == null ? "" : String(editing.lat), lng: editing.lng == null ? "" : String(editing.lng),
        governorate_id: editing.governorate_id ?? "", city_id: editing.city_id ?? "", active: editing.active,
      });
    }
  }, [editing, defaultGov, defaultCity]);

  const set = (patch: Partial<Draft>) => setD(prev => ({ ...prev, ...patch }));
  const cities = useMemo(() => ALL_CITIES.filter(c => c.gov === gov).sort((a, b) => a.en.localeCompare(b.en)), [gov]);

  async function save() {
    const num = (v: string) => (v.trim() === "" ? null : Number(v));
    const lat = num(d.lat);
    const lng = num(d.lng);
    if (!d.name_en.trim() || !d.name_ar.trim()) return setError("Both names are needed.");
    if ((lat === null) !== (lng === null)) return setError("Give both the latitude and the longitude, or neither.");
    if (lat !== null && (!Number.isFinite(lat) || lat < 29 || lat > 33.5 || !Number.isFinite(lng!) || lng! < 34.8 || lng! > 39.4)) {
      return setError("That point isn't in Jordan. Latitude is about 29–33.5 and longitude 34.8–39.4.");
    }
    if (level === "city" && !d.governorate_id) return setError("Choose the governorate.");
    if (level === "hood" && !d.city_id) return setError("Choose the city.");
    if (p && p.listings > 0 && !d.active && p.active) {
      const ok = await confirm({
        title: "Switch this place off?",
        body: `${full(p.listings)} listings use it. They keep it and stay readable, but nobody can pick it for a new listing, search or request.`,
        confirm: "Switch off",
        danger: true,
      });
      if (!ok) return;
    }
    const body: Record<string, unknown> = {
      level,
      name_en: d.name_en,
      name_ar: d.name_ar,
      aliases: d.aliases.split(/[,،\n]/).map(a => a.trim()).filter(Boolean),
      lat,
      lng,
    };
    if (level === "city") body.governorate_id = d.governorate_id;
    if (level === "hood") body.city_id = d.city_id;
    if (!isNew) {
      body.id = p!.id;
      body.active = d.active;
    }
    setSaving(true);
    setError("");
    try {
      await api("/api/admin/locations", { method: isNew ? "POST" : "PATCH", body });
      toast({ tone: "good", title: isNew ? "Place added" : "Place saved", body: d.name_en });
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
      title={isNew ? `New ${LEVEL_NAME[level]}` : p?.name_en ?? ""}
      subtitle={p ? <>id <code>{p.id}</code>{p.updated_at ? ` · updated ${when(p.updated_at)}` : ""}</> : "Shown on the website and in the apps once saved"}
      footer={
        <>
          <Button variant="primary" icon="check" loading={saving} onClick={() => void save()}>{isNew ? "Add place" : "Save"}</Button>
          <Button variant="ghost" onClick={onClose}>Cancel</Button>
        </>
      }
    >
      {p && p.listings > 0 && <Callout tone="info">{full(p.listings)} listings are in this place. A new name shows on all of them.</Callout>}

      <div className="adm-sv-names">
        <label className="adm-field">
          <span className="adm-field-label">Name in English</span>
          <input className="adm-input" value={d.name_en} maxLength={80} onChange={e => set({ name_en: e.target.value })} />
        </label>
        <label className="adm-field">
          <span className="adm-field-label">الاسم بالعربية</span>
          <input className="adm-input" value={d.name_ar} maxLength={80} onChange={e => set({ name_ar: e.target.value })} dir="rtl" lang="ar" />
        </label>
      </div>

      <label className="adm-field">
        <span className="adm-field-label">Other spellings <small>(comma between each; what people might type)</small></span>
        <input className="adm-input" value={d.aliases} onChange={e => set({ aliases: e.target.value })} placeholder="Swaifieh, Sweifiyeh, الصويفيه" dir="auto" />
      </label>

      {level === "city" && (
        <div className="adm-field-row">
          <span className="adm-field-label">Governorate</span>
          <Select
            label="Governorate"
            value={d.governorate_id}
            onChange={governorate_id => set({ governorate_id })}
            options={[{ value: "", label: "Choose…" }, ...GOVERNORATES.map(g => ({ value: g.id, label: `${g.en} · ${g.ar}` }))]}
          />
        </div>
      )}
      {level === "hood" && (
        <>
          <div className="adm-field-row">
            <span className="adm-field-label">Governorate</span>
            <Select
              label="Governorate"
              value={gov}
              onChange={v => { setGov(v); set({ city_id: "" }); }}
              options={[{ value: "", label: "Choose…" }, ...GOVERNORATES.map(g => ({ value: g.id, label: `${g.en} · ${g.ar}` }))]}
            />
          </div>
          <div className="adm-field-row">
            <span className="adm-field-label">City</span>
            <Select
              label="City"
              value={d.city_id}
              disabled={!gov}
              onChange={city_id => set({ city_id })}
              options={[
                { value: "", label: gov ? "Choose…" : "Choose the governorate first" },
                ...cities.map(c => ({ value: c.id, label: `${c.en} · ${c.ar}` })),
                ...(d.city_id && !cities.some(c => c.id === d.city_id) ? [{ value: d.city_id, label: humanize(d.city_id) }] : []),
              ]}
            />
          </div>
        </>
      )}

      <div className="adm-sv-names">
        <label className="adm-field">
          <span className="adm-field-label">Latitude</span>
          <input className="adm-input" inputMode="decimal" value={d.lat} onChange={e => set({ lat: e.target.value })} placeholder="31.9539" dir="ltr" />
        </label>
        <label className="adm-field">
          <span className="adm-field-label">Longitude</span>
          <input className="adm-input" inputMode="decimal" value={d.lng} onChange={e => set({ lng: e.target.value })} placeholder="35.9106" dir="ltr" />
        </label>
      </div>
      <p className="adm-hint">The centre of the place: maps open here when someone picks it.</p>

      {p && (
        <Switch
          checked={d.active}
          onChange={active => set({ active })}
          label="Shown in pickers and searches"
          hint="Off hides it from new listings, searches and requests. Listings already there keep it."
        />
      )}

      {error && <p className="adm-field-hint is-bad" role="alert">{error}</p>}
    </Drawer>
  );
}
