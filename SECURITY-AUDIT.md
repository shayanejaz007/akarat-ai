# Security audit — Akarat.ai

Date: 22 August 2026. Scope: the client application, the Supabase schema and
policies, the search API route, and the crawl worker.

## Verdict

No secret material reaches the browser, and no table is writable by a client
beyond its own rows. Two items must be completed before this is live, both
operational rather than code: run the migrations, and keep the service-role key
out of any client bundle.

## Verified on the running client

Probed the live DOM rather than reading the source:

| Check | Result |
|---|---|
| Service-role key or `sb_secret` in the document | none |
| JWT-shaped strings in the document | none |
| External links missing `rel="noopener noreferrer"` | 0 of 3 |
| External links not on HTTPS | none |
| Inline `onclick` / `onerror` / `onload` attributes | 0 |
| `iframe` elements | 0 |
| Password inputs without an `autocomplete` hint | 0 |

The only credential in the browser is the Supabase **publishable** key, which is
designed for it. Its blast radius is whatever Row Level Security allows, and
nothing more.

## Authorisation

Every policy is in `supabase/migrations/0001_init.sql`. The shape that matters:

- `properties` — anyone may read rows with `status = 'active'`. A signed-in user
  may additionally read, insert, update and delete rows where
  `auth.uid() = owner_id`. There is no policy that lets one user touch another
  user's listing.
- `profiles` — self read and self write only.
- `saved_searches` — private to the owning user for all operations.
- `inquiries` — readable by the listing owner or the sender; insertable by
  anyone, so a visitor can send one without an account.
- `external_properties`, `external_sources` — **public read, no write policy at
  all.** Only the service role, held by the crawler, can write. A stolen
  publishable key cannot poison the index.

`middleware.ts` additionally gates `/dashboard` and `/list` server-side. The
client-side `signedIn` flag controls what is *shown*; it is not access control,
and nothing depends on it for authorisation.

## Ownership is never taken from the client

`createProperty` sets `owner_id` from `auth.getUser()` on the server side of the
Supabase call, not from anything the caller passes. The RLS `with check`
clause enforces the same condition independently, so both layers would have to
fail to allow a forged owner.

## The crawler

`app/api/admin/crawl/route.ts` is the highest-risk component, since it holds the
service-role key and fetches untrusted pages. Controls in place:

- **Authentication** — requires `Bearer ${CRON_SECRET}`; without the env var set
  the route refuses every request rather than defaulting to open.
- **Host allowlist** — only hosts present and `enabled` in `external_sources`.
  Both seeded sources ship `enabled = false`.
- **robots.txt** — fetched and parsed per host, our own agent group taking
  precedence over the wildcard, `Crawl-delay` honoured. A network failure
  refuses the crawl rather than assuming permission.
- **Rate limiting** — per-host delay, and `Retry-After` respected on 429/503.
- **Prompt-injection surface** — raw HTML never leaves the extractor. Only
  schema.org JSON-LD is parsed, and each field is mapped explicitly rather than
  spread, so unknown keys cannot ride along into the database or the client.
- **Never bypasses** a CAPTCHA, paywall or login.

## The search route

`app/api/ai/search/route.ts`:

- **SSRF** — `assertFetchable()` requires HTTPS, blocks `localhost`, `127.*`,
  `10.*`, `192.168.*`, `172.16–31.*`, `169.254.*` (cloud metadata), `.local` and
  `.internal`, and requires the host to be on an explicit allowlist.
  `redirect: "error"` prevents a redirect off the allowlist.
- **Rate limiting** — 60 searches/minute signed in, 15 for anonymous.
- **Fault isolation** — `Promise.allSettled`, so one provider failing degrades
  coverage rather than the request. The response states which sources were
  unavailable instead of presenting partial results as complete.
- **Error messages** — generic text to the client; no stack traces, no database
  errors, no environment detail.

## AI advisor

Added 29 October 2026. `app/api/ai/advisor/route.ts` and `lib/advisor/`. The
advisor is a language model reading text written by strangers (visitors,
listing owners, web pages), so every rule it is given is also enforced
outside it. The system prompt is the first line of defence, not the only one.

- **Credentials.** `ANTHROPIC_API_KEY` is read only by the route. The browser
  sends text to `/api/ai/advisor` and receives text, cards and links; it never
  calls a model or a third party. `scripts/sync-public.mjs` no longer copies
  any `.ts` file to `public/`. Before this change it copied all of `lib/`,
  which served the server source (the admin gate, the translation prompt) as
  downloadable files; nothing secret was in them, but the advisor's prompt
  would have been.
