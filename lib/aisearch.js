// Deterministic query understanding + ranking. No model invention: the parser
// extracts constraints, the scorer weights retrieved facts only.

import { CITIES, NEIGHBORHOODS, AMENITIES, TYPES, SOURCE_CONFIDENCE } from '../data/market.js';

const AR_DIGITS = '٠١٢٣٤٥٦٧٨٩';

// Spelled-out counts. People type "four bedroom villa" as often as "4 bed".
// Longest first: 'غرفتين' must win before 'ست' can nibble at anything.
const WORD_NUMBERS = [
  ['غرفتين', '2 غرف'], ['غرفتان', '2 غرف'],
  ['three', 3], ['seven', 7], ['eight', 8], ['four', 4], ['five', 5],
  ['nine', 9], ['one', 1], ['two', 2], ['six', 6], ['ten', 10],
  ['واحدة', 1], ['ثلاث', 3], ['أربع', 4], ['اربع', 4],
  ['خمس', 5], ['ست', 6], ['سبع', 7], ['ثمان', 8], ['تسع', 9], ['عشر', 10]
].sort((a, b) => String(b[0]).length - String(a[0]).length);

const AR_LETTER = '\u0621-\u064A';

export function normalizeNumerals(s) {
  let out = s.replace(/[٠-٩]/g, d => String(AR_DIGITS.indexOf(d)));
  for (const [word, n] of WORD_NUMBERS) {
    if (/[\u0600-\u06FF]/.test(word)) {
      // \b is defined on [A-Za-z0-9_], so it never fires next to Arabic script.
      // Hand-roll the boundary: allow the common attached prefixes (بـ الـ وـ فـ
      // لـ كـ) so "بأربع" still reads as 4, but refuse to match mid-word, or
      // 'ست' eats مستودع/استوديو and 'ثلاث' eats ثلاثين.
      out = out.replace(
        new RegExp('(^|[^' + AR_LETTER + '])(بال|وال|فال|ال|ب|و|ف|ل|ك)?' + word + '(?![' + AR_LETTER + '])', 'g'),
        (_m, lead, prefix) => lead + (prefix || '') + n
      );
    } else {
      out = out.replace(new RegExp('\\b' + word + '\\b', 'gi'), String(n));
    }
  }
  return out;
}

// Units that mean the number is not a price. Without this, "max 300 sqm"
// becomes a 300 JOD budget and "make it 3 bedrooms" a 3 JOD one.
const NON_PRICE_UNIT = /^\s*(?:m2|m²|sqm|square\s*met(?:er|re)s?|متر|م٢|bed(?:room)?s?\b|bath(?:room)?s?\b|br\b|ba\b|غرف|حمام)/i;

function followedByArea(text, endIndex) {
  return NON_PRICE_UNIT.test(text.slice(endIndex));
}

// A money cue: either an explicit currency or a scale suffix.
const MONEY_CUE = /^\s*(?:jod|jd|dinars?|دينار|k\b|m\b|thousand|million|ألف|الف|مليون)/i;

export function detectLang(s) {
  return /[\u0600-\u06FF]/.test(s) ? 'ar' : 'en';
}

/* ── term matching ───────────────────────────────────────────────────────
   Everything below used to be `low.includes(name)`, which matches inside
   other words: "warehouse" scored as a house, "shopping centre" as a shop,
   "penthouse" as a house. Whole-word matching fixes all three at once.

   \b is defined over [A-Za-z0-9_] so it never fires beside Arabic script.
   Arabic terms get a hand-rolled boundary that still tolerates the attached
   article and prepositions (الـ بالـ وـ فـ لـ كـ). */
const RE_CACHE = new Map();

