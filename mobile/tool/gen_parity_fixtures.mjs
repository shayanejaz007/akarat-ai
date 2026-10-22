// Generates the fixtures the Dart parity tests compare against.
//
// The mobile app re-implements four pieces of the website's client logic in
// Dart: query parsing and ranking (lib/aisearch.js), location blurring and
// area snapping (lib/geo.js), portal deep links (lib/providers.js) and phone
// normalisation (lib/phone.js). This script runs the website's own JavaScript
// over a fixed set of inputs and writes what it returns, so `flutter test`
// fails the moment the two implementations disagree.
//
// Run from the mobile/ directory whenever any of those files change:
//
//   node tool/gen_parity_fixtures.mjs
//
// It reads the website's modules straight from the repository root and
// writes test/fixtures/*.json. Nothing here touches a network or a database.

import { writeFileSync, mkdirSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const root = join(here, '..', '..');
const out = join(here, '..', 'test', 'fixtures');
mkdirSync(out, { recursive: true });

const load = p => import(pathToFileURL(join(root, p)).href);
const ai = await load('lib/aisearch.js');
const geo = await load('lib/geo.js');
const providers = await load('lib/providers.js');
const phone = await load('lib/phone.js');
const market = await load('data/market.js');

const write = (name, data) =>
  writeFileSync(join(out, name), JSON.stringify(data, null, 2) + '\n', 'utf8');

/* ── reference data ──────────────────────────────────────────────────── */
// lib/shared/reference/market_data.dart is a hand-kept copy of this.
write('market.json', {
  CITIES: market.CITIES,
  NEIGHBORHOODS: market.NEIGHBORHOODS,
  AMENITIES: market.AMENITIES,
  TYPES: market.TYPES,
  SOURCE_CONFIDENCE: market.SOURCE_CONFIDENCE
});

/* ── query parsing ───────────────────────────────────────────────────── */

const QUERIES = [
  'Find me a 3-bedroom apartment in Abdoun under 150,000 JOD.',
  'Show me villas in Amman with a garden and parking.',
  'بدي شقة بعمان غرفتين وبسعر أقل من ٨٠ ألف دينار',
  'A four-bedroom villa in Abdoun with a garden, under 900,000 JOD.',
  'apartment for rent in Sweifieh 500 JOD per month',
  'flat in Khalda between 100k and 200k',
  'studio for rent in Jabal Amman',
  'warehouse in Zarqa',
  'penthouse in Dabouq with pool but no garden',
  'land in Rabieh at least 500 sqm',
  'شقة للإيجار في الصويفية ٣ غرف نوم',
  'فيلا للبيع في عبدون مع مسبح وحديقة بحدود مليون دينار',
  'max 300 sqm office in Shmeisani',
  'under 200,000, actually make it 250,000',
  'house in Irbid 2 bathrooms',
  'chalet at the Dead Sea with sea view',
  'only on this website apartments in amman',
  'شقة مفروشة في الجبيهة بالشهر',
  '3 bed 2 bath apartment in Jabal Al Hussein under 120k',
  'شاليه في البحر الميت',
  'مستودع في الزرقاء',
  'ستوديو للإيجار',
  'أرض في مادبا من 50 الف الى 80 الف',
  'villa in Aqaba over 500,000 JOD',
  'apartment Tla Al Ali 2 bedrooms rent 400 JOD/mo',
  'shop for sale downtown',
  'farm in Jerash',
  'Rabieh apartment',
  'Al Rabieh apartment for sale 1.5m',
  'building in Abdali',
  'apartment in amman with elevator and balcony, not furnished',
  'شقة ثلاث غرف في خلدا مع مصعد وبدون مسبح',
  'I want to buy a home in Fuheis with solar heating, budget 180k',
  'Apartment in Irbid near Yarmouk University for rent monthly',
  'shopping centre unit in Amman',
  'luxury modern villa in Dabouq',
  'quiet investment flat',
  'أبحث عن بيت في السلط أكثر من ١٠٠ ألف دينار',
  'apartment with 2 bedrooms in Wasfi Al Tal'
];

const parse = QUERIES.map(q => ({ input: q, previous: null, result: ai.parseQuery(q, null) }));

// Refinement: each turn reads on top of the last turn's constraints, the way
// the search screen behaves when someone keeps typing.
const chains = [
  ['apartment for sale in Abdoun under 200k', 'raise the budget to 300,000', 'only Sweifieh', 'make it 3 bedrooms'],
  ['villa in Amman', 'with a pool', 'no pool', 'خليها 500 ألف']
];
for (const chain of chains) {
  let prev = null;
  for (const q of chain) {
    const result = ai.parseQuery(q, prev);
    parse.push({ input: q, previous: prev, result });
    prev = result.constraints;
  }
}
write('parse_query.json', parse);

/* ── ranking and explanations ────────────────────────────────────────── */

const fmt = (n, deal) => {
  if (n == null) return 'Not provided';
  const s = n.toLocaleString('en-US');
  return deal === 'rent' ? `${s} JOD/mo` : `${s} JOD`;
};

const ITEMS = [
  { id: 'a', deal: 'sale', type: 'apartment', city: 'amman', hood: 'abdoun', price: 140000, beds: 3, baths: 2, area: 180, amen: ['parking', 'elevator'], days: 3 },
  { id: 'b', deal: 'sale', type: 'apartment', city: 'amman', hood: 'sweifieh', price: 160000, beds: 2, baths: 2, area: 150, amen: ['balcony'], days: 20 },
  { id: 'c', deal: 'sale', type: 'villa', city: 'amman', hood: 'dabouq', price: 900000, beds: 5, baths: 5, area: 600, amen: ['garden', 'pool', 'parking'], days: 45 },
  { id: 'd', deal: 'rent', type: 'apartment', city: 'amman', hood: null, price: 500, beds: 3, baths: null, area: null, amen: [], days: 0 },
  { id: 'e', deal: 'sale', type: 'land', city: 'salt', hood: null, price: 30000, beds: null, baths: null, area: 900, amen: [], days: 120 },
  { id: 'x', source: 'opensooq', kind: 'known_marketplace', deal: 'sale', type: 'apartment', city: 'amman', hood: 'abdoun', price: 155000, beds: 3, baths: null, area: null, amen: [], checked: 2 },
  { id: 'y', source: '2 sources', kind: 'known_marketplace', deal: 'sale', type: 'apartment', city: 'amman', hood: 'khalda', price: null, beds: null, baths: null, area: null, amen: [], checked: null }
];

const score = [];
for (const entry of parse.slice(0, 20)) {
  const c = entry.result.constraints;
  for (const it of ITEMS) {
    score.push({
      constraints: c,
      item: it,
      score: ai.scoreListing(it, c),
      explain_en: ai.explain(it, c, fmt, 'en'),
      explain_ar: ai.explain(it, c, fmt, 'ar')
    });
  }
}
write('score_listing.json', score);

/* ── location privacy and snapping ───────────────────────────────────── */

const POINTS = [
  [31.936, 35.879], [31.9493, 35.8671], [31.987654, 35.826543], [32.556, 35.847],
  [29.532, 35.006], [31.502, 35.583], [30.322, 35.478], [32.0711, 36.0882],
  [31.95, 35.93], [31.8, 35.9], [32.343, 36.208], [31.123456, 35.654321],
  [29.4, 34.98], [32.6, 36.0], [31.0, 36.5], [31.963, 35.93]
];
write('geo_blur.json', POINTS.map(([lat, lng]) => ({ lat, lng, out: geo.blur(lat, lng) })));
write('geo_nearest.json', POINTS.map(([lat, lng]) => ({
  lat, lng, out: geo.nearestArea(market, { lat, lng })
})));

/* ── portal deep links ───────────────────────────────────────────────── */

const LINK_CASES = parse.slice(0, 16).map(p => p.result.constraints);
const links = [];
for (const c of LINK_CASES) {
  for (const lang of ['en', 'ar']) {
    links.push({
      constraints: c, lang,
      searches: providers.buildExternalSearches(c, lang),
      describe: providers.describeQuery(c, lang)
    });
  }
}
write('portal_links.json', links);

/* ── phone numbers ───────────────────────────────────────────────────── */

const PHONES = [
  ['0791234567', 'jo'], ['791234567', 'jo'], ['+962 79 123 4567', 'jo'], ['00962791234567', 'jo'],
  ['٠٧٩١٢٣٤٥٦٧', 'jo'], ['07912345', 'jo'], ['0501234567', 'sa'], ['55123456', 'kw'],
  ['(415) 555-2671', 'us'], ['07911 123456', 'gb'], ['', 'jo'], ['abc', 'jo']
];
write('phone.json', PHONES.map(([input, country]) => ({
  input, country,
  e164: phone.toE164(input, country),
  pretty: phone.pretty(input, country)
})));

/* ── payload codec ───────────────────────────────────────────────────── */
// The browser's packPayload uses CompressionStream, which Node also has.
const sb = await load('lib/supabase.js');
const samplePayload = {
  amenities: ['garden', 'parking'],
  description_en: 'Bright corner apartment with a view over the valley.',
  description_ar: 'شقة زاوية مشمسة بإطلالة على الوادي.',
  images: [
    { url: 'https://example.invalid/a.jpg', path: 'user/a.jpg', type: 'image' },
    { url: 'https://example.invalid/b.mp4', path: 'user/b.mp4', type: 'video' }
  ],
  contact: { phone: '+962791234567', whatsapp: true, messaging: true }
};
const packed = await sb.packPayload(samplePayload);
write('payload.json', {
  object: samplePayload,
  packed: packed.payload_gz,
  payload_bytes: packed.payload_bytes,
  raw_bytes: packed.raw_bytes
});

console.log(`fixtures written to ${out}`);
