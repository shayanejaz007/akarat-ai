// How complete and useful a listing is, 0–100. Plain functions with no I/O:
// the server (lib/listing-quality.ts) runs them on the stored row and
// payload, and the tests (tests/quality) run them on fixtures.
//
// The score rewards what helps someone decide to call: real photos, a proper
// description in both languages, the facts filled in, a place they can find
// and a price. It never looks at the price itself, the area or the owner, so
// a cheap flat in Zarqa can score as high as a villa in Abdoun.
//
// Owners cannot write the score (migration 0025). Change the weights here and
// the nightly maintenance run re-scores every listing at its next edit; run
// /api/admin/listings?rescore=all to redo them all at once.

export const QUALITY_PARTS = {
  photos: 25,       // 10 or more photos for full marks
  video: 5,         // any video clip
  description: 15,  // a description of 400+ characters, in either language
  languages: 10,    // title and description in both English and Arabic
  facts: 15,        // the facts that matter for this type of property
  location: 15,     // town, neighbourhood and a pin on the map
  price: 5,         // a published price, not "price on request"
  amenities: 5,     // three or more amenities ticked
  contact: 5        // a phone number
};

export const QUALITY_MAX = Object.values(QUALITY_PARTS).reduce((a, b) => a + b, 0);

// Which facts count, by type. Land and farms are about the plot; offices,
// shops and warehouses about the floor area; homes about the rooms.
const PLOT_TYPES = new Set(['land', 'farm']);
const COMMERCIAL_TYPES = new Set(['office', 'shop', 'warehouse']);

function factsFor(type) {
  if (PLOT_TYPES.has(type)) return ['land_sqm'];
  if (COMMERCIAL_TYPES.has(type)) return ['area_sqm', 'year_built'];
  return ['bedrooms', 'bathrooms', 'area_sqm', 'year_built'];
}

const isVideo = m => !!m && (m.type === 'video' || /\.(mp4|webm|mov|m4v)(\?|#|$)/i.test(String(m.url || '')));
const text = v => (typeof v === 'string' ? v.trim() : '');
const present = v => v !== null && v !== undefined && v !== '' && Number(v) > 0;

/**
 * row: the properties columns (deal, property_type, city_id, neighborhood_id,
 * lat, lng, price_jod, price_on_request, bedrooms, bathrooms, area_sqm,
 * land_sqm, year_built, title_en, title_ar). payload: the unpacked payload
 * (description_en, description_ar, amenities, images, contact).
 *
 * Returns { score, parts, missing }: the total, the points per part, and the
 * parts that could still earn more, most points first.
 */
export function scoreListing(row = {}, payload = {}) {
  const media = Array.isArray(payload.images) ? payload.images.filter(m => m && m.url) : [];
  const photos = media.filter(m => !isVideo(m)).length;
  const videos = media.length - photos;

  const descEn = text(payload.description_en);
  const descAr = text(payload.description_ar);
  const longest = Math.max(descEn.length, descAr.length);

  const type = String(row.property_type || '');
  const facts = factsFor(type);
  const factsHave = facts.filter(k => present(row[k])).length;

  const amenities = Array.isArray(payload.amenities) ? payload.amenities.length : 0;
  const phone = text(payload.contact && payload.contact.phone);

  const P = QUALITY_PARTS;
  const parts = {
    photos: Math.min(P.photos, Math.round(photos * (P.photos / 10))),
    video: videos > 0 ? P.video : 0,
    description: longest >= 400 ? P.description : longest >= 200 ? 10 : longest >= 80 ? 5 : 0,
    languages:
      (text(row.title_en) && text(row.title_ar) ? 5 : 0) +
      (descEn.length >= 40 && descAr.length >= 40 ? 5 : 0),
    facts: Math.round((factsHave / facts.length) * P.facts),
    location:
      (row.city_id ? 5 : 0) +
      (row.neighborhood_id ? 5 : 0) +
      (Number.isFinite(Number(row.lat)) && Number.isFinite(Number(row.lng)) && row.lat != null && row.lng != null ? 5 : 0),
    price: !row.price_on_request && Number(row.price_jod) > 0 ? P.price : 0,
    // A plot of land has nothing to tick: it is not marked down for that.
    amenities: PLOT_TYPES.has(type) ? P.amenities : amenities >= 3 ? P.amenities : amenities > 0 ? 2 : 0,
    contact: phone ? P.contact : 0
  };

  const score = Math.max(0, Math.min(100, Object.values(parts).reduce((a, b) => a + b, 0)));
  const missing = Object.keys(parts)
    .filter(k => parts[k] < P[k])
    .sort((a, b) => (P[b] - parts[b]) - (P[a] - parts[a]));
  return { score, parts, missing };
}

/** A word for a score, for the admin panel and the owner's dashboard. */
export function scoreBand(score) {
  if (score == null) return 'unscored';
  if (score >= 80) return 'excellent';
  if (score >= 60) return 'good';
  if (score >= 40) return 'fair';
  return 'poor';
}