function termRegex(term) {
  let re = RE_CACHE.get(term);
  if (re) return re;
  const esc = term.replace(/[.*+?^${}()|[\]\\]/g, '\\$&').replace(/[\s’']+/g, "[\\s’']*");
  re = /[\u0600-\u06FF]/.test(term)
    ? new RegExp('(?:^|[^' + AR_LETTER + '])(?:بال|وال|فال|كال|لل|ال|ب|و|ف|ل|ك)?' + esc + '(?![' + AR_LETTER + '])')
    // optional plural: "villas", "offices", "shops"
    : new RegExp('\\b' + esc + '(?:e?s)?\\b', 'i');
  RE_CACHE.set(term, re);
  return re;
}

/**
 * Longest match wins, so "apartment building" reads as a building and
 * "warehouse" is never shortened to "house". Returns the id, or null.
 */
/**
 * Jordanian place names carry the definite article in their official form but
 * almost nobody types it: people search "Rabieh", not "Al Rabieh". Each name
 * therefore also matches with a leading Al/El stripped.
 */
function expandTerms(terms) {
  const out = [];
  for (const t of terms) {
    if (!t) continue;
    out.push(t);
    const bare = t.replace(/^(?:al|el)[\s-]+/i, '');
    if (bare !== t && bare.length > 2) out.push(bare);
  }
  return out;
}

function bestMatch(text, entries) {
  let bestId = null;
  let bestLen = 0;
  for (const e of entries) {
    for (const term of expandTerms(e.terms)) {
      if (!term || term.length <= bestLen) continue;
      if (termRegex(term).test(text)) { bestId = e.id; bestLen = term.length; break; }
    }
  }
  return bestId;
}

/**
 * What people actually type. Without these, "flat", "penthouse", "duplex",
 * "plot" and "showroom" all parsed to nothing at all.
 */
const TYPE_SYNONYMS = {
  apartment: ['apartment', 'apt', 'flat', 'condo', 'penthouse', 'duplex', 'studio apartment',
              'شقة', 'شقق', 'بنتهاوس', 'دوبلكس', 'ستوديو'],
  villa:     ['villa', 'townhouse', 'فيلا', 'فلل', 'فيلات', 'تاون هاوس'],
  house:     ['house', 'home', 'farmhouse', 'bungalow', 'بيت', 'منزل', 'دار', 'بيت مستقل'],
  land:      ['land', 'plot', 'parcel', 'lot', 'أرض', 'ارض', 'قطعة أرض', 'اراضي', 'أراضي'],
  office:    ['office', 'workspace', 'مكتب', 'مكاتب'],
  shop:      ['shop', 'store', 'showroom', 'retail unit', 'محل', 'محلات', 'معرض', 'محل تجاري'],
  building:  ['building', 'apartment building', 'block of flats', 'بناية', 'عمارة', 'بنايات'],
  chalet:    ['chalet', 'شاليه', 'شاليهات'],
  warehouse: ['warehouse', 'depot', 'مستودع', 'مخزن', 'مستودعات'],
  farm:      ['farm', 'farmland', 'orchard', 'مزرعة', 'مزارع']
};

function parseAmount(raw, tail) {
  let n = parseFloat(raw.replace(/,/g, ''));
  if (!isFinite(n)) return null;
  const t = (tail || '').toLowerCase();
  if (/^k\b|thousand|ألف|الف/.test(t)) n *= 1000;
  else if (/^m\b|million|مليون/.test(t)) n *= 1000000;
  return Math.round(n);
}

const DEAL_WORDS = {
  rent: [/\brent(al|ing)?\b/i, /\bto let\b/i, /\blease\b/i, /للإيجار/, /للايجار/, /استئجار/, /ايجار/, /إيجار/],
  sale: [/\bbuy\b/i, /\bfor sale\b/i, /\bpurchase\b/i, /\bown\b/i, /للبيع/, /شراء/, /اشتري/, /أشتري/, /تملك/]
};

const AMENITY_WORDS = {
  garden: [/garden/i, /yard/i, /حديقة/],
  pool: [/pool/i, /swimming/i, /مسبح/, /بركة/],
  parking: [/parking/i, /garage/i, /موقف/, /كراج/, /مواقف/],
  balcony: [/balcon/i, /terrace/i, /شرفة/, /بلكونة/, /تراس/],
  elevator: [/elevator/i, /\blift\b/i, /مصعد/, /اسانسير/],
  furnished: [/furnished/i, /مفروش/],
  security: [/security/i, /guard/i, /حراسة/, /أمن/],
  heating: [/heating/i, /تدفئة/],
  ac: [/\ba\/?c\b/i, /air condition/i, /تكييف/, /مكيف/],
  solar: [/solar/i, /شمسي/],
  storage: [/storage/i, /مستودع صغير/, /تخزين/],
  smart: [/smart home/i, /smart/i, /ذكي/],
  seaview: [/sea ?view/i, /إطلالة بحرية/, /اطلالة بحرية/, /على البحر/],
  roof: [/\broof\b/i, /rooftop/i, /رووف/, /سطح/]
};

const STYLE_WORDS = [
  [/modern|contemporary/i, 'modern'], [/حديث|عصري|مودرن/, 'modern'],
  [/new|brand ?new|newly built/i, 'new'], [/جديد|حديثة البناء/, 'new'],
  [/luxur|premium|high[- ]end/i, 'luxury'], [/فاخر|فخم/, 'luxury'],
  [/quiet|calm/i, 'quiet'], [/هادئ/, 'quiet'],
  [/investment|yield|rental return/i, 'investment'], [/استثمار|عائد/, 'investment']
];

export function parseQuery(input, previous) {
  const rawText = input.trim();
  const lang = detectLang(rawText);
  const text = normalizeNumerals(rawText);
  const low = text.toLowerCase();
  const c = previous ? JSON.parse(JSON.stringify(previous)) : {
    deal: null, city: null, hood: null, budgetMax: null, budgetMin: null,
    beds: null, baths: null, type: null, areaMin: null, amenities: [], styles: [],
    internalOnly: false
  };
  const changed = [];
  const set = (k, v) => { if (JSON.stringify(c[k]) !== JSON.stringify(v)) { c[k] = v; changed.push(k); } };

  // Negation is scoped to the words just before each feature, not applied to
  // the whole sentence. "a garden but no pool" must keep the garden.
  const NEGATOR = /(?:\bno\b|\bnot\b|\bwithout\b|\bremove\b|\bdrop\b|\bforget\b|\bdon'?t (?:need|want)\b|\bno longer\b|بدون|بلا|مش|ما بدي|ألغِ|الغي|احذف)[^.,;]{0,18}$/i;
  const negatedAt = index => NEGATOR.test(text.slice(Math.max(0, index - 28), index));

  for (const [deal, pats] of Object.entries(DEAL_WORDS))
    if (pats.some(p => p.test(text))) { set('deal', deal); break; }

  // Longest match again: "Jabal Al Hussein" must not lose to "Jabal Amman",
  // and a city named inside a district name must not steal the district.
  const hoodHit = bestMatch(text, NEIGHBORHOODS.map(n => ({
    id: n.id, terms: [n.en, n.ar, ...(n.alt || [])]
  })));
  if (hoodHit) {
    const n = NEIGHBORHOODS.find(x => x.id === hoodHit);
    set('hood', n.id); set('city', n.city);
  }
  const cityHit = bestMatch(text, CITIES.map(ct => ({
    id: ct.id, terms: [ct.en, ct.ar, ...(ct.alt || [])]
  })));
  if (cityHit) {
    // An explicit city that contradicts the district wins; the district is
    // dropped rather than left pointing somewhere else.
    if (c.hood) {
      const h = NEIGHBORHOODS.find(n => n.id === c.hood);
      if (h && h.city !== cityHit) set('hood', null);
    }
    set('city', cityHit);
  }

  const typeHit = bestMatch(text, TYPES.map(t => ({
    id: t.id,
    terms: [t.en, t.ar, ...(TYPE_SYNONYMS[t.id] || [])]
  })));
  if (typeHit) set('type', typeHit);
  if (termRegex('studio').test(text) || termRegex('ستوديو').test(text)) {
    set('type', 'apartment'); set('beds', 1);
  }

  // budget. Ranges first: "between 100,000 and 200,000" sets both ends.
  const range = /(?:between|from|بين|من)\s*([\d.,]+)\s*(k|m|thousand|million|ألف|الف|مليون)?\s*(?:and|to|until|[-–]|إلى|الى|و)\s*([\d.,]+)\s*(k|m|thousand|million|ألف|الف|مليون)?/i.exec(text);
  if (range && !followedByArea(text, range.index + range[0].length)) {
    const lo = parseAmount(range[1], range[2]);
    const hi = parseAmount(range[3], range[4]);
    if (lo && hi) { set('budgetMin', Math.min(lo, hi)); set('budgetMax', Math.max(lo, hi)); }
  }

  if (!range) {
    const budget = /(?:under|below|max(?:imum)?|up to|less than|budget(?: is| of)?|أقل من|اقل من|بحدود|ميزانيتي|حتى|لغاية)\s*(?:jod|jd|دينار)?\s*([\d.,]+)\s*(k|m|thousand|million|ألف|الف|مليون)?/i.exec(text);
    if (budget && !followedByArea(text, budget.index + budget[0].length)) set('budgetMax', parseAmount(budget[1], budget[2]));
    const minB = /(?:over|above|at least|starting (?:from|at)|from|أكثر من|اكثر من|ابتداء من)\s*(?:jod|jd|دينار)?\s*([\d.,]+)\s*(k|m|thousand|million|ألف|الف|مليون)?\s*(?:jod|jd|دينار)/i.exec(text);
    if (minB) set('budgetMin', parseAmount(minB[1], minB[2]));
    if (!budget && !minB) {
      const bare = /([\d.,]+)\s*(k|m|thousand|million|ألف|الف|مليون)?\s*(?:jod|jd|dinars?|دينار)/i.exec(text);
      if (bare) set('budgetMax', parseAmount(bare[1], bare[2]));
    }
  }

  // Mid-sentence corrections: "under 200,000, actually make it 250,000".
  // The number must read as money, or "make it 3 bedrooms" sets a 3 JOD budget.
  const revise = /(?:increase|raise|bump|actually|instead|change (?:it )?to|make it)\D{0,18}?([\d.,]+)\s*(k|m|thousand|million|ألف|الف|مليون)?|(?:ارفع|زد|خليها)\D{0,18}?([\d.,]+)\s*(ألف|الف|مليون)?/i.exec(text);
  if (revise) {
    const end = revise.index + revise[0].length;
    const tail = text.slice(end);
    const scaled = !!(revise[2] || revise[4]);
    const v = parseAmount(revise[1] || revise[3], revise[2] || revise[4]);
    // a bare number only counts as money when it is too large to be a room count
    const plausible = scaled || MONEY_CUE.test(tail) || (v != null && v >= 1000);
    if (v && plausible && !followedByArea(text, end)) set('budgetMax', v);
  }

  // A monthly figure is a rent, whether or not the word "rent" appears.
  if (!c.deal && /(?:per|a|\/)\s*month|monthly|\/mo\b|شهري|بالشهر|شهريا/i.test(text)) set('deal', 'rent');

  const beds = /([\d]+)\s*(?:\+|or more)?\s*-?\s*(?:bed(?:room)?s?|br\b)|(?:غرف(?:ة)? نوم|غرف)\s*([\d]+)|([\d]+)\s*غرف/i.exec(text);
  if (beds) set('beds', parseInt(beds[1] || beds[2] || beds[3], 10));
  const baths = /([\d]+)\s*(?:\+)?\s*-?\s*(?:bath(?:room)?s?|ba\b)|(?:حمام(?:ات)?)\s*([\d]+)|([\d]+)\s*حمام/i.exec(text);
  if (baths) set('baths', parseInt(baths[1] || baths[2] || baths[3], 10));

  const area = /([\d,]+)\s*(?:m2|m²|sqm|square met(?:er|re)s?|متر)/i.exec(text);
  if (area) set('areaMin', parseInt(area[1].replace(/,/g, ''), 10));

  const amen = new Set(c.amenities);
  for (const [id, pats] of Object.entries(AMENITY_WORDS)) {
    for (const p of pats) {
      const m = p.exec(text);
      if (!m) continue;
      if (negatedAt(m.index)) amen.delete(id); else amen.add(id);
      break;
    }
  }
  set('amenities', [...amen]);

  const styles = new Set(c.styles);
  for (const [p, id] of STYLE_WORDS) if (p.test(text)) styles.add(id);
  set('styles', [...styles]);

  if (/only .*(this (web)?site|our marketplace|akarat)|فقط .*(الموقع|منصتنا)/i.test(text)) set('internalOnly', true);

  const missing = [];
  if (!c.deal) missing.push('deal');
  if (!c.city && !c.hood) missing.push('location');

  return { constraints: c, lang, changed, missing, text: rawText };
}

// areaMin was parsed and shown as a chip but carried no weight, so "at least
// 200 sqm" changed the displayed constraints and nothing else.
const WEIGHTS = { budget: 26, location: 20, beds: 15, baths: 10, type: 12, area: 8, amenities: 9, freshness: 5, source: 3 };

export function scoreListing(item, c) {
  const reasons = [];
  let got = 0, possible = 0;
  const add = (w, frac, reason, kind) => {
    possible += w; got += w * frac;
    if (reason) reasons.push({ text: reason, kind: kind || (frac >= 1 ? 'good' : frac > 0 ? 'ok' : 'bad') });
  };

  if (c.budgetMax) {
    const over = item.price / c.budgetMax;
    const f = over <= 1 ? 1 : over <= 1.05 ? 0.6 : over <= 1.15 ? 0.25 : 0;
    add(WEIGHTS.budget, f, null);
  }
  if (c.hood) add(WEIGHTS.location, item.hood === c.hood ? 1 : item.city === c.city ? 0.55 : 0, null);
  else if (c.city) add(WEIGHTS.location, item.city === c.city ? 1 : 0, null);

  if (c.beds != null) {
    const b = item.beds;
    add(WEIGHTS.beds, b == null ? 0.3 : b >= c.beds ? 1 : b === c.beds - 1 ? 0.4 : 0, null);
  }
  if (c.baths != null) {
    const b = item.baths;
    add(WEIGHTS.baths, b == null ? 0.3 : b >= c.baths ? 1 : b === c.baths - 1 ? 0.4 : 0, null);
  }
  if (c.type) add(WEIGHTS.type, item.type === c.type ? 1 : 0, null);
  if (c.areaMin != null) {
    const a = item.area;
    add(WEIGHTS.area, a == null ? 0.3 : a >= c.areaMin ? 1 : a >= c.areaMin * 0.85 ? 0.5 : 0, null);
  }
  if (c.amenities.length) {
    const have = c.amenities.filter(a => (item.amen || []).includes(a)).length;
    add(WEIGHTS.amenities, have / c.amenities.length, null);
  }
  const days = item.source ? (item.checked == null ? 90 : item.checked) : item.days;
  add(WEIGHTS.freshness, days <= 7 ? 1 : days <= 30 ? 0.7 : days <= 60 ? 0.4 : 0.15, null);
  add(WEIGHTS.source, item.source ? (SOURCE_CONFIDENCE[item.kind] || 0.5) : 1, null);

  const score = possible ? Math.round((got / possible) * 100) : 50;
  return Math.max(1, Math.min(100, score));
}

export function explain(item, c, fmt, lang) {
  const ar = lang === 'ar';
  const out = [];
  if (c.budgetMax) {
    if (item.price <= c.budgetMax) out.push({ kind: 'good', text: ar
      ? `${fmt(item.price, item.deal)}. داخل ميزانيتك ${fmt(c.budgetMax)}`
      : `${fmt(item.price, item.deal)}. Within your ${fmt(c.budgetMax)} budget` });
    else {
      const over = Math.round((item.price / c.budgetMax - 1) * 100);
      out.push({ kind: 'warn', text: ar
        ? `${fmt(item.price, item.deal)}. أعلى من ميزانيتك بنسبة ${over}%`
        : `${fmt(item.price, item.deal)}. ${over}% above your budget` });
    }
  }
  if (c.beds != null) {
    if (item.beds == null) out.push({ kind: 'bad', text: ar ? 'عدد غرف النوم غير متوفر من المصدر' : 'Bedrooms not provided by the source' });
    else if (item.beds > c.beds) out.push({ kind: 'good', text: ar
      ? `${item.beds} غرف نوم. أكثر من طلبك (${c.beds}+)`
      : `${item.beds} bedrooms. Exceeds your ${c.beds}+ requirement` });
    else if (item.beds === c.beds) out.push({ kind: 'good', text: ar
      ? `${item.beds} غرف نوم. مطابق تماماً`
      : `${item.beds} bedrooms. Exact match` });
    else out.push({ kind: 'warn', text: ar
      ? `${item.beds} غرف نوم. أقل بغرفة واحدة من طلبك`
      : `${item.beds} bedrooms. One short of your requirement` });
  }
  if (c.baths != null) {
    if (item.baths == null) out.push({ kind: 'bad', text: ar ? 'عدد الحمامات غير متوفر من المصدر' : 'Bathrooms not provided by the source' });
    else {
      const meets = item.baths >= c.baths;
      out.push({ kind: meets ? 'good' : 'warn', text: ar
        ? `${item.baths} حمام. ${meets ? 'يلبي' : 'أقل من'} طلبك (${c.baths}+)`
        : `${item.baths} bathrooms. ${meets ? 'Meets' : 'Below'} your ${c.baths}+ requirement` });
    }
  }
  if (c.areaMin != null) {
    if (item.area == null) out.push({ kind: 'bad', text: ar ? 'المساحة غير متوفرة من المصدر' : 'Area not provided by the source' });
    else {
      const meets = item.area >= c.areaMin;
      out.push({ kind: meets ? 'good' : 'warn', text: ar
        ? `${item.area} م². ${meets ? 'يلبي' : 'أقل من'} طلبك (${c.areaMin}+ م²)`
        : `${item.area} m². ${meets ? 'Meets' : 'Below'} your ${c.areaMin}+ m² requirement` });
    }
  }
  if (c.amenities.length) {
    const have = c.amenities.filter(a => (item.amen || []).includes(a));
    const miss = c.amenities.filter(a => !(item.amen || []).includes(a));
    // resolve through the same bilingual records the rest of the app uses
    const label = id => {
      const row = AMENITIES.find(a => a.id === id);
      if (!row) return id;
      return ar ? row.ar : row.en.toLowerCase();
    };
    if (have.length) out.push({ kind: 'good', text: ar
      ? `يتضمن ${have.map(label).join('، ')}`
      : `Has ${have.map(label).join(', ')}` });
    if (miss.length) out.push({ kind: item.source ? 'bad' : 'warn', text: ar
      ? `${miss.map(label).join('، ')} ${item.source ? 'غير مذكور من المصدر' : 'غير مذكور'}`
      : `${miss.map(label).join(', ')} ${item.source ? 'not listed by the source' : 'not listed'}` });
  }
  // An indexed row knows when the crawler last saw it, not when it was
  // published. Say which, so this never contradicts the card's own footer.
  if (item.source) {
    if (item.checked == null) out.push({ kind: 'bad', text: ar ? 'وقت آخر تحقق غير متوفر' : 'Last checked date not provided' });
    else out.push({
      kind: item.checked <= 7 ? 'good' : 'plain',
      text: item.checked === 0
        ? (ar ? 'تم التحقق من المصدر اليوم' : 'Checked on the source today')
        : (ar ? `تم التحقق من المصدر قبل ${item.checked} أيام` : `Checked on the source ${item.checked} days ago`)
    });
  } else if (item.days != null) {
    out.push({
      kind: item.days <= 14 ? 'good' : 'plain',
      text: item.days === 0
        ? (ar ? 'أُضيف اليوم' : 'Listed today')
        : (ar ? `أُضيف قبل ${item.days} أيام` : `Listed ${item.days} days ago`)
    });
  } else {
    out.push({ kind: 'bad', text: ar ? 'تاريخ الإضافة غير متوفر' : 'Listing date not provided' });
  }
  return out;
}
