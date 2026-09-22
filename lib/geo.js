// Google location services for the listing form.
//
// Three jobs, in order of how much they matter:
//
//   1. Turn a typed address into a point   (Places Autocomplete)
//   2. Let the owner correct that point    (a draggable pin on a map)
//   3. Keep the point off the public row   (blur(), below)
//
// ── On the key ──────────────────────────────────────────────────────────
// SEARCH-ARCHITECTURE.md says no API key belongs in the browser, and that is
// still right for Brave, Serper or Anthropic keys: whoever holds one is you,
// with no way to bound it. A Google Maps key is the same exception the
// Supabase publishable key is — it is bounded elsewhere. An HTTP-referrer
// restriction ties it to your own domains, an API restriction ties it to Maps
// and Places alone, and a quota cap bounds the spend. An interactive map
// cannot be drawn any other way: the tiles are fetched by the browser.
//
// What is NOT safe to put here is the Geocoding or Places key used from a
// server, because a referrer restriction cannot cover a server call. If a
// server-side lookup is added later it belongs behind /api, with its own key.
//
// The whole module is optional. With no key configured, hasMaps() is false,
// the form falls back to the city/area dropdowns it has always had, and
// nothing below is ever loaded.

const CFG = (typeof window !== 'undefined' && window.__AKARAT_CONFIG) || {};
const MAPS_KEY = CFG.mapsKey || '';

// Jordan. Biases autocomplete and bounds the initial viewport.
const COUNTRY = 'jo';
const JORDAN_CENTER = { lat: 31.963, lng: 35.93 };

export function hasMaps() {
  return !!MAPS_KEY;
}

/* ──────────────── loader ────────────────
   Google's bootstrap, inlined. Loads once however many callers ask, and
   rejects rather than hanging if the script never arrives, so a blocked CDN
   surfaces as "map unavailable" instead of a spinner that never stops. */

let _maps = null;

export function loadMaps() {
  if (!MAPS_KEY) return Promise.reject(new Error('No Google Maps key configured'));
  if (_maps) return _maps;

  _maps = new Promise((resolve, reject) => {
    if (typeof window === 'undefined') { reject(new Error('No window')); return; }
    if (window.google && window.google.maps) { resolve(window.google.maps); return; }

    const params = new URLSearchParams({
      key: MAPS_KEY,
      libraries: 'places,marker',
      loading: 'async',
      callback: '__akaratMapsReady',
      language: document.documentElement.lang === 'ar' ? 'ar' : 'en',
      region: 'JO'
    });

    const timer = setTimeout(() => reject(new Error('Google Maps took too long to load')), 12000);
    window.__akaratMapsReady = () => { clearTimeout(timer); resolve(window.google.maps); };

    const s = document.createElement('script');
    s.src = `https://maps.googleapis.com/maps/api/js?${params}`;
    s.async = true;
    s.onerror = () => { clearTimeout(timer); reject(new Error('Google Maps failed to load')); };
    document.head.appendChild(s);
  });

  // A failed load must not be cached, or one flaky network request disables
  // the map for the rest of the session.
  _maps.catch(() => { _maps = null; });
  return _maps;
}

/* ──────────────── autocomplete ────────────────
   Places API (New). Session tokens matter for the bill: every keystroke is a
   request, but a session of keystrokes plus one details call is billed once,
   so the token is minted per editing session and retired on selection. */

let _token = null;

export function newSession(maps) {
  _token = new maps.places.AutocompleteSessionToken();
  return _token;
}

/**
 * Address suggestions for what the owner has typed so far.
 * Returns [{ id, primary, secondary, fetch() }]; `fetch` resolves the full
 * place and is what closes the billing session.
 */
export async function suggest(maps, input, bias) {
  const text = (input || '').trim();
  if (text.length < 3) return [];
  if (!_token) newSession(maps);

  const request = {
    input: text,
    sessionToken: _token,
    includedRegionCodes: [COUNTRY],
    language: document.documentElement.lang === 'ar' ? 'ar' : 'en'
  };
  // Bias toward the city already chosen in the form, so "Abdoun" in an Irbid
  // listing does not rank the Amman one first.
  if (bias && bias.lat != null && bias.lng != null) {
    request.locationBias = { center: bias, radius: 20000 };
  }

  const { suggestions } = await maps.places.AutocompleteSuggestion
    .fetchAutocompleteSuggestions(request);

  return (suggestions || [])
    .map(s => s.placePrediction)
    .filter(Boolean)
    .map(p => ({
      id: p.placeId,
      primary: p.mainText ? p.mainText.text : p.text.text,
      secondary: p.secondaryText ? p.secondaryText.text : '',
      fetch: async () => {
        const place = p.toPlace();
        await place.fetchFields({ fields: ['location', 'formattedAddress', 'displayName'] });
        _token = null; // session closed; the next keystroke starts a new one
        return {
          lat: place.location.lat(),
          lng: place.location.lng(),
          address: place.formattedAddress || '',
          name: place.displayName || ''
        };
      }
    }));
}

/* ──────────────── the map picker ────────────────
   A map with one draggable pin. Clicking the map moves the pin too, because
   dragging a pin on a phone is fiddly and tapping is not. */

