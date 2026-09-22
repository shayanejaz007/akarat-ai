// Supabase access for the Akarat.ai prototype.
//
// The publishable key is designed to be exposed in a browser: it grants
// exactly what Row Level Security allows and nothing more. Every policy
// is in supabase/migrations/0001_init.sql — a client can read active
// listings plus its own rows, and can only write rows whose owner_id
// equals its own auth.uid().

// Values come from NEXT_PUBLIC_SUPABASE_URL / NEXT_PUBLIC_SUPABASE_ANON_KEY,
// baked into public/config.js at build time by scripts/sync-public.mjs. The
// literals below are the fallback so a fresh checkout with no .env still runs;
// set the env vars to point staging and production at different projects
// without editing source.
const CFG = (typeof window !== 'undefined' && window.__AKARAT_CONFIG) || {};
const SUPABASE_URL = CFG.supabaseUrl || 'https://ppqftdcdpshfokjqnuhq.supabase.co';
const SUPABASE_KEY = CFG.supabaseKey || 'sb_publishable_Xrp8dp25j0fk4-XNpbS5eQ_hXZnIfrH';

let _client = null;
let _loading = null;

export async function getClient() {
  if (_client) return _client;
  if (_loading) return _loading;
  _loading = import('https://esm.sh/@supabase/supabase-js@2.45.4')
    .then(({ createClient }) => {
      _client = createClient(SUPABASE_URL, SUPABASE_KEY, {
        auth: { persistSession: true, autoRefreshToken: true, storageKey: 'akarat.auth' }
      });
      return _client;
    });
  return _loading;
}

/* ────────────────────────────────────────────────────────────
   Payload compression.

   A listing's queryable facts (price, beds, city, status) stay in real
   columns so Postgres can index and filter them. Everything bulky and
   free-form travels together in one gzipped blob: both descriptions,
   the amenity list, image metadata and contact preferences.

   Typical saving on a full bilingual listing is 60–75%, because the
   two descriptions and the repeated JSON keys compress extremely well.
   ──────────────────────────────────────────────────────────── */

const hasCompression = typeof CompressionStream !== 'undefined';

async function streamToBytes(stream) {
  const reader = stream.getReader();
  const chunks = [];
  let total = 0;
  for (;;) {
    const { done, value } = await reader.read();
    if (done) break;
    chunks.push(value);
    total += value.length;
  }
  const out = new Uint8Array(total);
  let at = 0;
  for (const c of chunks) { out.set(c, at); at += c.length; }
  return out;
}

function bytesToBase64(bytes) {
  let s = '';
  const CHUNK = 0x8000; // avoid blowing the argument limit on large blobs
  for (let i = 0; i < bytes.length; i += CHUNK) {
    s += String.fromCharCode.apply(null, bytes.subarray(i, i + CHUNK));
  }
  return btoa(s);
}

function base64ToBytes(b64) {
  const bin = atob(b64);
  const out = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i);
  return out;
}

// object → { payload_gz, payload_bytes, raw_bytes, ratio }
export async function packPayload(obj) {
  const json = JSON.stringify(obj);
  const raw = new TextEncoder().encode(json);
  if (!hasCompression) {
    // Older browser: store it readable rather than failing the save.
    const b64 = bytesToBase64(raw);
    return { payload_gz: 'raw:' + b64, payload_bytes: b64.length, raw_bytes: raw.length, ratio: 1 };
  }
  const cs = new CompressionStream('gzip');
  const stream = new Blob([raw]).stream().pipeThrough(cs);
  const gz = await streamToBytes(stream);
  const b64 = bytesToBase64(gz);
  return {
    payload_gz: 'gz:' + b64,
    payload_bytes: gz.length,
    raw_bytes: raw.length,
    ratio: raw.length ? gz.length / raw.length : 1
  };
}

// stored string → original object
export async function unpackPayload(stored) {
  if (!stored) return {};
  try {
    if (stored.startsWith('raw:')) {
      return JSON.parse(new TextDecoder().decode(base64ToBytes(stored.slice(4))));
    }
    const bytes = base64ToBytes(stored.startsWith('gz:') ? stored.slice(3) : stored);
    if (!hasCompression) return {};
    const ds = new DecompressionStream('gzip');
    const out = await streamToBytes(new Blob([bytes]).stream().pipeThrough(ds));
    return JSON.parse(new TextDecoder().decode(out));
  } catch (e) {
    console.warn('payload could not be read', e);
    return {};
  }
}

