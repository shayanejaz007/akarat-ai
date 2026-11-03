/**
 * The arithmetic behind the panel's charts and stat tiles. Pure and
 * import-free, like format.ts, so tests/admin runs it under plain Node.
 */

export type DayRow = { day: string } & Record<string, unknown>;

const num = (v: unknown): number => (typeof v === "number" ? (Number.isFinite(v) ? v : 0) : Number(v) || 0);

/** The last n rows of a series that runs oldest first. */
export const lastN = <T>(rows: T[], n: number): T[] => (n >= rows.length ? rows.slice() : rows.slice(rows.length - n));

export const sum = (rows: DayRow[], field: string): number => rows.reduce((a, r) => a + num(r[field]), 0);

export const column = (rows: DayRow[], field: string): number[] => rows.map(r => num(r[field]));

export type Change = { current: number; previous: number | null; ratio: number | null };

/**
 * The last n days against the n before them. previous is null when the
 * series is too short to hold both periods; ratio is null when there is
 * nothing to divide by (no previous period, or a previous period of zero).
 */
export function change(rows: DayRow[], field: string, n: number): Change {
  const current = sum(lastN(rows, n), field);
  if (rows.length < n * 2) return { current, previous: null, ratio: null };
  const previous = sum(rows.slice(rows.length - n * 2, rows.length - n), field);
  return { current, previous, ratio: previous > 0 ? (current - previous) / previous : null };
}

export type Trend = { text: string; dir: "up" | "down" | "flat"; good: boolean | null };

/**
 * A change as a stat tile shows it: "12%" up or down, "No change", or
 * "+5 from 0" when the previous period was empty. Null when there is no
 * previous period to compare with. `upIsGood` says which way is good news.
 */
export function trend(c: Change, upIsGood = true): Trend | null {
  if (c.previous === null) return null;
  if (c.ratio === null) {
    return c.current === 0
      ? { text: "No change", dir: "flat", good: null }
      : { text: `+${Math.round(c.current).toLocaleString("en-US")} from 0`, dir: "up", good: upIsGood };
  }
  const p = Math.abs(c.ratio) * 100;
  if (p < 0.5) return { text: "No change", dir: "flat", good: null };
  const up = c.ratio > 0;
  return { text: `${p >= 10 ? Math.round(p) : Math.round(p * 10) / 10}%`, dir: up ? "up" : "down", good: up === upIsGood };
}

/**
 * An axis from zero to a clean maximum with about `ticks` evenly spaced
 * steps of 1, 2, 2.5 or 5 times a power of ten. Counts get whole steps.
 */
export function niceScale(max: number, opts: { ticks?: number; integer?: boolean } = {}): { max: number; ticks: number[] } {
  const want = opts.ticks ?? 4;
  if (!(max > 0)) return { max: 1, ticks: [0, 1] };
  const rough = max / want;
  const pow = Math.pow(10, Math.floor(Math.log10(rough)));
  let step = [1, 2, 2.5, 5, 10].map(m => m * pow).find(s => s >= rough - 1e-12) ?? 10 * pow;
  if (opts.integer) step = Math.max(1, Math.ceil(step));
  const ticks: number[] = [];
  for (let i = 0; i * step < max + step - 1e-9; i++) ticks.push(Math.round(i * step * 1e6) / 1e6);
  return { max: ticks[ticks.length - 1], ticks };
}

/** Whole percentages that add up to exactly 100 (largest remainder). */
export function shares(values: number[]): number[] {
  const clean = values.map(v => Math.max(0, num(v)));
  const total = clean.reduce((a, b) => a + b, 0);
  if (!total) return clean.map(() => 0);
  const raw = clean.map(v => (v / total) * 100);
  const out = raw.map(Math.floor);
  let left = 100 - out.reduce((a, b) => a + b, 0);
  const order = raw.map((r, i) => [r - Math.floor(r), i] as const).sort((a, b) => b[0] - a[0]);
  for (const [, i] of order) {
    if (left <= 0) break;
    out[i]++;
    left--;
  }
  return out;
}

/** The first `keep` rows as they are and the rest added up into one; folding a single row helps nobody. */
export function foldTail<T extends { n: number }>(rows: T[], keep: number, other: (n: number) => T): T[] {
  if (rows.length <= keep + 1) return rows.slice();
  const rest = rows.slice(keep).reduce((a, r) => a + r.n, 0);
  return rest > 0 ? [...rows.slice(0, keep), other(rest)] : rows.slice(0, keep);
}

/** Up to `count` evenly spread indexes into a series of n, always the first and the last. */
export function spread(n: number, count: number): number[] {
  if (n <= 0) return [];
  if (n <= count) return Array.from({ length: n }, (_, i) => i);
  const out = new Set<number>();
  for (let k = 0; k < count; k++) out.add(Math.round((k * (n - 1)) / (count - 1)));
  return [...out];
}

const r1 = (v: number) => Math.round(v * 10) / 10;

/**
 * An SVG path through the points that never overshoots them: monotone cubic
 * interpolation (Fritsch–Carlson), so a smooth line still never shows a dip
 * or peak the data does not have.
 */
export function smoothPath(pts: [number, number][]): string {
  const n = pts.length;
  if (n === 0) return "";
  if (n === 1) return `M${r1(pts[0][0])},${r1(pts[0][1])}`;
  const dx: number[] = [];
  const m: number[] = [];
  for (let i = 0; i < n - 1; i++) {
    dx[i] = pts[i + 1][0] - pts[i][0];
    m[i] = dx[i] === 0 ? 0 : (pts[i + 1][1] - pts[i][1]) / dx[i];
  }
  const t: number[] = [m[0]];
  for (let i = 1; i < n - 1; i++) t[i] = m[i - 1] * m[i] <= 0 ? 0 : (m[i - 1] + m[i]) / 2;
  t[n - 1] = m[n - 2];
  for (let i = 0; i < n - 1; i++) {
    if (m[i] === 0) {
      t[i] = 0;
      t[i + 1] = 0;
      continue;
    }
    const a = t[i] / m[i];
    const b = t[i + 1] / m[i];
    const s = a * a + b * b;
    if (s > 9) {
      const k = 3 / Math.sqrt(s);
      t[i] = k * a * m[i];
      t[i + 1] = k * b * m[i];
    }
  }
  let d = `M${r1(pts[0][0])},${r1(pts[0][1])}`;
  for (let i = 0; i < n - 1; i++) {
    const h = dx[i] / 3;
    d +=
      `C${r1(pts[i][0] + h)},${r1(pts[i][1] + t[i] * h)} ` +
      `${r1(pts[i + 1][0] - h)},${r1(pts[i + 1][1] - t[i + 1] * h)} ` +
      `${r1(pts[i + 1][0])},${r1(pts[i + 1][1])}`;
  }
  return d;
}

/** Hours since an ISO time. */
export const hoursSince = (iso: string, now: number = Date.now()): number => (now - new Date(iso).getTime()) / 3_600_000;
