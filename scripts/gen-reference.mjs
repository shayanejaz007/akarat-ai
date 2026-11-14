// Mirrors data/market.js into lib/reference.ts.
//
// data/market.js is a browser ES module; the server-rendered pages need the
// same city / neighbourhood / type / amenity names as typed values. Rather
// than maintain two copies by hand, this regenerates the typed one. Runs as
// part of prebuild, so the two cannot drift.
import { writeFile } from 'node:fs/promises';

const m = await import('../data/market.js');
// Every place, for names: a listing may be in any town of data/locations.js.
const all = await import('../data/locations.js');
const pick = (arr) => (arr || []).map((x) => ({ id: x.id, en: x.en, ar: x.ar }));
// Neighbourhoods keep their city: the AI advisor resolves an area to the city
// it belongs to, and needs the pair without loading the browser module.
const pickHoods = (arr) => (arr || []).map((x) => ({ id: x.id, en: x.en, ar: x.ar, city: x.city }));

const body = `/**
 * Reference lists for the server-rendered pages.
 *
 * GENERATED from data/market.js by scripts/gen-reference.mjs — do not edit.
 */
export type Ref = { id: string; en: string; ar: string };
export type Hood = Ref & { city: string };

export const CITIES: Ref[] = ${JSON.stringify(pick(m.CITIES), null, 2)};

export const NEIGHBORHOODS: Hood[] = ${JSON.stringify(pickHoods(m.NEIGHBORHOODS), null, 2)};

export const TYPES: Ref[] = ${JSON.stringify(pick(m.TYPES), null, 2)};

export const AMENITIES: Ref[] = ${JSON.stringify(pick(m.AMENITIES), null, 2)};

/* Every governorate, city and neighbourhood in data/locations.js, for
   naming a listing's place. CITIES and NEIGHBORHOODS above stay the
   hand-checked set: the AI advisor lists those in its tool definitions,
   and a list of every village in the country would not fit there. */
export const GOVERNORATES: Ref[] = ${JSON.stringify(pick(all.GOVERNORATES))};

export const ALL_CITIES: (Ref & { gov: string })[] = ${JSON.stringify(all.CITIES.map(c => ({ id: c.id, en: c.en, ar: c.ar, gov: c.gov })))};

export const ALL_NEIGHBORHOODS: Hood[] = ${JSON.stringify(all.NEIGHBORHOODS.map(n => ({ id: n.id, en: n.en, ar: n.ar, city: n.city })))};
`;

await writeFile(new URL('../lib/reference.ts', import.meta.url), body);
console.log(
  `gen-reference: lib/reference.ts written (${pick(m.CITIES).length} cities, `
  + `${pick(m.NEIGHBORHOODS).length} neighbourhoods, ${pick(m.TYPES).length} types, `
  + `${pick(m.AMENITIES).length} amenities; ${all.CITIES.length} + ${all.NEIGHBORHOODS.length} places for names)`
);
