// Builds data/locations.js: Jordan's 12 governorates, its cities, towns and
// villages, and their neighbourhoods, in English and Arabic.
//
// Source: GeoNames (https://www.geonames.org), licensed CC BY 4.0. The
// hand-checked places in data/market.js (the "core" places search has always
// known) are kept exactly as they are, ids included, so every existing
// listing still points at a real place; GeoNames fills in everything else.
//
//   1. Download and unzip, into any folder:
//        https://download.geonames.org/export/dump/JO.zip
//        https://download.geonames.org/export/dump/alternatenames/JO.zip
//   2. node scripts/build-locations.mjs --main <folder>/JO.txt --alt <folder2>/JO.txt
//   3. node scripts/gen-locations-sql.mjs   (writes the migration)
//      node scripts/gen-reference.mjs       (and the typed copy; prebuild runs it)
//      cd mobile && node tool/gen_reference.mjs
//
// What it decides, and why:
//   - Governorates come from GeoNames' first-level divisions, which are
//     Jordan's 12 governorates.
//   - A populated place becomes a city (town, village) of its governorate.
//     Inside a big city's built-up area it is a neighbourhood of that city
//     instead (Sweileh is part of Amman, not a town of its own).
//   - GeoNames' "sections of a populated place" become neighbourhoods of the
//     nearest city in the same governorate.
//   - Duplicates are folded together: the same name (compared in Arabic and
//     in English, without articles, diacritics or "Hayy"/"حي") within a few
//     kilometres is one place, and its spellings become search aliases.
//   - A place with no Arabic name is left out: everything here is shown in
//     both languages.
//   - data/locations-fixes.js renames, re-parents or drops individual
//     GeoNames entries where the data is wrong.
import { readFileSync, writeFileSync } from 'node:fs';

const args = process.argv.slice(2);
const opt = name => { const i = args.indexOf(name); return i >= 0 ? args[i + 1] : null; };
const MAIN = opt('--main');
const ALT = opt('--alt');
if (!MAIN || !ALT) {
  console.error('Usage: node scripts/build-locations.mjs --main <geonames JO.txt> --alt <alternatenames JO.txt>');
  process.exit(1);
}

const market = await import('../data/market.js');
const { FIXES } = await import('../data/locations-fixes.js');

/* ── Governorates ─────────────────────────────────────────────────────── */

// GeoNames admin1 code → our id. The names are the official ones.
const GOVERNORATES = [
  { code: '16', id: 'amman',   en: 'Amman',   ar: 'عمّان',    lat: 31.95, lng: 35.93, alt: ['capital', 'amman governorate', 'العاصمة', 'محافظة العاصمة', 'عمان'] },
  { code: '18', id: 'irbid',   en: 'Irbid',   ar: 'إربد',     lat: 32.55, lng: 35.85, alt: ['erbid', 'irbed', 'اربد'] },
  { code: '17', id: 'zarqa',   en: 'Zarqa',   ar: 'الزرقاء',  lat: 32.07, lng: 36.09, alt: ['zarka', 'zarqaa'] },
  { code: '02', id: 'balqa',   en: 'Balqa',   ar: 'البلقاء',  lat: 32.04, lng: 35.73, alt: ['al balqa', 'balka', 'belqa'] },
  { code: '15', id: 'mafraq',  en: 'Mafraq',  ar: 'المفرق',   lat: 32.34, lng: 36.21, alt: ['al mafraq', 'mafrak'] },
  { code: '09', id: 'karak',   en: 'Karak',   ar: 'الكرك',    lat: 31.18, lng: 35.70, alt: ['al karak', 'kerak'] },
  { code: '22', id: 'jerash',  en: 'Jerash',  ar: 'جرش',      lat: 32.28, lng: 35.90, alt: ['jarash', 'gerasa'] },
  { code: '23', id: 'madaba',  en: 'Madaba',  ar: 'مادبا',    lat: 31.72, lng: 35.79, alt: ['madaba', 'mādabā', 'مأدبا'] },
  { code: '20', id: 'ajloun',  en: 'Ajloun',  ar: 'عجلون',    lat: 32.33, lng: 35.75, alt: ['ajlun', 'ajloon'] },
  { code: '21', id: 'aqaba',   en: 'Aqaba',   ar: 'العقبة',   lat: 29.53, lng: 35.01, alt: ['akaba', 'aqabah'] },
  { code: '19', id: 'maan',    en: 'Ma’an',   ar: 'معان',     lat: 30.19, lng: 35.73, alt: ['maan', 'ma an', "ma'an"] },
  { code: '12', id: 'tafilah', en: 'Tafilah', ar: 'الطفيلة',  lat: 30.84, lng: 35.60, alt: ['tafila', 'at tafilah', 'tafielah'] },
];
const govByCode = new Map(GOVERNORATES.map(g => [g.code, g]));

