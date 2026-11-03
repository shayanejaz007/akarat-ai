"use client";

import Link from "next/link";
import { useId, useLayoutEffect, useRef, useState, type KeyboardEvent, type PointerEvent, type ReactNode } from "react";
import { dayLabel, full, tick } from "../_lib/format";
import { niceScale, shares, smoothPath, spread } from "../_lib/stats";
import { cx } from "./ui";

/*
 * The panel's charts, drawn by hand in SVG at the size they are shown (text
 * never scales with the card). The rules they follow:
 *
 *  - Colour does one job. Series take --c1, --c2, --c3 in that order (brand
 *    green, blue, the logo's gold), checked for colour-blind separation and
 *    contrast in both themes; text never wears a series colour.
 *  - Thin marks: 2px lines, columns at most 24px with a 4px rounded top,
 *    hairline solid gridlines, a 2px surface ring on dots.
 *  - One axis per chart. Two measures in different units are two charts.
 *  - The hover readout never gates a value: every chart has a table twin,
 *    and arrow keys move the readout for keyboard users.
 */

export type Series = { key: string; label: string; color: string };
type Row = { day: string } & Record<string, unknown>;

const num = (v: unknown): number => (typeof v === "number" ? (Number.isFinite(v) ? v : 0) : Number(v) || 0);
const crisp = (v: number) => Math.round(v) + 0.5;

function useWidth<T extends HTMLElement>() {
  const ref = useRef<T>(null);
  const [width, setWidth] = useState(0);
  useLayoutEffect(() => {
    const el = ref.current;
    if (!el) return;
    setWidth(el.clientWidth);
    const ro = new ResizeObserver(entries => setWidth(Math.round(entries[0].contentRect.width)));
    ro.observe(el);
    return () => ro.disconnect();
  }, []);
  return [ref, width] as const;
}

type Frame = {
  W: number; H: number; padL: number; padR: number; padT: number; padB: number;
  plotW: number; plotH: number; ticks: number[]; y: (v: number) => number;
};

function frame(width: number, height: number, peak: number, integer: boolean, format: (v: number) => string): Frame {
  const scale = niceScale(peak, { integer });
  const longest = Math.max(...scale.ticks.map(t => format(t).length));
  const padL = Math.round(Math.max(26, longest * 6.6 + 12));
  const padR = 14;
  const padT = 12;
  const padB = 28;
  const W = Math.max(width, 160);
  const plotW = W - padL - padR;
  const plotH = height - padT - padB;
  return { W, H: height, padL, padR, padT, padB, plotW, plotH, ticks: scale.ticks, y: v => padT + plotH * (1 - v / scale.max) };
}

type XLabel = { i: number; x: number; anchor: "start" | "middle" | "end" };

function Axes({ f, format, labels, data }: { f: Frame; format: (v: number) => string; labels: XLabel[]; data: Row[] }) {
  return (
    <g>
      {f.ticks.map((t, i) => (
        <g key={t}>
          <line x1={f.padL} x2={f.W - f.padR} y1={crisp(f.y(t))} y2={crisp(f.y(t))} className={i === 0 ? "adm-axis-base" : "adm-axis-grid"} />
          <text x={f.padL - 8} y={f.y(t)} dy="0.32em" textAnchor="end" className="adm-axis-tick">{format(t)}</text>
        </g>
      ))}
      {labels.map(l => (
        <text key={l.i} x={l.x} y={f.H - 8} textAnchor={l.anchor} className="adm-axis-tick">{dayLabel(data[l.i].day)}</text>
      ))}
    </g>
  );
}

/** The readout beside the crosshair: values lead, names follow, each keyed by a short stroke of its colour. */
function Readout({ x, W, top, title, rows }: { x: number; W: number; top: number; title: string; rows: { color: string; label: string; value: string }[] }) {
  return (
    <div className={cx("adm-tip", x > W * 0.6 && "is-flipped")} style={{ left: x, top }}>
      <div className="adm-tip-title">{title}</div>
      {rows.map(r => (
        <div key={r.label} className="adm-tip-row">
          <i style={{ background: r.color }} />
          <b>{r.value}</b>
          <span>{r.label}</span>
        </div>
      ))}
    </div>
  );
}

/** Arrow keys, Home and End move the readout; Escape or leaving hides it. */
function useScrub(n: number) {
  const [at, setAt] = useState<number | null>(null);
  const onKeyDown = (e: KeyboardEvent) => {
    if (!n) return;
    const move = (to: (v: number | null) => number) => {
      e.preventDefault();
      setAt(v => Math.max(0, Math.min(n - 1, to(v))));
    };
    if (e.key === "ArrowRight") move(v => (v === null ? n - 1 : v + 1));
    else if (e.key === "ArrowLeft") move(v => (v === null ? n - 1 : v - 1));
    else if (e.key === "Home") move(() => 0);
    else if (e.key === "End") move(() => n - 1);
    else if (e.key === "Escape") setAt(null);
  };
  return { at, setAt, onKeyDown, onBlur: () => setAt(null) };
}