- **What it can reach.** Seven tools of its own, all read-only and
  parameterised: fixed lists of deals, types, cities, areas and amenities,
  numeric ranges checked in code, listing ids that must be UUIDs. No SQL, no
  URL fetched by our server, no code run. Listing reads go through the
  caller's own Supabase client, so Row Level Security decides what exists:
  drafts, rejected and pending listings are invisible to it, exactly as on
  the website. Owner contact details, owner ids, addresses and coordinates
  are never put in front of the model; output is built field by field.
- **The web.** Anthropic's web search and web fetch, called directly (not
  from code execution) so each result comes back to us. Both are limited to a
  fixed list of two listing portals and sixteen official, news and research
  sites (`lib/advisor/config.ts`). Fetching happens on Anthropic's side: it
  refuses private addresses and honours robots.txt, and only URLs that came
  from a search or the user's own message can be fetched. Our server makes no
  request on the model's behalf, so there is no SSRF path through it.
- **Fabrication.** A listing card is never the model's word. An Akarat.ai
  card is rebuilt from the database row, and must be an id a tool returned
  in this conversation and still active. An outside card needs its exact URL
  to have come back from search or fetch, on an approved portal; each price,
  room count, size and location must appear on the page web_fetch read, or
  it is left off the card and the model is told not to state it. A page that
  says the ad is gone is refused.
- **Prompt injection.** Listing text and web pages reach the model only as
  tool results, labelled as owner-written or third-party data; the prompt
  tells it to ignore instructions inside them. What the model can do with an
  injected instruction is bounded by the above: it cannot reach private data,
  invent a link onto a card, or fetch outside the list.
- **Leaks.** The prompt carries a canary string. The reply streams through a
  120-character hold-back and is screened as it goes: the canary, or three
  verbatim eight-word runs of the operating rules, withdraws the reply before
  any of the matched text reaches the browser. The page renders replies with
  `createElement` and text nodes only; a link in a reply works only if it
  points at this site or at the reply's own sources and listings.
- **Forged history.** The conversation is held by the browser and signed
  with HMAC-SHA256 under a server-only key; it expires after twelve hours. A
  transcript that fails the check is dropped and the visitor is told.
- **Abuse and cost.** Per minute (5 anonymous, 8 signed in) through the
  shared limiter; per day per caller (30 / 80) and a site-wide daily cap
  (600) in `0020_ai_advisor.sql`. Each turn is capped at six model calls, six
  web searches, four page reads, 14,000 output tokens and 54 seconds. Inputs
  are capped at 2,000 characters, with control and bidi-override characters
  removed. Callers are recorded as a user id or a salted hash of the address,
  never a raw IP, and the log line per turn has counts and outcomes, never the
  conversation. Flags (a withdrawn reply, an unbacked link, a refused tool
  input) are counted for the admin panel.
- **Errors.** The visitor sees a fixed message per error code. The server log
  keeps the API status and message, not the request.

Tests: `npm run test:advisor` (54, no model or network) covers the tools'
validation, the evidence checks, signing, the leak screen and the agent loop
against a stand-in API. `scripts/advisor-live-check.mts` runs the attacks
against the real model: prompt extraction, owners' phone numbers, a role
override, internal addresses, an invented listing URL and a forged history.

## Injection

The app builds no SQL. Every query goes through the Supabase client as
parameterised calls. There is no `innerHTML` assignment in application code, no
`eval`, and no `dangerouslySetInnerHTML`. All user-visible text is rendered as
text nodes by the component runtime.

## Before launch

1. **Run the migrations.** Until `0001`–`0003` are applied the tables do not
   exist, so RLS is not protecting anything yet. This is the single most
   important item.
2. **Keep `SUPABASE_SERVICE_ROLE_KEY` server-only.** Never prefix it with
   `NEXT_PUBLIC_`, never import it into a client component.
3. **Rotate the publishable key** if the repo was ever public before
   `.gitignore` was added, and confirm `.env.local` is not in git history.
4. **Move the rate-limit buckets to Redis or Postgres.** The in-memory map in
   the search route is per-instance, so it does not hold across a scaled
   deployment.
5. **Set `CRON_SECRET`** before enabling any source.
6. **Add security headers** at the edge: a Content-Security-Policy, HSTS,
   `X-Content-Type-Options: nosniff`, `X-Frame-Options: DENY`. The document
   already sets a strict `referrer` policy.
7. **Enable email confirmation** in Supabase Auth for production. The sign-up
   flow already handles the "check your email" path.
8. **Turn on leaked-password protection** in Supabase Auth, and consider a
   minimum length above the default.

## Not addressed, by design

Exact property coordinates are stored but the owner-side privacy control
(showing an approximate location instead) is not built yet. If you launch with
real listings before that exists, owners cannot hide a precise address.
