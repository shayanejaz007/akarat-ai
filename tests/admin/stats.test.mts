import { test } from "node:test";
import assert from "node:assert/strict";
import { change, column, foldTail, lastN, niceScale, shares, smoothPath, spread, sum, trend } from "../../app/admin/_lib/stats.ts";

const days = (values: number[]) => values.map((v, i) => ({ day: `2026-10-${String(i + 1).padStart(2, "0")}`, views: v }));

test("niceScale: clean steps of 1, 2, 2.5 or 5, starting at zero", () => {
  assert.deepEqual(niceScale(7), { max: 8, ticks: [0, 2, 4, 6, 8] });
  assert.deepEqual(niceScale(8), { max: 8, ticks: [0, 2, 4, 6, 8] });
  assert.deepEqual(niceScale(100), { max: 100, ticks: [0, 25, 50, 75, 100] });
  assert.deepEqual(niceScale(0.37), { max: 0.4, ticks: [0, 0.1, 0.2, 0.3, 0.4] });
});

test("niceScale: counts get whole steps, and an empty series still has an axis", () => {
  assert.deepEqual(niceScale(3, { integer: true }), { max: 3, ticks: [0, 1, 2, 3] });
  assert.deepEqual(niceScale(1, { integer: true }), { max: 1, ticks: [0, 1] });
  assert.deepEqual(niceScale(0), { max: 1, ticks: [0, 1] });
  assert.deepEqual(niceScale(Number.NaN), { max: 1, ticks: [0, 1] });
  for (const peak of [1, 5, 9, 13, 47, 99, 101, 999, 1234, 98765]) {
    const s = niceScale(peak, { integer: true });
    assert.ok(s.max >= peak, `axis for ${peak} reaches it`);
    assert.ok(s.ticks.length >= 2 && s.ticks.length <= 6, `axis for ${peak} has a readable number of ticks`);
    assert.ok(s.ticks.every(Number.isInteger), `axis for ${peak} has whole ticks`);
  }
});

test("lastN, sum and column read a series oldest first", () => {
  const d = days([1, 2, 3, 4, 5]);
  assert.deepEqual(lastN(d, 2).map(r => r.views), [4, 5]);
  assert.equal(lastN(d, 10).length, 5);
  assert.equal(sum(d, "views"), 15);
  assert.deepEqual(column(d, "views"), [1, 2, 3, 4, 5]);
  assert.equal(sum(d, "missing"), 0);
});

test("change compares the last n days with the n before, only when both fit", () => {
  const d = days([...Array(16).fill(1), 5, 5, 5, 5, 5, 5, 5, ...Array(7).fill(10)]);
  assert.deepEqual(change(d, "views", 7), { current: 70, previous: 35, ratio: 1 });
  assert.equal(change(d, "views", 30).previous, null);
  assert.equal(change(d, "views", 30).current, 16 + 35 + 70);
  const quiet = days([...Array(23).fill(0), 1, 0, 0, 0, 2, 0, 0]);
  assert.deepEqual(change(quiet, "views", 7), { current: 3, previous: 0, ratio: null });
});

test("trend says how a change reads on a tile", () => {
  assert.equal(trend({ current: 5, previous: null, ratio: null }), null);
  assert.deepEqual(trend({ current: 12, previous: 10, ratio: 0.2 }), { text: "20%", dir: "up", good: true });
  assert.deepEqual(trend({ current: 8, previous: 10, ratio: -0.2 }), { text: "20%", dir: "down", good: false });
  assert.deepEqual(trend({ current: 8, previous: 10, ratio: -0.2 }, false), { text: "20%", dir: "down", good: true });
  assert.deepEqual(trend({ current: 5, previous: 0, ratio: null }), { text: "+5 from 0", dir: "up", good: true });
  assert.deepEqual(trend({ current: 0, previous: 0, ratio: null }), { text: "No change", dir: "flat", good: null });
  assert.deepEqual(trend({ current: 1001, previous: 1000, ratio: 0.001 }), { text: "No change", dir: "flat", good: null });
  assert.equal(trend({ current: 0, previous: 0, ratio: 0.0444 })?.text, "4.4%");
});

test("shares always add up to 100", () => {
  assert.deepEqual(shares([1, 1, 1]), [34, 33, 33]);
  assert.deepEqual(shares([2, 1]), [67, 33]);
  assert.deepEqual(shares([0, 0]), [0, 0]);
  assert.deepEqual(shares([5, -3]), [100, 0]);
  for (const v of [[1, 2, 3, 4], [7, 0, 0, 1], [999, 1, 1], [3, 3, 3, 3, 3, 3, 3]]) {
    assert.equal(shares(v).reduce((a, b) => a + b, 0), 100, `shares of ${v}`);
  }
});

test("foldTail folds the rest into one row, but never a single row", () => {
  const rows = [5, 4, 3, 2, 1].map((n, i) => ({ name: `r${i}`, n }));
  assert.deepEqual(foldTail(rows, 2, n => ({ name: "Other", n })).map(r => [r.name, r.n]), [["r0", 5], ["r1", 4], ["Other", 6]]);
  assert.equal(foldTail(rows, 4, n => ({ name: "Other", n })).length, 5);
  const zeros = [3, 0, 0].map((n, i) => ({ name: `z${i}`, n }));
  assert.deepEqual(foldTail(zeros, 1, n => ({ name: "Other", n })).map(r => r.name), ["z0"]);
});

test("spread picks evenly spaced labels, always the first and last", () => {
  assert.deepEqual(spread(30, 5), [0, 7, 15, 22, 29]);
  assert.deepEqual(spread(3, 5), [0, 1, 2]);
  assert.deepEqual(spread(14, 3), [0, 7, 13]);
  assert.deepEqual(spread(0, 5), []);
});

test("smoothPath passes through every point and never overshoots the data", () => {
  assert.equal(smoothPath([]), "");
  assert.equal(smoothPath([[1, 2]]), "M1,2");
  const flat = smoothPath([[0, 10], [10, 10], [20, 10]]);
  const ys = (d: string) => [...d.matchAll(/[\d.]+,([\d.]+)/g)].map(m => Number(m[1]));
  assert.ok(ys(flat).every(y => y === 10), "a flat series stays flat");
  const rising: [number, number][] = [[0, 100], [10, 90], [20, 20], [30, 15], [40, 15], [50, 0]];
  const d = smoothPath(rising);
  assert.ok(ys(d).every(y => y >= 0 && y <= 100), "no control point leaves the data's range");
  for (const [x, y] of rising) assert.ok(d.includes(`${x},${y}`), `passes through ${x},${y}`);
});
