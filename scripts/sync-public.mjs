// Copies the application document and its assets into public/ so Next can
// serve them. Keeps one source of truth: edit the files at the repo root.
//
// Deliberately reads and rewrites bytes rather than using fs.cp: on Windows,
// files extracted from a zip are read-only, and a permission-preserving copy
// fails with EPERM before it ever writes anything.
import { readdir, readFile, writeFile, mkdir, stat, rm } from 'node:fs/promises';
import { existsSync, readFileSync } from 'node:fs';
import { join } from 'node:path';

// ── Read .env.local ourselves ───────────────────────────────────────────
// Loading .env.local is a Next.js feature, not a Node one, and this script
// runs as plain Node from `predev` / `prebuild`. Without this, a key sitting
// in .env.local never reaches public/config.js, and the app behaves exactly
// as though it had never been set — which is a very hard thing to debug.
//
// A real environment variable always wins, so Vercel and CI are unaffected.
function loadEnvFile(file) {
  if (!existsSync(file)) return 0;
  let n = 0;
  for (const raw of readFileSync(file, 'utf8').split(/\r?\n/)) {
    const line = raw.trim();
    if (!line || line.startsWith('#')) continue;
    const eq = line.indexOf('=');
    if (eq < 1) continue;
    const key = line.slice(0, eq).trim();
    if (process.env[key] !== undefined) continue;
    let value = line.slice(eq + 1).trim();
    if ((value.startsWith('"') && value.endsWith('"'))
      || (value.startsWith("'") && value.endsWith("'"))) {
      value = value.slice(1, -1);
    }
    if (value === '') continue;
    process.env[key] = value;
    n += 1;
  }
  return n;
}

// Next's own precedence: .env.local overrides .env.
const envLoaded = loadEnvFile('.env.local') + loadEnvFile('.env');

const items = ['Akarat.dc.html', 'support.js', 'assets', 'lib', 'data'];

async function copyFile(src, dest) {
  // Remove first: an existing read-only target cannot be overwritten.
  if (existsSync(dest)) await rm(dest, { force: true });
  await writeFile(dest, await readFile(src));
}

async function copyTree(src, dest) {
  const info = await stat(src);
  if (info.isDirectory()) {
    await mkdir(dest, { recursive: true });
    for (const entry of await readdir(src)) {
      await copyTree(join(src, entry), join(dest, entry));
    }
  } else {
    await copyFile(src, dest);
  }
}

await mkdir('public', { recursive: true });

for (const item of items) {
  if (!existsSync(item)) {
    console.warn(`sync-public: skipping missing ${item}`);
    continue;
  }
  await copyTree(item, join('public', item));
}

// ── favicon.ico at the web root ─────────────────────────────────────────
// Browsers request /favicon.ico regardless of what <link> tags say, and it is
// what bookmarks and history use. It lives in assets/ so it is versioned with
// the other icons, and is copied to the root here.
if (existsSync(join('assets', 'favicon.ico'))) {
  await copyFile(join('assets', 'favicon.ico'), join('public', 'favicon.ico'));
} else {
  console.warn('sync-public: assets/favicon.ico missing');
}

// ── Vendor React locally ────────────────────────────────────────────────
// The runtime fetches React and ReactDOM from unpkg unless window.__resources
// maps those URLs elsewhere. Serving them from our own origin removes a
// third-party single point of failure from the critical path: an unpkg outage
// otherwise leaves the page blank, because nothing renders until they land.
const VENDOR = [
  ['node_modules/react/umd/react.production.min.js', 'react.production.min.js'],
  ['node_modules/react-dom/umd/react-dom.production.min.js', 'react-dom.production.min.js'],
];
await mkdir(join('public', 'vendor'), { recursive: true });
let vendored = 0;
for (const [src, name] of VENDOR) {
  if (!existsSync(src)) {
    console.warn(`sync-public: ${src} missing — run npm install; falling back to the CDN`);
    continue;
  }
  await copyFile(src, join('public', 'vendor', name));
  vendored += 1;
}

// ── Build-time configuration ────────────────────────────────────────────
// The app document is static, so Next cannot inject env vars per request.
// They are baked in here instead, at build time. The literals in
// lib/supabase.js remain as a fallback so a checkout with no .env still runs.
const cfg = {
  supabaseUrl: process.env.NEXT_PUBLIC_SUPABASE_URL || null,
  supabaseKey: process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY || null,
  // Optional. Unset, the listing form keeps the city/area dropdowns and never
  // loads Google Maps. See lib/geo.js for why this one key is allowed in the
  // browser when SEARCH-ARCHITECTURE.md says none are.
  mapsKey: process.env.NEXT_PUBLIC_GOOGLE_MAPS_KEY || null,
};
// NB: do not set window.__resources here. support.js re-reads the raw document
// source to recover camelCase attributes, and skips that pass entirely when
// __resources is set. React is preloaded with script tags in the document
// instead; loadReactUmd() sees window.React and never calls the CDN.
await writeFile(
  join('public', 'config.js'),
  `/* generated by scripts/sync-public.mjs — do not edit */\n`
  + `window.__AKARAT_CONFIG = ${JSON.stringify(cfg)};\n`
);

console.log(
  `sync-public: public/ is up to date (react vendored: ${vendored}/${VENDOR.length},`
  + ` env file vars: ${envLoaded},`
  + ` supabase config from env: ${cfg.supabaseUrl ? 'yes' : 'no, using lib/supabase.js fallback'},`
  + ` google maps: ${cfg.mapsKey ? 'on' : 'off, form uses dropdowns only'})`
);

// The whole point of the key is that the map appears. If it is set but did not
// make it through, say so here rather than letting the form look broken.
if (!cfg.mapsKey) {
  console.log(
    'sync-public: no NEXT_PUBLIC_GOOGLE_MAPS_KEY — the listing form will use '
    + 'its city/area dropdowns. Put the key in .env.local to enable the map '
    + '(see LOCATIONS.md).'
  );
}