export function Legend({ items, kind = "line" }: { items: { label: string; color: string; value?: string }[]; kind?: "line" | "box" }) {
  return (
    <ul className="adm-legend">
      {items.map(it => (
        <li key={it.label}>
          <i className={kind === "line" ? "is-line" : "is-box"} style={{ background: it.color }} aria-hidden="true" />
          <span>{it.label}</span>
          {it.value !== undefined && <b>{it.value}</b>}
        </li>
      ))}
    </ul>
  );
}

/** Every chart's accessible twin: the same numbers as a table, newest first. */
function TableTwin({ caption, head, rows }: { caption: string; head: string[]; rows: string[][] }) {
  return (
    <details className="adm-twin">
      <summary>Show as table</summary>
      <div className="adm-twin-body">
        <table>
          <caption className="adm-sr">{caption}</caption>
          <thead>
            <tr>{head.map(h => <th key={h} scope="col">{h}</th>)}</tr>
          </thead>
          <tbody>
            {rows.map((r, i) => (
              <tr key={i}>
                {r.map((c, j) => (j === 0 ? <th key={j} scope="row">{c}</th> : <td key={j}>{c}</td>))}
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </details>
  );
}

/**
 * Change over time: one line per series, a soft wash under a single series,
 * a crosshair that snaps to the nearest day. Two or more series get a legend
 * carrying each one's total.
 */
export function LineChart({ data, series, label, height = 240, format = tick, valueFormat = full, integer = true }: {
  data: Row[]; series: Series[]; label: string; height?: number;
  format?: (v: number) => string; valueFormat?: (v: number) => string; integer?: boolean;
}) {
  const [ref, width] = useWidth<HTMLDivElement>();
  const n = data.length;
  const scrub = useScrub(n);
  const values = series.map(s => data.map(d => num(d[s.key])));
  const peak = Math.max(0, ...values.flat());
  const f = frame(width, height, peak, integer, format);
  const x = (i: number) => f.padL + (n <= 1 ? f.plotW / 2 : (i * f.plotW) / (n - 1));
  const pts = (si: number) => values[si].map((v, i) => [x(i), f.y(v)] as [number, number]);
  const labels: XLabel[] = spread(n, f.W < 420 ? 3 : 5).map(i => ({ i, x: x(i), anchor: i === 0 ? "start" : i === n - 1 ? "end" : "middle" }));
  const totals = values.map(v => v.reduce((a, b) => a + b, 0));
  const at = scrub.at;

  const pick = (e: PointerEvent<SVGRectElement>) => {
    const box = e.currentTarget.getBoundingClientRect();
    scrub.setAt(n <= 1 ? 0 : Math.max(0, Math.min(n - 1, Math.round(((e.clientX - box.left) / box.width) * (n - 1)))));
  };

  const summary = `${label}. ${series.map((s, si) => `${s.label}: ${valueFormat(totals[si])} in total`).join("; ")}.`;
  return (
    <div className="adm-chart-wrap">
      {series.length > 1 && <Legend items={series.map((s, si) => ({ label: s.label, color: s.color, value: valueFormat(totals[si]) }))} />}
      <div ref={ref} className="adm-chart" style={{ height }} tabIndex={0} role="img" aria-label={summary} onKeyDown={scrub.onKeyDown} onBlur={scrub.onBlur}>
        {width > 0 && n > 0 && (
          <svg width={f.W} height={f.H} aria-hidden="true">
            <Axes f={f} format={format} labels={labels} data={data} />
            {series.length === 1 && (
              <path d={`${smoothPath(pts(0))}L${x(n - 1)},${f.y(0)}L${x(0)},${f.y(0)}Z`} fill={series[0].color} opacity={0.1} />
            )}
            {series.map((s, si) => (
              <path key={s.key} d={smoothPath(pts(si))} fill="none" stroke={s.color} strokeWidth={2} strokeLinecap="round" strokeLinejoin="round" />
            ))}
            {at !== null && <line className="adm-crosshair" x1={crisp(x(at))} x2={crisp(x(at))} y1={f.padT} y2={f.padT + f.plotH} />}
            {series.map((s, si) => {
              const i = at ?? n - 1;
              return <circle key={`dot-${s.key}`} cx={x(i)} cy={f.y(values[si][i])} r={4} fill={s.color} stroke="var(--surface)" strokeWidth={2} />;
            })}
            <rect
              x={f.padL - 6}
              y={f.padT}
              width={f.plotW + 12}
              height={f.plotH}
              fill="transparent"
              className="adm-chart-hit"
              onPointerMove={pick}
              onPointerDown={pick}
              onPointerLeave={() => scrub.setAt(null)}
            />
          </svg>
        )}
        {at !== null && width > 0 && (
          <Readout
            x={x(at)}
            W={f.W}
            top={f.padT}
            title={dayLabel(data[at].day, true)}
            rows={series.map((s, si) => ({ color: s.color, label: s.label, value: valueFormat(values[si][at]) }))}
          />
        )}
        {peak === 0 && width > 0 && <div className="adm-chart-empty">Nothing recorded in this period</div>}
      </div>
      <TableTwin
        caption={label}
        head={["Day", ...series.map(s => s.label)]}
        rows={[...data.keys()].reverse().map(i => [dayLabel(data[i].day, true), ...values.map(v => valueFormat(v[i]))])}
      />
    </div>
  );
}

function columnPath(x: number, top: number, w: number, base: number): string {
  const r = Math.min(4, base - top, w / 2);
  return `M${x},${base}V${top + r}Q${x},${top} ${x + r},${top}H${x + w - r}Q${x + w},${top} ${x + w},${top + r}V${base}Z`;
}

/** Magnitude per day: one series of columns, each its own hover target. */
export function ColumnChart({ data, field, name, label, color = "var(--c1)", height = 220, format = tick, valueFormat = full, integer = true }: {
  data: Row[]; field: string; name: string; label: string; color?: string; height?: number;
  format?: (v: number) => string; valueFormat?: (v: number) => string; integer?: boolean;
}) {
  const [ref, width] = useWidth<HTMLDivElement>();
  const n = data.length;
  const scrub = useScrub(n);
  const values = data.map(d => num(d[field]));
  const peak = Math.max(0, ...values);
  const f = frame(width, height, peak, integer, format);
  const band = n ? f.plotW / n : f.plotW;
  const barW = Math.max(2, Math.min(18, band * 0.5));
  const bx = (i: number) => f.padL + band * i + (band - barW) / 2;
  const mid = (i: number) => f.padL + band * i + band / 2;
  const labels: XLabel[] = spread(n, f.W < 420 ? 3 : 5).map(i => ({
    i,
    x: i === 0 ? bx(0) : i === n - 1 ? bx(n - 1) + barW : mid(i),
    anchor: i === 0 ? "start" : i === n - 1 ? "end" : "middle",
  }));
  const total = values.reduce((a, b) => a + b, 0);
  const at = scrub.at;

  const pick = (e: PointerEvent<SVGRectElement>) => {
    const box = e.currentTarget.getBoundingClientRect();
    scrub.setAt(Math.max(0, Math.min(n - 1, Math.floor(((e.clientX - box.left) / box.width) * n))));
  };

  return (
    <div className="adm-chart-wrap">
      <div
        ref={ref}
        className="adm-chart"
        style={{ height }}
        tabIndex={0}
        role="img"
        aria-label={`${label}. ${valueFormat(total)} in total.`}
        onKeyDown={scrub.onKeyDown}
        onBlur={scrub.onBlur}
      >
        {width > 0 && n > 0 && (
          <svg width={f.W} height={f.H} aria-hidden="true">
            <Axes f={f} format={format} labels={labels} data={data} />
            {values.map((v, i) =>
              v > 0 ? (
                <path key={data[i].day} d={columnPath(bx(i), f.y(v), barW, f.y(0))} fill={color} className={at !== null && at !== i ? "adm-col is-dim" : "adm-col"} />
              ) : null,
            )}
            <rect x={f.padL} y={f.padT} width={f.plotW} height={f.plotH} fill="transparent" className="adm-chart-hit" onPointerMove={pick} onPointerDown={pick} onPointerLeave={() => scrub.setAt(null)} />
          </svg>
        )}
        {at !== null && width > 0 && (
          <Readout x={mid(at)} W={f.W} top={f.padT} title={dayLabel(data[at].day, true)} rows={[{ color, label: name, value: valueFormat(values[at]) }]} />
        )}
        {peak === 0 && width > 0 && <div className="adm-chart-empty">Nothing recorded in this period</div>}
      </div>
      <TableTwin caption={label} head={["Day", name]} rows={[...data.keys()].reverse().map(i => [dayLabel(data[i].day, true), valueFormat(values[i])])} />
    </div>
  );
}

/**
 * A stat tile's trend: the whole month in a quiet grey, the selected period
 * in the accent, ending on a dot. Decorative: the tile states the number.
 */
export function Sparkline({ values, from, height = 38, color = "var(--c1)" }: { values: number[]; from: number; height?: number; color?: string }) {
  const [ref, width] = useWidth<HTMLDivElement>();
  const id = `spark${useId().replace(/[^a-zA-Z0-9]/g, "")}`;
  const n = values.length;
  const max = Math.max(1, ...values);
  const pad = 4;
  const W = Math.max(width, 40);
  const pts = values.map((v, i) => [pad + (n <= 1 ? 0 : (i * (W - pad * 2)) / (n - 1)), pad + (height - pad * 2) * (1 - v / max)] as [number, number]);
  const d = smoothPath(pts);
  const cut = pts[Math.max(0, Math.min(n - 1, from))]?.[0] ?? 0;
  return (
    <div ref={ref} className="adm-spark" style={{ height }} aria-hidden="true">
      {width > 0 && n > 1 && (
        <svg width={W} height={height}>
          <defs>
            <clipPath id={id}>
              <rect x={cut} y={0} width={W - cut + 1} height={height} />
            </clipPath>
          </defs>
          <path d={d} fill="none" stroke="var(--c-muted)" strokeWidth={1.5} strokeLinecap="round" strokeLinejoin="round" />
          <path d={`${d}L${pts[n - 1][0]},${height}L${pts[0][0]},${height}Z`} fill={color} opacity={0.1} clipPath={`url(#${id})`} />
          <path d={d} fill="none" stroke={color} strokeWidth={2} strokeLinecap="round" strokeLinejoin="round" clipPath={`url(#${id})`} />
          <circle cx={pts[n - 1][0]} cy={pts[n - 1][1]} r={3.2} fill={color} stroke="var(--surface)" strokeWidth={1.5} />
        </svg>
      )}
    </div>
  );
}

export type BarRow = { key: string; label: ReactNode; n: number; href?: string; external?: boolean; extra?: ReactNode; title?: string };

/** A ranked list: one hue (the categories have no order of their own), value at the bar's end. */
export function BarList({ rows, format = full, empty = "Nothing yet." }: { rows: BarRow[]; format?: (n: number) => string; empty?: string }) {
  if (!rows.length) return <p className="adm-barlist-empty">{empty}</p>;
  const max = Math.max(1, ...rows.map(r => r.n));
  return (
    <ol className="adm-barlist">
      {rows.map(r => (
        <li key={r.key}>
          <div className="adm-barlist-top">
            <span className="adm-barlist-label" title={r.title}>
              {r.href ? (
                r.external ? <a href={r.href} target="_blank" rel="noreferrer">{r.label}</a> : <Link href={r.href}>{r.label}</Link>
              ) : (
                r.label
              )}
              {r.extra}
            </span>
            <span className="adm-barlist-n">{format(r.n)}</span>
          </div>
          <div className="adm-barlist-track" aria-hidden="true">
            <span style={{ width: `${r.n > 0 ? Math.max(1.5, (r.n / max) * 100) : 0}%` }} />
          </div>
        </li>
      ))}
    </ol>
  );
}

export type Segment = { key: string; label: string; n: number; color: string };

/** Part of a whole: one bar split by a 2px surface gap, its legend carrying every value and share. */
export function StackedBar({ segments, label, format = full }: { segments: Segment[]; label: string; format?: (n: number) => string }) {
  const total = segments.reduce((a, s) => a + Math.max(0, s.n), 0);
  const p = shares(segments.map(s => s.n));
  return (
    <div className="adm-stack">
      <div
        className="adm-stack-bar"
        role="img"
        aria-label={`${label}: ${segments.map((s, i) => `${s.label} ${format(s.n)}${total ? ` (${p[i]}%)` : ""}`).join(", ")}`}
      >
        {total > 0 ? (
          segments.map(s => (s.n > 0 ? <span key={s.key} style={{ flex: `${s.n} 1 0`, background: s.color }} title={`${s.label}: ${format(s.n)}`} /> : null))
        ) : (
          <span className="is-empty" />
        )}
      </div>
      <ul className="adm-legend is-stack">
        {segments.map((s, i) => (
          <li key={s.key}>
            <i className="is-box" style={{ background: s.color }} aria-hidden="true" />
            <span>{s.label}</span>
            <b>{format(s.n)}</b>
            <small>{total ? `${p[i]}%` : "—"}</small>
          </li>
        ))}
      </ul>
    </div>
  );
}

/** A value against a limit. The track is a lighter step of the fill's own colour. */
export function Meter({ value, max, label, tone = "accent" }: { value: number; max: number; label: string; tone?: "accent" | "warn" | "bad" }) {
  const p = max > 0 ? Math.max(0, Math.min(1, value / max)) : 0;
  return (
    <div className={cx("adm-meter", `is-${tone}`)} role="meter" aria-label={label} aria-valuemin={0} aria-valuemax={max} aria-valuenow={value}>
      <span style={{ width: `${p * 100}%` }} />
    </div>
  );
}
