# How the search should work, and where keys belong

## Short answers

**Never put a search or LLM API key in the browser.** Not in the bundle, not in
a `NEXT_PUBLIC_` variable, not in a comment. Anything the browser downloads is
public: devtools, view-source, the network tab. Someone will find it and spend
your quota.

The Supabase publishable key is the one exception, and only because Row Level
Security constrains it *on the server*. It can read active listings and the
signed-in user's own rows, and nothing else. A Brave, Serper, Google CSE or
Anthropic key has no equivalent constraint. Whoever holds it is you.

Correct shape:

```
browser  →  your /api/ai/search route  →  provider
                    ↑
            key lives here only,
            in server env, never NEXT_PUBLIC_
```

**Yes, work the way a search engine works.** That is the bigger of the two
answers, and it is already section 25 of your brief.

## What Google actually does

Google does not search the web when you type. It searches its own index, built
continuously by crawlers. Your query touches one system, and it answers in
milliseconds.

Two architectures are available, and the difference matters:

### Live fan-out at query time

Every search hits every portal in real time.

- Latency is set by the slowest source, every single time
- Rate limits are hit constantly, because traffic is bursty
- One dead source degrades every search
- Cost scales with searches, not with inventory
- Ranking is poor: you only ever see the first page of each source
- No cross-source deduplication is possible, because you never hold the data

### Index-first, the search-engine model

```
approved sources → scheduled crawl → extract → normalise
                 → deduplicate → external_properties → search
```

- Searches read your own Postgres. Fast, and fast under load
- Ranking is real, because the whole corpus is in one place and comparable
- Deduplication works, because the same property from three sources is three
  rows you can compare
- Cost scales with inventory, not with traffic
- A source going down affects freshness, not availability
- Freshness is explicit: `last_seen_at`, `last_checked_at`, and a stale sweep

Index-first is the right choice. Keep live fan-out only as a top-up for queries
the index cannot answer.

`supabase/migrations/0002_external_index.sql` creates this: `external_sources`
(the allowlist, with crawl delay and rate limits per host) and
`external_properties` (the index, with the composite indexes a real query uses,
a trigram index for fuzzy title matching during dedupe, and an
`expire_stale_external()` sweep).

Note the RLS: **no policy grants insert or update** on either table. Reads are
public; only the service role, held by the crawler, can write. The browser key
physically cannot poison your index.

## Before you crawl anything

This is the part that decides whether the product survives contact with the
market, so treat it as engineering work, not paperwork.

1. **Ask for the feed first.** Most portals would rather give you a licensed
   feed than be crawled. It is faster, cleaner and legally settled. Both seeded
   sources start `enabled = false` for exactly this reason.
2. **Read robots.txt per host, and honour it.** Record the check in
   `robots_checked_at`.
3. **Read the terms.** Some prohibit automated access outright. `terms_reviewed`
   is a column because it should be a decision someone made, not an assumption.
4. **Identify your crawler** with a real user agent and a contact URL.
5. **Rate limit yourself** below what they would tolerate. `crawl_delay_ms` and
   `requests_per_hour` are per source for this reason.
6. **Never bypass a CAPTCHA, paywall, or login.** If access is gated, the answer
   is a partnership, not a workaround.

Expect at least one portal to object. The durable path is licensed feeds and
partnerships, with crawling as the bridge, which is why the adapter interface in
`app/api/ai/search/route.ts` treats every source as pluggable and optional.

## What the browser does today

No credentials, so no fabricated listings. Your brief is turned into real search
URLs on each portal, and each row states what the link could not carry
("drops Abdoun, price. Set it on their site"). That is honest and useful now,
and it becomes the fallback the moment the index has real rows in it.

## Also keep server-side

- The LLM key, if you add model-based query understanding
- Any search API key used for discovery
- `SUPABASE_SERVICE_ROLE_KEY`, which the crawler needs and which bypasses RLS
  entirely

Rule of thumb: if leaking it would cost you money or let someone write to your
database, it never reaches the browser.