// The core cities' governorates. Every one is checked by hand.
const CORE_CITY_GOV = {
  amman: 'amman', zarqa: 'zarqa', irbid: 'irbid', aqaba: 'aqaba', salt: 'balqa', madaba: 'madaba',
  jerash: 'jerash', mafraq: 'mafraq', ajloun: 'ajloun', karak: 'karak', tafilah: 'tafilah', maan: 'maan',
  ramtha: 'irbid', russeifa: 'zarqa', sahab: 'amman', fuheis: 'balqa', mahis: 'balqa', deadsea: 'balqa',
  wadimusa: 'maan', wadirum: 'aqaba', azraq: 'zarqa', dhiban: 'madaba',
};

// How far a big city's built-up area reaches, in km from its centre. A
// populated place inside it is one of the city's neighbourhoods.
const URBAN_KM = { amman: 9, zarqa: 5, irbid: 5, aqaba: 5, salt: 3, madaba: 3, russeifa: 3, ramtha: 3, mafraq: 3 };

/* ── Folding names for comparison ─────────────────────────────────────── */

const ARABIC_MARKS = /[ً-ٰٟـ]/g;
function foldAr(s) {
  return String(s || '')
    .replace(ARABIC_MARKS, '')
    .replace(/[أإآٱ]/g, 'ا').replace(/ى/g, 'ي').replace(/ة/g, 'ه').replace(/ؤ/g, 'و').replace(/ئ/g, 'ي')
    .replace(/^(حي|منطقة|محافظة|قرية|ضاحية)\s+/, '')
    .replace(/(^|\s)ال/g, '$1')
    .replace(/\s+/g, '')
    .trim();
}
function foldEn(s) {
  return String(s || '')
    .normalize('NFKD').replace(/[̀-ͯ]/g, '')
    .toLowerCase()
    .replace(/[‘’`'ʿʾ]/g, '')
    .replace(/^(hayy|hay|mintaqat|mintaqa|qaryat)\s+/, '')
    .replace(/\b(al|el|ar|as|ash|at|ad|adh|az|an|ath|aş|ad-|al-|el-)[\s-]+/g, '')
    .replace(/[^a-z0-9]/g, '')
    .replace(/(.)\1+/g, '$1')
    .replace(/[aeiouy]/g, '');
}

function km(a, b) {
  const R = 6371, rad = x => (x * Math.PI) / 180;
  const dLat = rad(b.lat - a.lat), dLng = rad(b.lng - a.lng);
  const h = Math.sin(dLat / 2) ** 2 + Math.cos(rad(a.lat)) * Math.cos(rad(b.lat)) * Math.sin(dLng / 2) ** 2;
  return 2 * R * Math.asin(Math.sqrt(h));
}

/* ── Display names ────────────────────────────────────────────────────── */

const ARTICLE = /^(al|el|ar|as|ash|at|ad|adh|az|an|ath|az̧)$/i;
function cleanEn(name) {
  let s = String(name).normalize('NFKD').replace(/[̀-ͯ]/g, '');
  s = s.replace(/^(Hayy|Hay|Mintaqat)\s+/i, '');
  // An ayn or hamza mark at either end of a word goes; inside a word it is an apostrophe.
  s = s.replace(/(^|\s)[‘’`'ʿʾ]+/g, '$1').replace(/[‘’`'ʿʾ]+(\s|$)/g, '$1').replace(/[‘’`ʿʾ]/g, '’');
  const words = s.split(/\s+/);
  s = words.map((w, i) => {
    if (ARTICLE.test(w) && i < words.length - 1) return i === 0 ? w[0].toUpperCase() + w.slice(1).toLowerCase() : w.toLowerCase();
    return w ? w[0].toUpperCase() + w.slice(1) : w;
  }).join(' ');
  return s.replace(/\s+/g, ' ').trim();
}
function cleanAr(name) {
  return String(name).replace(/^(حي|منطقة)\s+/, '').replace(/\s+/g, ' ').trim();
}
const isArabic = s => /[؀-ۿ]/.test(s) && !/[A-Za-zÀ-ɏ]/.test(s);

function slug(en) {
  return foldEnId(en) || 'place';
}
function foldEnId(s) {
  return String(s).normalize('NFKD').replace(/[̀-ͯ]/g, '').toLowerCase()
    .replace(/[‘’`'ʿʾ]/g, '').replace(/[^a-z0-9]+/g, '-').replace(/^-+|-+$/g, '').slice(0, 40);
}

/* ── Read GeoNames ────────────────────────────────────────────────────── */

const rows = readFileSync(MAIN, 'utf8').split('\n').filter(Boolean).map(l => l.split('\t'));
const alts = new Map();
for (const line of readFileSync(ALT, 'utf8').split('\n')) {
  if (!line) continue;
  const f = line.split('\t');
  // altId, geonameId, isoLang, name, preferred, short, colloquial, historic
  if (f[7] === '1') continue; // historic names are not what people type
  if (!alts.has(f[1])) alts.set(f[1], []);
  alts.get(f[1]).push({ lang: f[2], name: f[3], preferred: f[4] === '1' });
}

function arabicName(id) {
  const list = (alts.get(id) || []).filter(a => a.lang === 'ar' && isArabic(a.name));
  const pick = list.find(a => a.preferred) || list[0];
  return pick ? cleanAr(pick.name) : null;
}
function aliasesOf(id, row, en, ar) {
  const out = new Set();
  const seenEn = new Set([foldEn(en)]);
  const seenAr = new Set([foldAr(ar)]);
  const add = raw => {
    const v = String(raw || '').trim();
    if (v.length < 3 || /^[A-Z]{2,4}$/.test(v)) return;
    if (isArabic(v)) {
      const f = foldAr(cleanAr(v));
      if (!f || seenAr.has(f)) return;
      seenAr.add(f);
      out.add(cleanAr(v));
    } else if (/^[\x20-\x7EÀ-ɏ‘’ʿʾ]+$/.test(v)) {
      const plain = cleanEn(v).toLowerCase();
      const letters = plain.replace(/[^a-z]/g, '');
      const vowels = letters.replace(/[^aeiou]/g, '').length;
      if (letters.length > 4 && vowels / letters.length < 0.24) return;
      if (/^(hy|mntqt|mhafzt)\b/.test(plain)) return;
      const f = foldEn(plain);
      if (!f || seenEn.has(f + plain)) return;
      seenEn.add(f + plain);
      if (plain !== en.toLowerCase()) out.add(plain);
    }
  };
  for (const a of alts.get(id) || []) if (['', 'en', 'ar', 'en-JO', 'ar-JO', 'translit'].includes(a.lang)) add(a.name);
  for (const a of String(row[3] || '').split(',')) add(a);
  return [...out].slice(0, 8);
}

const P = rows.filter(r => r[6] === 'P' && govByCode.has(r[10]));
const TOWN_CODES = new Set(['PPLC', 'PPLA', 'PPLA2', 'PPLA3', 'PPL', 'PPLL']);
const RANK = { PPLC: 0, PPLA: 1, PPLA2: 2, PPLA3: 3, PPL: 4, PPLL: 5, PPLX: 6 };

const raw = [];
for (const r of P) {
  const fix = FIXES[r[0]] || {};
  if (fix.drop) continue;
  const ar = fix.ar || arabicName(r[0]);
  if (!ar) continue;
  const en = fix.en || cleanEn(r[1]);
  if (!fix.en && / wa /i.test(en)) continue;
  const kind = fix.kind || (r[7] === 'PPLX' ? 'hood' : TOWN_CODES.has(r[7]) ? 'town' : null);
  if (!kind) continue;
  raw.push({
    gn: Number(r[0]), code: r[7], rank: RANK[r[7]] ?? 9, gov: govByCode.get(r[10]).id,
    en, ar, lat: Math.round(Number(r[4]) * 10000) / 10000, lng: Math.round(Number(r[5]) * 10000) / 10000,
    pop: Number(r[14] || 0), kind, alt: aliasesOf(r[0], r, en, ar), parent: fix.city || null,
  });
}

/* ── The core places, as they are ─────────────────────────────────────── */

const cities = market.CITIES.map(c => ({
  id: c.id, gov: CORE_CITY_GOV[c.id], en: c.en, ar: c.ar, lat: c.lat, lng: c.lng, alt: [...(c.alt || [])], core: 1, pop: 1e9,
}));
for (const c of cities) if (!c.gov) throw new Error(`No governorate for core city ${c.id}`);
const hoods = market.NEIGHBORHOODS.map(n => ({
  id: n.id, city: n.city, en: n.en, ar: n.ar, lat: n.lat, lng: n.lng, alt: [...(n.alt || [])], core: 1,
}));
const cityById = new Map(cities.map(c => [c.id, c]));
for (const h of hoods) h.gov = cityById.get(h.city).gov;

const sameAr = (a, b) => !!foldAr(a.ar) && foldAr(a.ar) === foldAr(b.ar);
const sameName = (a, b) => sameAr(a, b) || (foldEn(a.en).length > 2 && foldEn(a.en) === foldEn(b.en));
// Within `near` km on any name match, within `far` km when the Arabic names match.
const matches = (a, b, near, far) => { const d = km(a, b); return (d < near && sameName(a, b)) || (d < far && sameAr(a, b)); };
function absorb(into, from) {
  const have = new Set([into.en.toLowerCase(), into.ar, ...into.alt]);
  for (const v of [from.en.toLowerCase(), from.ar, ...from.alt]) {
    if (!have.has(v) && into.alt.length < 12) { into.alt.push(v); have.add(v); }
  }
  if (!into.gn && from.gn) into.gn = from.gn;
}

const usedCityIds = new Set(cities.map(c => c.id));
const usedHoodIds = new Set(hoods.map(h => h.id));
function uniqueId(base, gov, used) {
  for (const id of [base, `${base}-${gov}`, ...Array.from({ length: 20 }, (_, i) => `${base}-${gov}-${i + 2}`)]) {
    if (!used.has(id)) { used.add(id); return id; }
  }
  throw new Error(`No free id for ${base}`);
}

/* ── Towns: merge, urban areas, duplicates ────────────────────────────── */

const towns = raw.filter(p => p.kind === 'town').sort((a, b) => a.rank - b.rank || b.pop - a.pop);
const pending = [];
for (const t of towns) {
  // Already a core city or neighbourhood?
  const coreCity = cities.find(c => c.gov === t.gov && matches(c, t, 6, 10));
  if (coreCity) { absorb(coreCity, t); continue; }
  const coreHood = hoods.find(h => matches(h, t, 3, 5));
  if (coreHood) { absorb(coreHood, t); continue; }
  // Inside a big city's built-up area: one of its neighbourhoods.
  const urban = t.parent ? cityById.get(t.parent) : cities.find(c => URBAN_KM[c.id] && c.gov === t.gov && km(c, t) <= URBAN_KM[c.id]);
  if (urban) { pending.push({ ...t, kind: 'hood', parent: urban.id }); continue; }
  // The same village twice in GeoNames.
  const twin = cities.find(c => !c.core && c.gov === t.gov && matches(c, t, 4, 6));
  if (twin) { absorb(twin, t); continue; }
  const c = { id: uniqueId(slug(t.en), t.gov, usedCityIds), gov: t.gov, en: t.en, ar: t.ar, lat: t.lat, lng: t.lng, alt: t.alt, gn: t.gn, pop: t.pop, rank: t.rank };
  cities.push(c);
  cityById.set(c.id, c);
}

/* ── Neighbourhoods ───────────────────────────────────────────────────── */

const sections = [...pending, ...raw.filter(p => p.kind === 'hood')];
for (const s of sections) {
  const coreHood = hoods.find(h => matches(h, s, 3, 5));
  if (coreHood) { absorb(coreHood, s); continue; }
  let parent = s.parent ? cityById.get(s.parent) : null;
  if (!parent) {
    let best = null, bestKm = 1e9;
    for (const c of cities) {
      if (c.gov !== s.gov) continue;
      // A big city reaches further than a village.
      const reach = URBAN_KM[c.id] ? URBAN_KM[c.id] + 6 : 4;
      const d = km(c, s);
      if (d <= reach && d - (URBAN_KM[c.id] || 0) < bestKm) { best = c; bestKm = d - (URBAN_KM[c.id] || 0); }
    }
    parent = best;
  }
  if (!parent) continue;
  const twin = hoods.find(h => h.city === parent.id && matches(h, s, 2.5, 4));
  if (twin) { absorb(twin, s); continue; }
  if (sameName(parent, s) && km(parent, s) < 3) { absorb(parent, s); continue; }
  hoods.push({ id: uniqueId(slug(s.en), parent.id, usedHoodIds), city: parent.id, gov: parent.gov, en: s.en, ar: s.ar, lat: s.lat, lng: s.lng, alt: s.alt, gn: s.gn });
}

/* ── Same name, different place ───────────────────────────────────────── */

// Two villages called Al Faysaliyah in one governorate are two villages (one
// place listed twice was folded together above). All but the best known get
// the nearest bigger place after their name, so a list can tell them apart;
// the plain name still finds them, since it starts the new one.
function disambiguate(list, parentOf, landmarks) {
  const groups = new Map();
  for (const x of list) {
    const k = `${parentOf(x)}|${foldAr(x.ar)}`;
    if (!groups.has(k)) groups.set(k, []);
    groups.get(k).push(x);
  }
  let renamed = 0;
  for (const g of groups.values()) {
    if (g.length < 2) continue;
    g.sort((a, b) => (b.core || 0) - (a.core || 0) || (b.pop || 0) - (a.pop || 0) || (a.rank ?? 9) - (b.rank ?? 9));
    for (const x of g.slice(1)) {
      let best = null, bestKm = 1e9;
      for (const l of landmarks(x)) {
        if (l === x || foldAr(l.ar) === foldAr(x.ar)) continue;
        const d = km(l, x);
        if (d < bestKm) { best = l; bestKm = d; }
      }
      if (!best) continue;
      x.en = `${x.en} (near ${best.en})`;
      x.ar = `${x.ar} (قرب ${best.ar})`;
      renamed++;
    }
  }
  return renamed;
}
const major = c => c.core || (c.rank ?? 9) <= 3;
const renamedCities = disambiguate(cities, c => c.gov, x => cities.filter(c => c.gov === x.gov && major(c)));
const renamedHoods = disambiguate(hoods, h => h.city, x => {
  const near = hoods.filter(h => h.city === x.city && h.core);
  return near.length ? near : hoods.filter(h => h.city === x.city);
});

/* ── Write ────────────────────────────────────────────────────────────── */

const byName = (a, b) => (b.core || 0) - (a.core || 0) || (b.pop || 0) - (a.pop || 0) || a.en.localeCompare(b.en);
const govOrder = GOVERNORATES.map(g => g.id);
cities.sort((a, b) => govOrder.indexOf(a.gov) - govOrder.indexOf(b.gov) || byName(a, b));
hoods.sort((a, b) => a.city.localeCompare(b.city) || (b.core || 0) - (a.core || 0) || a.en.localeCompare(b.en));

const q = v => JSON.stringify(v);
const line = o => `  { ${Object.entries(o).filter(([, v]) => v !== undefined && v !== null && !(Array.isArray(v) && !v.length)).map(([k, v]) => `${k}: ${q(v)}`).join(', ')} }`;
const out = `// GENERATED by scripts/build-locations.mjs. Do not edit by hand: fix a
// core place in data/market.js, or a GeoNames one in data/locations-fixes.js,
// and build again.
//
// Jordan's 12 governorates, ${cities.length} cities, towns and villages, and ${hoods.length}
// neighbourhoods, in English and Arabic, with the spellings people type.
// Places marked core are the hand-checked ones from data/market.js; the rest
// are from GeoNames (geonames.org), CC BY 4.0.

export const GOVERNORATES = [
${GOVERNORATES.map(g => line({ id: g.id, en: g.en, ar: g.ar, lat: g.lat, lng: g.lng, alt: g.alt })).join(',\n')}
];

export const CITIES = [
${cities.map(c => line({ id: c.id, gov: c.gov, en: c.en, ar: c.ar, lat: c.lat, lng: c.lng, alt: c.alt, core: c.core, gn: c.gn })).join(',\n')}
];

export const NEIGHBORHOODS = [
${hoods.map(h => line({ id: h.id, city: h.city, en: h.en, ar: h.ar, lat: h.lat, lng: h.lng, alt: h.alt, core: h.core, gn: h.gn })).join(',\n')}
];
`;
writeFileSync(new URL('../data/locations.js', import.meta.url), out);
const perGov = Object.fromEntries(govOrder.map(g => [g, cities.filter(c => c.gov === g).length]));
console.log(`data/locations.js: 12 governorates, ${cities.length} cities, ${hoods.length} neighbourhoods`);
console.log('cities per governorate:', JSON.stringify(perGov));
console.log(`told apart by a nearby place: ${renamedCities} cities, ${renamedHoods} neighbourhoods`);
