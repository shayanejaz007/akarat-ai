// Mirrors data/market.js into lib/reference.ts.
//
// data/market.js is a browser ES module; the server-rendered pages need the
// same city / neighbourhood / type / amenity names as typed values. Rather
// than maintain two copies by hand, this regenerates the typed one. Runs as
// part of prebuild, so the two cannot drift.
import { writeFile } from 'node:fs/promises';

const m = await import('../data/market.js');
const pick = (arr) => (arr || []).map((x) => ({ id: x.id, en: x.en, ar: x.ar }));

const body = `/**
 * Reference lists for the server-rendered pages.
 *
 * GENERATED from data/market.js by scripts/gen-reference.mjs — do not edit.
 */
export type Ref = { id: string; en: string; ar: string };

export const CITIES: Ref[] = ${JSON.stringify(pick(m.CITIES), null, 2)};

export const NEIGHBORHOODS: Ref[] = ${JSON.stringify(pick(m.NEIGHBORHOODS), null, 2)};

export const TYPES: Ref[] = ${JSON.stringify(pick(m.TYPES), null, 2)};

export const AMENITIES: Ref[] = ${JSON.stringify(pick(m.AMENITIES), null, 2)};
`;

await writeFile(new URL('../lib/reference.ts', import.meta.url), body);
console.log(
  `gen-reference: lib/reference.ts written (${pick(m.CITIES).length} cities, `
  + `${pick(m.NEIGHBORHOODS).length} neighbourhoods, ${pick(m.TYPES).length} types, `
  + `${pick(m.AMENITIES).length} amenities)`
);