/* ──────────────── auth ──────────────── */

export async function signUp(email, password, fullName) {
  const sb = await getClient();
  const { data, error } = await sb.auth.signUp({
    email,
    password,
    options: { data: { full_name: fullName || '' } }
  });
  if (error) throw error;
  return data;
}

export async function signIn(email, password) {
  const sb = await getClient();
  const { data, error } = await sb.auth.signInWithPassword({ email, password });
  if (error) throw error;
  return data;
}

export async function signOut() {
  const sb = await getClient();
  await sb.auth.signOut();
}

export async function getSession() {
  const sb = await getClient();
  const { data } = await sb.auth.getSession();
  return data.session || null;
}

export async function onAuthChange(fn) {
  const sb = await getClient();
  const { data } = sb.auth.onAuthStateChange((_e, session) => fn(session));
  return () => data.subscription.unsubscribe();
}

/* ──────────────── properties ──────────────── */

// Owner's listings, newest first, with each payload decompressed.
export async function listMyProperties() {
  const sb = await getClient();
  const { data: { user } } = await sb.auth.getUser();
  if (!user) return [];
  const { data, error } = await sb
    .from('properties')
    .select('*')
    .eq('owner_id', user.id)
    .order('created_at', { ascending: false });
  if (error) throw error;
  return Promise.all((data || []).map(async row => ({
    ...row,
    payload: await unpackPayload(row.payload_gz)
  })));
}

// `fields` are the indexed columns; `payload` is everything else and is
// gzipped before it leaves the browser.
export async function createProperty(fields, payload) {
  const sb = await getClient();
  const { data: { user } } = await sb.auth.getUser();
  if (!user) throw new Error('Not signed in');
  const packed = await packPayload(payload || {});
  // `ratio` is a UI-only statistic for the save note. The table has no such
  // column, and PostgREST rejects the whole insert if it is sent.
  const { ratio, ...columns } = packed;
  const { data, error } = await sb
    .from('properties')
    .insert({ ...fields, owner_id: user.id, ...columns })
    .select()
    .single();
  if (error) throw error;
  return { ...data, payload: payload || {}, _compression: packed };
}

/**
 * Rewrites an existing listing. Same shape as createProperty, so the form can
 * build one object and pick the call.
 *
 * owner_id and status are deliberately not touchable here: ownership is not
 * an editable field, and status has its own control (updatePropertyStatus) so
 * that saving an edit cannot quietly republish a listing the owner had
 * hidden. The `.eq('owner_id')` is belt and braces — the RLS policy in
 * 0001_init.sql already refuses any other row — but it keeps a bug in this
 * file from becoming a bug in someone else's listing.
 */
export async function updateProperty(id, fields, payload) {
  if (!id) throw new Error('No listing id');
  const sb = await getClient();
  const { data: { user } } = await sb.auth.getUser();
  if (!user) throw new Error('Not signed in');
  const packed = await packPayload(payload || {});
  const { ratio, ...columns } = packed;
  const { owner_id, status, id: _ignored, ...safe } = fields || {};
  const { data, error } = await sb
    .from('properties')
    .update({ ...safe, ...columns })
    .eq('id', id)
    .eq('owner_id', user.id)
    .select()
    .single();
  if (error) throw error;
  return { ...data, payload: payload || {}, _compression: packed };
}

/* ──────────────── exact coordinates ────────────────
   properties.lat/lng is the publishable point and may be displaced. The real
   one lives in property_locations, which 0010_location.sql makes readable by
   its owner alone. See lib/geo.js → blur(). */

export async function saveExactLocation(propertyId, { lat, lng, placeId = null, address = null }) {
  if (!propertyId || lat == null || lng == null) return;
  const sb = await getClient();
  const { data: { user } } = await sb.auth.getUser();
  if (!user) throw new Error('Not signed in');
  const { error } = await sb.from('property_locations').upsert({
    property_id: propertyId,
    owner_id: user.id,
    lat,
    lng,
    place_id: placeId,
    address
  }, { onConflict: 'property_id' });
  if (error) throw error;
}

