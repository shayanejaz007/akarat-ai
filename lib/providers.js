// External market discovery.
//
// A browser cannot fetch third-party listing pages directly: CORS blocks it,
// and scraping a portal needs server-side execution plus that portal's
// permission. Inventing listings to fill the gap would break the one promise
// this product makes, so we do not.
//
// What we can do honestly, today, with no credentials: translate the parsed
// constraints into REAL search URLs on the actual Jordanian portals. Every URL
// below follows a path pattern verified against the live site, so the link
// lands on that portal's own filtered results for exactly what the user asked.
//
// When the server-side adapters in app/api/ai/search are given credentials,
// those return individual normalised listings and this layer becomes the
// fallback rather than the primary path.

import { CITIES, NEIGHBORHOODS, TYPES } from '../data/market.js';

// Neighbourhood slugs confirmed against the live site. Not derived from our
// own names: Bayut renders Abdoun as "Abdun", so every entry has to be seen
// before it is trusted. An unmapped hood falls back to city level and is
// reported as dropped rather than quietly ignored.
const BAYUT_HOODS = {
  jabalamman: 'jabal-amman'
};

// Portals whose URL grammar we have confirmed. `coverage` states plainly how
// much of the user's brief the link carries, so the UI never overclaims.
const PROVIDERS = [
  {
    id: 'opensooq',
    name: 'OpenSooq Jordan',
    kind: 'known_marketplace',
    cities: ['amman', 'irbid', 'zarqa', 'aqaba', 'madaba', 'salt', 'jerash'],
    build(c, lang) {
      const L = lang === 'ar' ? 'ar' : 'en';
      const city = this.cities.includes(c.city) ? '/' + c.city : '';
      // only 'apartments' is confirmed as a type segment; anything else uses
      // the generic property listing so the link cannot 404
      const kind = c.type === 'apartment' ? 'apartments' : 'property';
      const deal = c.deal === 'rent' ? 'rent' : 'sale';
      let url = `https://jo.opensooq.com/${L}${city}/property/${kind}-for-${deal}`;
      if (c.beds != null && c.beds >= 1 && c.beds <= 9) url += `/${c.beds}-bedrooms`;
      return url;
    },
    // no confirmed neighbourhood or price grammar, so neither is claimed
    carries: c => ({
      deal: !!c.deal,
      city: !!c.city && ['amman', 'irbid', 'zarqa', 'aqaba', 'madaba', 'salt', 'jerash'].includes(c.city),
      hood: false,
      type: c.type === 'apartment',
      beds: c.beds != null && c.beds >= 1 && c.beds <= 9,
      budget: false
    })
  },
  {
    id: 'bayut',
    name: 'Bayut Jordan',
    kind: 'known_marketplace',
    cities: ['amman', 'irbid', 'zarqa', 'aqaba'],
    build(c, lang) {
      const L = lang === 'ar' ? 'ar' : 'en';
      // they expose a country-wide scope, so an unknown city still lands well
      const city = this.cities.includes(c.city) ? c.city : 'jordan';
      const kind = c.type === 'apartment' ? 'apartments'
        : c.type === 'villa' ? 'villas'
        : 'properties';
      const deal = c.deal === 'rent' ? 'for-rent' : 'for-sale';
      // bedroom counts are a path prefix, confirmed for the apartments scope
      const beds = (c.type === 'apartment' && c.beds != null && c.beds >= 1 && c.beds <= 5)
        ? `${c.beds}-bedroom-` : '';
      const hood = BAYUT_HOODS[c.hood];
      // the hood form is a suffix on the listing path, e.g. apartments-for-rent-in-jabal-amman
      const tail = hood ? `${beds}${kind}-${deal}-in-${hood}` : `${beds}${kind}-${deal}`;
      return `https://www.bayut.jo/${L}/${city}/${tail}/`;
    },
    carries: c => ({
      deal: !!c.deal,
      city: !!c.city,
      hood: !!BAYUT_HOODS[c.hood],
      type: c.type === 'apartment' || c.type === 'villa',
      beds: c.type === 'apartment' && c.beds != null && c.beds >= 1 && c.beds <= 5,
      budget: false
    })
  }
];

