// One-time: translates the missing language of listings saved before
// /api/translate existed. The work runs on the deployed site
// (app/api/admin/backfill-translations/route.ts), which holds the Supabase
// service-role key and the Anthropic key; this only drives it a page at a time.
//
//   BACKFILL_SECRET=... node scripts/backfill-translations.mts            # dry run: lists what it would change
//   BACKFILL_SECRET=... node scripts/backfill-translations.mts --apply    # writes
//
// BACKFILL_SECRET is the value set under the same name in Vercel. SITE_URL
// defaults to the live site.
const SITE = process.env.SITE_URL || 'https://www.akarat.ai';
const SECRET = process.env.BACKFILL_SECRET;
const APPLY = process.argv.includes('--apply');

if (!SECRET) {
  console.error('Set BACKFILL_SECRET to the value of BACKFILL_SECRET in Vercel.');
  process.exit(1);
}

console.log(`${SITE}: ${APPLY ? 'writing changes.' : 'dry run, nothing is written. Add --apply to write.'}`);

let after: string | null = null;
const counts = { updated: 0, ok: 0, failed: 0 };
do {
  const res = await fetch(`${SITE}/api/admin/backfill-translations`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${SECRET}` },
    body: JSON.stringify({ apply: APPLY, after }),
  });
  const body = (await res.json().catch(() => ({}))) as { lines?: string[]; next?: string | null; error?: string };
  if (!res.ok) {
    console.error(
      `Stopped: ${res.status} ${body.error ?? ''}` +
      (res.status === 404 ? '\nThe site does not have this endpoint yet: deploy the latest code first.' : ''),
    );
    // exitCode rather than process.exit(): exiting with the fetch's handles
    // still open trips a libuv assertion on Windows.
    process.exitCode = 1;
    break;
  }
  for (const line of body.lines ?? []) {
    if (line.startsWith('ok ')) { counts.ok++; continue; }
    console.log(line);
    if (line.startsWith('FAILED') || line.startsWith('skipped')) counts.failed++;
    else counts.updated++;
  }
  after = body.next ?? null;
} while (after);

if (!process.exitCode) console.log(
  `Done. ${counts.updated} ${APPLY ? 'updated' : 'to update'}, ` +
  `${counts.ok} already in both languages, ${counts.failed} failed or skipped.`,
);
