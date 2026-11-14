// Jordan's places for pickers, filters and place names: governorates, then
// cities, towns and villages, then neighbourhoods (data/locations.js), with
// an admin's changes from the database laid over them.
//
// Search is forgiving in the ways people are: Arabic with or without the
// article, hamza or taa marbuta; English in any of the usual spellings
// ("Sweifieh", "Swaifieh", "Suwayfiyah"); and from any level, so typing an
// area finds the area with its city and governorate and nobody has to pick
// all three by hand. Pure: no DOM, no network. The website imports it, and
// tests/places runs it under Node.

const ARABIC_MARKS = /[ً-ٰٟـ]/g;
const ARABIC = /[؀-ۿ]/;

/** Arabic folded for comparison: no marks, one alef, no article, no spaces. */
export function foldAr(s) {
  return String(s || '')
    .replace(ARABIC_MARKS, '')
    .replace(/[أإآٱ]/g, 'ا').replace(/ى/g, 'ي').replace(/ة/g, 'ه').replace(/ؤ/g, 'و').replace(/ئ/g, 'ي').replace(/ء/g, '')
    .replace(/[^ء-ي\s]/g, ' ')
    .replace(/(^|\s)(حي|منطقة|ضاحية)(?=\s)/g, ' ')
    .replace(/(^|\s)(و?ب?ال)(?=\S{2})/g, '$1')
    .replace(/\s+/g, '');
}