function label(id, list, lang) {
  const row = list.find(x => x.id === id);
  return row ? (lang === 'ar' ? row.ar : row.en) : id;
}

// A plain-language description of the search, reused for the web-wide fallback.
export function describeQuery(c, lang) {
  const ar = lang === 'ar';
  const bits = [];
  if (c.beds != null) bits.push(ar ? `${c.beds} غرف نوم` : `${c.beds} bedroom`);
  if (c.type) bits.push(label(c.type, TYPES, lang));
  else bits.push(ar ? 'عقار' : 'property');
  bits.push(c.deal === 'rent' ? (ar ? 'للإيجار' : 'for rent') : (ar ? 'للبيع' : 'for sale'));
  if (c.hood) bits.push(label(c.hood, NEIGHBORHOODS, lang));
  if (c.city) bits.push(label(c.city, CITIES, lang));
  bits.push(ar ? 'الأردن' : 'Jordan');
  if (c.budgetMax) bits.push((ar ? 'أقل من ' : 'under ') + c.budgetMax.toLocaleString('en-US') + (ar ? ' دينار' : ' JOD'));
  return bits.join(' ');
}

// Returns one entry per approved source, each with a real, openable URL.
export function buildExternalSearches(c, lang) {
  if (!c) return [];
  const ar = lang === 'ar';

  // Every constraint the user actually stated, so the fraction has an honest
  // denominator. A dropped one has to show up somewhere the user can see it.
  const asked = {
    deal: !!c.deal, city: !!c.city, hood: !!c.hood,
    type: !!c.type, beds: c.beds != null, budget: !!c.budgetMax
  };
  const askedKeys = Object.keys(asked).filter(k => asked[k]);
  const nameOf = {
    deal: ar ? 'نوع العملية' : 'buy/rent',
    city: ar ? 'المدينة' : 'city',
    hood: c.hood ? label(c.hood, NEIGHBORHOODS, lang) : (ar ? 'المنطقة' : 'area'),
    type: ar ? 'نوع العقار' : 'property type',
    beds: ar ? 'غرف النوم' : 'bedrooms',
    budget: ar ? 'السعر' : 'price'
  };

  const out = PROVIDERS.map(p => {
    const carried = p.carries(c);
    const kept = askedKeys.filter(k => carried[k]);
    const dropped = askedKeys.filter(k => !carried[k]);
    return {
      id: p.id,
      name: p.name,
      kind: p.kind,
      url: p.build(c, lang),
      coverage: askedKeys.length ? `${kept.length}/${askedKeys.length}` : 'all',
      // name what the link cannot carry: the page promises we never widen a
      // search quietly, and a link that drops the area is exactly that
      note: dropped.length
        ? (ar ? `يتجاهل ${dropped.map(k => nameOf[k]).join('، ')}. حدّدها على الموقع`
              : `drops ${dropped.map(k => nameOf[k]).join(', ')}. Set it on their site`)
        : (ar ? 'يحمل طلبك كاملاً' : 'carries your full brief')
    };
  });

  // Search-engine discovery, per the architecture's last resort. This URL is
  // always valid and reaches pages no single portal covers: agency sites,
  // developer pages, broker listings.
  out.push({
    id: 'web',
    name: ar ? 'بحث عام في السوق' : 'Wider web search',
    kind: 'general_web_result',
    url: 'https://www.google.com/search?q=' + encodeURIComponent(describeQuery(c, lang)),
    carried: ['all'],
    coverage: ar ? 'كل الشروط' : 'full brief',    note: ar ? 'وكلاء ومطوّرون خارج المنصات' : 'agencies and developers beyond the portals'
  });

  return out;
}