/**
 * The owner's own exact pin, for reopening the form on a listing they are
 * editing. Returns null when there is none, and also when the table does not
 * exist yet — an owner who has not run 0010 should get the dropdowns back,
 * not a failed edit.
 */
export async function getExactLocation(propertyId) {
  if (!propertyId) return null;
  const sb = await getClient();
  const { data, error } = await sb
    .from('property_locations')
    .select('lat, lng, place_id, address')
    .eq('property_id', propertyId)
    .maybeSingle();
  if (error) return null;
  return data || null;
}

/* ──────────────── listing media (photos + video) ────────────────
   Files go to Supabase Storage, never into payload_gz: gzipped base64 of a
   JPEG is larger than the JPEG and would bloat every row read. The payload
   keeps only the public URLs.

   Paths are prefixed with the owner's user id, which is what the storage
   policy in 0006_listing_photos.sql checks on write. */

const MEDIA_BUCKET = 'listing-photos';
const MAX_IMAGE_BYTES = 6 * 1024 * 1024;
const MAX_VIDEO_BYTES = 50 * 1024 * 1024;
const MAX_VIDEOS = 2;

const IMAGE_TYPES = ['image/jpeg', 'image/png', 'image/webp', 'image/avif'];
const VIDEO_TYPES = ['video/mp4', 'video/webm', 'video/quicktime'];

/* ──────────────── downscaling before upload ────────────────
   A phone camera writes 4000 px JPEGs at three to six megabytes. The cards
   that display them are about 300 px wide, so an audit of the home page found
   7 MB of photographs being fetched to fill three thumbnails — one of them
   4032 px shown at 301 px. On a Jordanian mobile connection that is the
   difference between a site that feels immediate and one people leave.

   Resizing here, before the bytes ever leave the browser, is what fixes it on
   the free plan: Supabase's own image transformation would serve a perfect
   size per layout but is a paid feature. It also costs the owner less upload
   time and less stored data, and it is permanent — every listing added from
   now on is small at rest, with no transformation step in the request path.

   1600 px is the ceiling because the detail page shows photos full width on a
   desktop display, and a lightbox opens them larger still. Below that they
   start to look soft; above it nothing on screen can use the pixels. */

const MAX_EDGE = 1600;
const JPEG_QUALITY = 0.85;

async function downscaleImage(file) {
  // Only worth it for photographs. A PNG is usually a screenshot or a graphic
  // with text, where re-encoding to JPEG is visibly worse, and an AVIF/WebP
  // is already small. Anything unexpected falls through untouched.
  if (file.type !== 'image/jpeg' && file.type !== 'image/png') return file;
  if (typeof createImageBitmap !== 'function' || typeof OffscreenCanvas !== 'function') return file;

  try {
    const bitmap = await createImageBitmap(file);
    const { width, height } = bitmap;
    const longest = Math.max(width, height);
    if (longest <= MAX_EDGE) { bitmap.close(); return file; }

    const scale = MAX_EDGE / longest;
    const w = Math.round(width * scale);
    const h = Math.round(height * scale);
    const canvas = new OffscreenCanvas(w, h);
    const ctx = canvas.getContext('2d');
    ctx.drawImage(bitmap, 0, 0, w, h);
    bitmap.close();

    const blob = await canvas.convertToBlob({ type: 'image/jpeg', quality: JPEG_QUALITY });
    // A resize that did not actually save anything is not worth the quality
    // loss or the changed file type.
    if (!blob || blob.size >= file.size) return file;

    const name = file.name.replace(/\.[^.]+$/, '') + '.jpg';
    return new File([blob], name, { type: 'image/jpeg', lastModified: Date.now() });
  } catch {
    // Anything at all going wrong here must not stop the listing being
    // published. The original uploads, exactly as it did before.
    return file;
  }
}