export function pinMap(maps, el, at, onMove) {
  const center = at && at.lat != null ? at : JORDAN_CENTER;
  const map = new maps.Map(el, {
    center,
    zoom: at && at.lat != null ? 17 : 11,
    mapTypeId: 'roadmap',
    mapTypeControl: false,
    streetViewControl: false,
    fullscreenControl: false,
    zoomControl: true,
    gestureHandling: 'greedy',
    clickableIcons: false
  });

  const marker = new maps.Marker({
    map,
    position: center,
    draggable: true,
    title: ''
  });

  const report = pos => onMove({ lat: pos.lat(), lng: pos.lng() });
  marker.addListener('dragend', e => report(e.latLng));
  map.addListener('click', e => { marker.setPosition(e.latLng); report(e.latLng); });

  return {
    map,
    marker,
    moveTo(next, zoom) {
      const p = { lat: next.lat, lng: next.lng };
      marker.setPosition(p);
      map.setCenter(p);
      if (zoom) map.setZoom(zoom);
    },
    destroy() {
      maps.event.clearInstanceListeners(marker);
      maps.event.clearInstanceListeners(map);
      marker.setMap(null);
    }
  };
}

/* ──────────────── coordinates → our own taxonomy ────────────────
   city_id and neighborhood_id are foreign keys, and search, dedupe and the
   Arabic place names all read them. A Google point does not replace them; it
   locates a property *inside* one. So every pin is snapped back to the
   nearest known area, and the dropdowns stay the source of truth. */

const EARTH_KM = 6371;

export function distanceKm(a, b) {
  const rad = d => (d * Math.PI) / 180;
  const dLat = rad(b.lat - a.lat);
  const dLng = rad(b.lng - a.lng);
  const s = Math.sin(dLat / 2) ** 2
    + Math.cos(rad(a.lat)) * Math.cos(rad(b.lat)) * Math.sin(dLng / 2) ** 2;
  return 2 * EARTH_KM * Math.asin(Math.sqrt(s));
}

/**
 * The closest city and neighbourhood in data/market.js to a dropped pin.
 * `market` is the imported data/market.js module.
 *
 * A neighbourhood is only accepted within 6 km of its centre: past that the
 * pin is somewhere the taxonomy has no name for, and guessing an area would
 * put the listing on a search page it does not belong on. The city is always
 * returned, because every point in Jordan has a nearest one.
 */
export function nearestArea(market, at) {
  if (!at || at.lat == null) return { city_id: null, neighborhood_id: null };

  const near = (list, cap) => {
    let best = null;
    let bestKm = Infinity;
    for (const item of list) {
      if (item.lat == null || item.lng == null) continue;
      const km = distanceKm(at, { lat: item.lat, lng: item.lng });
      if (km < bestKm) { bestKm = km; best = item; }
    }
    return cap != null && bestKm > cap ? null : best;
  };

  const hood = near(market.NEIGHBORHOODS || [], 6);
  // A matched neighbourhood decides the city, so the two can never disagree.
  const city = hood
    ? (market.CITIES || []).find(c => c.id === hood.city)
    : near(market.CITIES || [], null);

  return {
    city_id: city ? city.id : null,
    neighborhood_id: hood ? hood.id : null
  };
}

/* ──────────────── privacy ────────────────
   README's known gap: "Owners cannot yet hide exact coordinates behind an
   approximate location."

   blur() is the answer. The exact point goes to property_locations, which
   only the owner can read; properties.lat/lng — the row the anon key reads —
   gets this displaced point instead.

   Two properties of the displacement matter:

   - It is deterministic. Seeded from the coordinates themselves, so the
     circle lands in the same place on every save and every render. A random
     offset per read would let anyone average many reads back to the truth.
   - It is an offset, not a rounding. Rounding to 3 decimals snaps to a grid,
     and a grid tells you the true point is within one known cell. */

const BLUR_METRES = 300;

function seed(lat, lng) {
  // FNV-1a over the fixed-precision coordinates. Not a security hash; it only
  // has to spread nearby inputs to unrelated angles.
  const str = `${lat.toFixed(6)},${lng.toFixed(6)}`;
  let h = 0x811c9dc5;
  for (let i = 0; i < str.length; i += 1) {
    h ^= str.charCodeAt(i);
    h = Math.imul(h, 0x01000193) >>> 0;
  }
  return h;
}

/** A point up to ~300 m from the real one, stable for a given input. */
export function blur(lat, lng) {
  if (lat == null || lng == null) return { lat: null, lng: null };
  const h = seed(lat, lng);
  const angle = ((h & 0xffff) / 0xffff) * 2 * Math.PI;
  // sqrt keeps the distribution even across the disc instead of clustering
  // everything near the centre.
  const radius = BLUR_METRES * Math.sqrt(((h >>> 16) & 0xffff) / 0xffff);

  const dLat = (radius * Math.cos(angle)) / 111320;
  const dLng = (radius * Math.sin(angle)) / (111320 * Math.cos((lat * Math.PI) / 180));

  return {
    lat: Number((lat + dLat).toFixed(6)),
    lng: Number((lng + dLng).toFixed(6))
  };
}

export const BLUR_RADIUS_M = BLUR_METRES;