/** English folded for comparison: lower case, no accents, articles or punctuation. */
export function foldEn(s) {
  return String(s || '')
    .normalize('NFKD').replace(/[̀-ͯ]/g, '')
    .toLowerCase()
    .replace(/[‘’`'ʿʾ]/g, '')
    .replace(/(^|[\s-])(al|el|ar|as|ash|at|ad|adh|az|an|ath)[\s-]+(?=\S)/g, '$1')
    .replace(/^(hayy|hay|mintaqat)\s+/, '')
    .replace(/[^a-z0-9]/g, '');
}

/** The consonants of a folded English name: what survives every transliteration. */
export function skeleton(folded) {
  return String(folded).replace(/(.)\1+/g, '$1').replace(/[aeiouyw]/g, '').replace(/(.)\1+/g, '$1');
}

const isArabic = s => ARABIC.test(String(s || ''));

function termsOf(x) {
  const en = new Set();
  const ar = new Set();
  for (const t of [x.en, x.ar, ...(x.alt || [])]) {
    if (!t) continue;
    if (isArabic(t)) { const f = foldAr(t); if (f) ar.add(f); }
    else { const f = foldEn(t); if (f) en.add(f); }
  }
  // Each skeleton keeps the name's first letter: consonants alone match too
  // much ("Abdoun" and "Biddin" are both b-d-n).
  const sk = new Set([...en].map(t => t[0] + skeleton(t)).filter(s => s.length >= 3));
  return { en: [...en], sk: [...sk], ar: [...ar] };
}

/**
 * The places, with lookups and search. `data` has GOVERNORATES, CITIES and
 * NEIGHBORHOODS in the shape of data/locations.js.
 */
export function createPlaces(data) {
  const governorates = (data.GOVERNORATES || []).filter(g => g.active !== false);
  const cities = (data.CITIES || []).filter(c => c.active !== false);
  const hoods = (data.NEIGHBORHOODS || []).filter(h => h.active !== false);
  const govById = new Map(governorates.map(g => [g.id, g]));
  const cityById = new Map(cities.map(c => [c.id, c]));
  const hoodById = new Map(hoods.map(h => [h.id, h]));
  // Switched-off places too, for naming: a listing made before an admin
  // switched its area off still says where it is.
  const anyGov = new Map((data.GOVERNORATES || []).map(g => [g.id, g]));
  const anyCity = new Map((data.CITIES || []).map(c => [c.id, c]));
  const anyHood = new Map((data.NEIGHBORHOODS || []).map(h => [h.id, h]));
  // A neighbourhood's governorate is its city's.
  const govOfCity = id => (anyCity.get(id) || {}).gov || null;

  let index = null;
  const build = () => {
    index = [
      // A city outranks the governorate named after it: "Irbid" is usually the city.
      ...governorates.map(x => ({ kind: 'gov', x, t: termsOf(x), weight: 8 })),
      ...cities.map(x => ({ kind: 'city', x, t: termsOf(x), weight: x.core ? 10 : 4 })),
      ...hoods.map(x => ({ kind: 'hood', x, t: termsOf(x), weight: x.core ? 9 : 2 })),
    ];
    return index;
  };

  const name = (x, lang) => (x ? (lang === 'ar' ? x.ar || x.en : x.en || x.ar) : '');

  function selection(kind, id) {
    if (kind === 'hood') {
      const h = hoodById.get(id);
      if (!h) return null;
      return { governorate_id: govOfCity(h.city), city_id: h.city, neighborhood_id: h.id };
    }
    if (kind === 'city') {
      const c = cityById.get(id);
      return c ? { governorate_id: c.gov, city_id: c.id, neighborhood_id: null } : null;
    }
    const g = govById.get(id);
    return g ? { governorate_id: g.id, city_id: null, neighborhood_id: null } : null;
  }

  /** Where a hit sits, for the line under its name: "Amman · Amman governorate". */
  function pathOf(kind, x, lang) {
    const ar = lang === 'ar';
    const govWord = g => (g ? (ar ? `محافظة ${g.ar}` : `${g.en} governorate`) : '');
    if (kind === 'hood') {
      const c = cityById.get(x.city);
      return [name(c, lang), govWord(govById.get(c && c.gov))].filter(Boolean).join(' · ');
    }
    if (kind === 'city') return govWord(govById.get(x.gov));
    return ar ? 'المحافظة كاملة' : 'The whole governorate';
  }

  /**
   * Places matching what was typed, best first. `kinds` limits the levels;
   * `gov` and `city` limit the area searched.
   */
  function search(query, { lang = 'en', kinds = null, gov = null, city = null, limit = 12 } = {}) {
    // null or absent: every level.
    let levels = Array.isArray(kinds) && kinds.length ? kinds : ['gov', 'city', 'hood'];
    let raw = String(query || '').trim();
    // "Irbid governorate", "محافظة إربد": the word asks for the governorate.
    const GOV_WORD = /(^|\s)(governorate|governate|gov|muhafazat|muhafazah|محافظة|محافظه)(?=\s|$)/gi;
    if (GOV_WORD.test(raw) && levels.includes('gov')) {
      raw = raw.replace(GOV_WORD, ' ').trim();
      levels = ['gov'];
    }
    if (!raw) return [];
    const ar = isArabic(raw);
    const q = ar ? foldAr(raw) : foldEn(raw);
    if (!q) return [];
    const qs = ar ? '' : q[0] + skeleton(q);
    const hits = [];
    for (const e of index || build()) {
      if (!levels.includes(e.kind)) continue;
      const egov = e.kind === 'gov' ? e.x.id : e.kind === 'city' ? e.x.gov : govOfCity(e.x.city);
      if (gov && egov !== gov) continue;
      if (city && (e.kind === 'gov' || (e.kind === 'city' ? e.x.id !== city : e.x.city !== city))) continue;
      let score = 0;
      for (const t of ar ? e.t.ar : e.t.en) {
        let s = 0;
        if (t === q) s = 100;
        else if (t.startsWith(q)) s = 80 - Math.min(20, t.length - q.length);
        else if (q.length >= 3 && t.includes(q)) s = 40;
        if (s > score) score = s;
      }
      // "Swaifieh" for "Sweifieh": the consonants agree.
      if (!ar && score < 60 && qs.length >= 4) {
        for (const t of e.t.sk) {
          if (t === qs) { score = Math.max(score, 70); break; }
          if (t.startsWith(qs)) score = Math.max(score, 55);
        }
      }
      if (!score) continue;
      hits.push({ e, score: score + e.weight });
    }
    hits.sort((a, b) => b.score - a.score || name(a.e.x, lang).length - name(b.e.x, lang).length);
    return hits.slice(0, limit).map(({ e, score }) => ({
      kind: e.kind,
      id: e.x.id,
      // A governorate says so, so "Aqaba" the city and "Aqaba governorate" read apart.
      label: e.kind === 'gov' ? (lang === 'ar' ? `محافظة ${e.x.ar}` : `${e.x.en} governorate`) : name(e.x, lang),
      path: pathOf(e.kind, e.x, lang),
      score,
      ...selection(e.kind, e.x.id),
    }));
  }

  return {
    governorates,
    cities,
    hoods,
    gov: id => govById.get(id) || null,
    city: id => cityById.get(id) || null,
    hood: id => hoodById.get(id) || null,
    citiesOf: govId => cities.filter(c => c.gov === govId),
    hoodsOf: cityId => hoods.filter(h => h.city === cityId),
    govOfCity,
    name,
    selection,
    search,
    /** "Abdoun · Amman", the city alone, or empty. Names switched-off places too. */
    placeLabel(cityId, hoodId, lang) {
      return [name(anyHood.get(hoodId), lang), name(anyCity.get(cityId), lang)].filter(Boolean).join(' · ');
    },
    /** A governorate's name, switched off or not: "Amman governorate" / "محافظة عمّان". */
    govLabel(id, lang) {
      const g = anyGov.get(id);
      if (!g) return '';
      return lang === 'ar' ? `محافظة ${g.ar}` : `${g.en} governorate`;
    },
    /** A listing in this place matches a filter on `sel` (any level, or none). */
    inArea(row, sel) {
      if (!sel) return true;
      if (sel.neighborhood_id) return row.neighborhood_id === sel.neighborhood_id;
      if (sel.city_id) return row.city_id === sel.city_id;
      if (sel.governorate_id) return govOfCity(row.city_id) === sel.governorate_id;
      return true;
    },
  };
}

/**
 * The bundled places with an admin's changes laid over them: rows from the
 * database's governorates, cities and neighborhoods tables that an admin
 * added or edited (edited = true), in the tables' own column names. A row
 * switched off hides the place; an unknown id adds one.
 */
export function withEdits(data, rows) {
  const out = {
    GOVERNORATES: [...(data.GOVERNORATES || [])],
    CITIES: [...(data.CITIES || [])],
    NEIGHBORHOODS: [...(data.NEIGHBORHOODS || [])],
  };
  const lay = (list, row, shape) => {
    const i = list.findIndex(x => x.id === row.id);
    const next = { ...(i >= 0 ? list[i] : {}), ...shape(row) };
    if (i >= 0) list[i] = next;
    else list.push(next);
  };
  const common = r => ({
    id: r.id, en: r.name_en, ar: r.name_ar, lat: r.lat, lng: r.lng,
    ...(Array.isArray(r.aliases) ? { alt: r.aliases } : {}), active: r.active !== false,
  });
  for (const r of (rows && rows.governorates) || []) lay(out.GOVERNORATES, r, r2 => common(r2));
  for (const r of (rows && rows.cities) || []) lay(out.CITIES, r, r2 => ({ ...common(r2), gov: r2.governorate_id }));
  for (const r of (rows && rows.neighborhoods) || []) lay(out.NEIGHBORHOODS, r, r2 => ({ ...common(r2), city: r2.city_id }));
  return out;
}