function extensionFor(file) {
  const fromName = (file.name.split('.').pop() || '').toLowerCase();
  if (/^[a-z0-9]{2,5}$/.test(fromName)) return fromName;
  // A file with no usable extension still needs one, or Storage serves it as
  // application/octet-stream and the browser downloads it instead of playing it.
  return file.type === 'video/quicktime' ? 'mov'
    : file.type.startsWith('video/') ? file.type.slice(6)
    : file.type.slice(6) || 'jpg';
}

/**
 * Uploads listing images and video clips to Storage and returns the public
 * URLs. Each entry carries its own `type` so the gallery knows whether to
 * render an <img> or a <video>; entries written before video existed have no
 * `type` and are read as images.
 *
 * The size and MIME limits below are the client-side half of the check. The
 * bucket enforces the same numbers server-side (0006 + 0007), because a
 * browser check is a courtesy, not a control.
 */
export async function uploadListingMedia(files, onProgress) {
  if (!files || !files.length) return [];
  const sb = await getClient();
  const { data: { user } } = await sb.auth.getUser();
  if (!user) throw new Error('Not signed in');

  const list = Array.from(files);
  if (list.filter(f => f.type.startsWith('video/')).length > MAX_VIDEOS) {
    throw new Error(`Two video clips is the maximum`);
  }

  const out = [];
  let done = 0;
  for (const original of list) {
    const isVideo = original.type.startsWith('video/');
    const allowed = isVideo ? VIDEO_TYPES : IMAGE_TYPES;
    if (!allowed.includes(original.type)) {
      throw new Error(`${original.name} is not a supported ${isVideo ? 'video' : 'image'} format`);
    }

    // Downscale first, then check the cap against what is actually being
    // uploaded. Doing it in this order means a 12 MB photo straight off a
    // phone succeeds at about 300 KB, rather than being refused for a size it
    // was never going to be sent at. Video is passed through untouched:
    // re-encoding it in the browser is slow and lossy.
    const file = isVideo ? original : await downscaleImage(original);

    const cap = isVideo ? MAX_VIDEO_BYTES : MAX_IMAGE_BYTES;
    if (file.size > cap) {
      throw new Error(`${original.name} is larger than ${isVideo ? '50' : '6'} MB`);
    }
    const path = `${user.id}/${Date.now()}-${Math.random().toString(36).slice(2, 8)}.${extensionFor(file)}`;
    const { error } = await sb.storage.from(MEDIA_BUCKET)
      .upload(path, file, { cacheControl: '31536000', upsert: false, contentType: file.type });
    if (error) throw error;
    const { data } = sb.storage.from(MEDIA_BUCKET).getPublicUrl(path);
    out.push({ url: data.publicUrl, path, type: isVideo ? 'video' : 'image' });
    done += 1;
    if (onProgress) onProgress(done, list.length);
  }
  return out;
}

// Kept so anything still calling the old name keeps working.
export const uploadListingPhotos = uploadListingMedia;

export async function deleteListingPhoto(path) {
  const sb = await getClient();
  const { error } = await sb.storage.from(MEDIA_BUCKET).remove([path]);
  if (error) throw error;
}

/* ──────────────── public marketplace ────────────────
   Active listings from every owner. RLS already limits this to
   status = 'active', so no one sees a draft or a hidden row. */

/**
 * One active listing by id, for a deep link into a property that is not in
 * the currently loaded page of results. RLS keeps this to active rows.
 */
export async function getPropertyById(id) {
  if (!id) return null;
  const sb = await getClient();
  const { data, error } = await sb
    .from('properties')
    .select('*')
    .eq('id', id)
    .eq('status', 'active')
    .limit(1);
  if (error || !data || !data.length) return null;
  const row = data[0];
  return { ...row, payload: await unpackPayload(row.payload_gz) };
}

export async function listPublicProperties({ deal = null, limit = 60 } = {}) {
  const sb = await getClient();
  let q = sb.from('properties').select('*').eq('status', 'active');
  if (deal) q = q.eq('deal', deal);
  const { data, error } = await q.order('price_jod', { ascending: false }).limit(limit);
  if (error) throw error;
  return Promise.all((data || []).map(async row => ({
    ...row,
    payload: await unpackPayload(row.payload_gz)
  })));
}

