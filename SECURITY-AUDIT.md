# Security audit — Akarat.ai

Date: 22 August 2026. Scope: the client application, the Supabase schema and
policies, the search API route, and the crawl worker.

## Production audit, 30 October 2026

Scope: both AI assistants (models, prompts, injection and leaks, cost), the
Supabase schema and API routes, dependencies, secrets, and the website's UI.
Findings and what was done; the remaining items are at the end.

- **Dependencies.** Next.js 14.2.35 had critical and high advisories; it is
  now 15.5.28 (React 19). `npm audit --omit=dev` leaves two, both PostCSS
  inside Next (one high, one moderate). PostCSS runs at build time on this
  project's own CSS, never on visitors' input; the fix is Next 16, a major
  upgrade, and is recorded as an accepted risk until then.
- **Secrets.** The working tree and all 44 revisions were scanned for keys,
  tokens and private-key material without printing values. None found: the
  only matches are placeholders in documentation and the Android build
  reading its passwords from the git-ignored `key.properties`.
- **Row Level Security.** All 28 tables in the migrations enable it; the
  service-role-only tables revoke everything from `anon` and
  `authenticated`. The 0020, 0021 and 0022 migrations were run on Postgres
  16 (PGlite) with 127 checks of their policies, functions and grants.
- **Routes.** Every admin data route (`/api/admin/` overview, listings,
  users, inquiries, reports, daily, bookings) requires the admin session
  (httpOnly, Secure, SameSite=Strict cookie), and signing in to it is rate
  limited; the crawler and backfill require their secrets; every `/api/legal/*` route goes through one gate
  (configured, signed in, allowed in). No route sets CORS headers, so the
  APIs are same-origin. No browser source maps are produced.
- **AI cost and abuse.** Both assistants now stop researching past an
  estimated per-answer cost (`AI_ADVISOR_MAX_TURN_USD`,
  `LEGAL_MAX_TURN_USD`), on top of the existing call, search, fetch, output
  and time budgets and the per-minute and daily limits. The same question
  from the same caller while it is still being answered is refused (409)
  instead of paid for twice. Each answer's estimated cost, model and effort
  are recorded (0022, service role only) and shown in the admin panel.
- **Model routing.** Deterministic, in code: the advisor runs Claude Sonnet
  5.5 at low effort and high for investment questions; Ask a Lawyer runs it
  at medium, high for documents, courts, urgent matters and long accounts.
  An optional stronger model for legal questions is off by default, and a
  model cheaper than the configured one, or with no known price, is refused.
- **Answers that could be lost.** On these models text written before a
  tool call comes back as a hidden progress note. Both assistants now make
  every tool call first and answer last; follow-up suggestions come from a
  separate structured-output call; a turn that ends with nothing visible is
  asked for its answer once more with tools off.
- **Leaks and injection.** The leak screen now covers the production prompt
  as well as the operating notes, and catches the canary spelled out, split
  by invisible characters or base64 encoded (tests/advisor/injection.test.mts).
  An answer that says it researched when no tool ran is flagged to the
  reader. Injected text in listings, web pages and documents stays data:
  covered by the advisor's end-to-end run (an injected listing description
  never reaches the page) and the legal document tests.
- **Browser.** `Permissions-Policy` allows the microphone for this site only
  (voice dictation) and nothing else; geolocation and camera stay off.

**Still open.** Neither assistant has been run against the live model in
this audit: there was no API key here. `scripts/model-benchmark.mts` and
`npm run legal:eval` are ready and must be run before release, and Ask a
Lawyer needs the licensed lawyer's review it was built to wait for. No
external penetration test has been done. There is no ESLint configuration;
TypeScript's strict check is the static gate.

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
  120-character hold-back and is screened as it goes: the canary (also when
  spelled out, split by invisible characters, in another case or base64
  encoded), or three verbatim eight-word runs of the instructions (the
  production prompt and the operating notes; long base64 runs are decoded
  and checked too), withdraws the reply before any of the matched text
  reaches the browser. The disclaimer is excluded, since it is meant to be
  repeated. Tests: tests/advisor/injection.test.mts. The page renders replies with
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

## Ask a Lawyer

Added 30 October 2026. `app/api/legal/*`, `lib/legal/`, `0021_legal_ai.sql`.
People bring this feature their disputes, contracts and identity documents,
so it is built on the assumption that everything stored will one day be seen
by someone who should not see it, and that the model will one day be told to
misbehave by a document. LEGAL-AI.md has the architecture; this is the
security record.

- **Who can call it.** Signed-in accounts only: every route resolves the
  Supabase session from the bearer token (the website sends the token from
  its own storage, not a cookie) and refuses anonymous callers with 401.
  Before launch only the accounts in `LEGAL_REVIEWERS` get past the gate
  (403 for everyone else); `LEGAL_ACCESS=public` opens it. The gate is in the
  server, not the page.