// Must match the listing_status enum in 0001_init.sql exactly. Sending a
// value it does not define fails at the database with "invalid input value
// for enum", which surfaces to the owner as an unexplained rejection.
export const LISTING_STATUSES = [
  'draft', 'pending', 'active', 'rejected', 'paused', 'sold', 'rented', 'archived'
];

export async function updatePropertyStatus(id, status) {
  if (!LISTING_STATUSES.includes(status)) {
    throw new Error(`"${status}" is not a listing status. Expected one of: ${LISTING_STATUSES.join(', ')}`);
  }
  const sb = await getClient();
  const { error } = await sb.from('properties').update({ status }).eq('id', id);
  if (error) throw error;
}

export async function deleteProperty(id) {
  const sb = await getClient();
  const { error } = await sb.from('properties').delete().eq('id', id);
  if (error) throw error;
}

/* ──────────────── external index ────────────────
   Reads the crawler's output. One row per distinct property via the grouped
   view, so a listing found on three portals arrives once with all three
   source links. Returns [] when the index is empty, never a placeholder. */

export async function searchExternalIndex(c, limit = 30) {
  if (!c) return [];
  const sb = await getClient();
  let q = sb.from('external_properties_grouped').select('*');
  if (c.deal) q = q.eq('transaction_type', c.deal);
  if (c.city) q = q.eq('city_id', c.city);
  if (c.hood) q = q.eq('neighborhood_id', c.hood);
  if (c.budgetMax) q = q.lte('price_low', Math.round(c.budgetMax * 1.15));
  if (c.budgetMin) q = q.gte('price_low', c.budgetMin);
  if (c.beds != null) q = q.gte('bedrooms', Math.max(0, c.beds - 1));
  if (c.baths != null) q = q.gte('bathrooms', Math.max(0, c.baths - 1));

  const { data, error } = await q.order('last_seen_at', { ascending: false }).limit(limit);
  if (error) {
    // Index not migrated yet, or unreachable. The UI falls back to portal
    // deep links, which is why this stays quiet rather than throwing.
    return [];
  }
  const now = Date.now();
  return (data || []).map(r => {
    const listings = Array.isArray(r.listings) ? r.listings : [];
    const freshest = listings.reduce((a, b) =>
      (!a || new Date(b.last_checked_at) > new Date(a.last_checked_at)) ? b : a, null);
    const checkedDays = freshest
      ? Math.floor((now - new Date(freshest.last_checked_at).getTime()) / 86400000)
      : null;
    return {
      id: 'x-' + r.group_key,
      source: r.sources && r.sources.length > 1
        ? `${r.sources.length} sources`
        : (r.sources && r.sources[0]) || 'external',
      sources: r.sources || [],
      sourceCount: r.source_count || 1,
      listings,
      url: listings.length ? listings[0].url : null,
      kind: 'known_marketplace',
      en: r.title, ar: r.title,
      deal: r.transaction_type,
      type: r.property_type ? String(r.property_type).toLowerCase() : null,
      city: r.city_id, hood: r.neighborhood_id,
      price: r.price_low,
      priceHigh: r.price_high,
      beds: r.bedrooms, baths: r.bathrooms, area: r.area_sqm,
      lat: r.latitude, lng: r.longitude,
      image: r.image_url,
      checked: checkedDays,
      amen: []
    };
  });
}

// Is the index live, and how much is in it? Drives the coverage panel.
export async function indexStatus() {
  const sb = await getClient();
  const [props, sources] = await Promise.all([
    sb.from('external_properties').select('*', { count: 'exact', head: true }),
    sb.from('external_sources').select('id,name,enabled')
  ]);
  if (props.error || sources.error) return { ready: false, count: 0, sources: [] };
  return {
    ready: true,
    count: props.count || 0,
    sources: sources.data || []
  };
}

export async function listInquiries() {
  const sb = await getClient();
  const { data: { user } } = await sb.auth.getUser();
  if (!user) return [];
  const { data, error } = await sb
    .from('inquiries')
    .select('*, properties(title_en)')
    .eq('owner_id', user.id)
    .order('created_at', { ascending: false })
    .limit(20);
  if (error) throw error;
  return data || [];
}