- **Whose data it can touch.** Conversations, messages and documents are
  read and written with the caller's own session, so Row Level Security
  decides: each table's policy is `user_id = auth.uid()`, a message or
  document must also sit in one of the caller's own conversations, and a
  document's file path must be in the caller's own folder of the private
  `legal-documents` bucket, whose storage policies say the same. Messages and
  documents cannot be edited at all; a conversation's title and last-used
  time are the only columns anyone may update. Checked during development by
  running every migration on PGlite (Postgres 16) with two users against
  every table and function, and end to end: a second reviewer cannot list,
  open, add to, or report on the first one's conversation.
- **Encryption at rest, beyond Supabase's own.** Titles, messages, document
  names, document files, report notes and reviewers' snapshots are sealed
  with AES-256-GCM in `lib/legal/crypto.ts` before they leave the server,
  under `LEGAL_DATA_KEY`, which the database never sees. Each value is bound
  (as associated data) to its conversation and role, so ciphertext copied to
  another row, or a user's message relabelled as the assistant's, fails to
  open. A dump, a backup, a support session or a policy mistake shows
  ciphertext. Key rotation: `LEGAL_DATA_KEY_PREVIOUS`.
- **Minimisation and redaction.** Word and text uploads are reduced to their
  text; the file itself is never kept. Text that leaves a person's own
  conversation (conversation titles, report notes, reviewers' snapshots) has
  email addresses, phone numbers, national numbers, IBANs and card numbers
  masked (`lib/legal/redact.ts`). Logs and the provenance table hold counts,
  outcomes and source references, never a question or an answer. The usage
  table keys callers by user id.
- **Uploads.** At most 4 MB and 30 pages, four per conversation, and a token
  budget measured by the API before a file is accepted. The type is read from
  the bytes. Refused: encrypted files, PDFs with scripts, launch actions,
  attachments, rich media or XFA forms (including inside compressed object
  streams), Word files with macros, ActiveX, embedded objects or remote
  templates, zip bombs and encrypted archives (directory read with fixed
  limits; expansion capped regardless of the sizes the archive claims), old
  `.doc`, and anything else. Files are never executed, rendered on our
  servers, or served back to a browser. **No antivirus engine is wired in**;
  this screening is what stands in for one (LEGAL-AI.md, "Not available").
- **Isolation from the library.** User documents live only in their owner's
  rows and folder. The library is a separate set of tables that only the
  service role can read or write, filled only by `scripts/legal-ingest.mts`
  from files people prepared. Nothing a user uploads or asks can reach it.
- **Tools.** Three of its own, strict and read-only: library search, exact
  citation lookup, an urgent-notice banner. (Follow-up suggestions come from a
  separate small call after the answer, with structured output, and are
  cleaned like any model text: no links, no control or direction characters.)
  Inputs are validated again in code (lengths, digits, case-number shapes, fixed lists).
  The library is reached through two `security definer` functions that return
  only verified sources. Web search and fetch are Anthropic's, called
  directly, limited to official Jordanian hosts and a short list of secondary
  ones, and never given URLs from our own tool results.
- **Citations and provenance.** Library passages go to the model as
  `search_result` blocks and the user's documents as `document` blocks, both
  with citations on, so every citation the page shows is tied by the API to
  the passage, page or document it quotes. Every article, law and case
  number in a finished answer is checked against what was retrieved
  (`lib/legal/references.ts`); the ones nothing supports are marked
  "not verified" in the answer itself and counted. Each answer's sources
  (retrieved and cited) go to `legal_audit`.
- **Prompt injection and leaks.** Documents are labelled untrusted where they
  enter, and file names are stripped to letters and digits before the model
  sees them. The canary and the eight-word-run screen from the advisor apply
  here with their own canary; a recital is withdrawn before it reaches the
  page. A planted document instruction cannot reach other users' data, the
  library's write path, or a host outside the list, whatever the model
  decides to do.
- **Retention and deletion.** Triggers set expiry (90 days after a
  conversation's last message, 30 days after a document's upload); nobody
  can extend it. Expired rows and their files are swept by `legal_sweep()`.
  People can delete a conversation or all of them; account deletion deletes
  the rows (foreign keys) and empties the bucket folder.
- **Abuse and cost.** Per minute (4 questions, 4 uploads) through the shared
  limiter; per day per account (30) and site-wide (300) in its own counters,
  apart from the advisor's. Each answer: six model calls, six searches, five
  page reads, 20,000 output tokens, 54 seconds.
- **No training or reuse.** Nothing a user sends is used to train anything
  or shown to anyone else; reviewers' snapshots are the only copy outside a
  conversation, and they are the reviewers' own test questions.

Tests: `npm run test:legal` (74, no model or network): documents and
screening, encryption and redaction, the reference checker, the tools and the
library (including the optional embeddings path against a stand-in), the agent
loop against a stand-in API, ingestion, and the evaluation harness. End to end
against a stand-in Supabase and model: 89 checks in a real browser. Not done:
any run against the real model, and the lawyer's review (LEGAL-AI.md,
"Before launch").

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
