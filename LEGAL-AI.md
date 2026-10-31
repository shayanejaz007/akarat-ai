# Ask a Lawyer · اسأل محامي

A legal research assistant for Jordanian law, in its own section of the
website. People ask in English, formal Arabic, Jordanian Arabic or a mix, by
typing or speaking, attach a contract or notice, and get an answer in fixed
sections with numbered citations, each labelled with what kind of source it
is and, for the legal library, its status and when it was last verified.

It is **not a lawyer**, it does not represent anyone, and nothing in it is
"verified", "complete" or "lawyer-equivalent". Every answer carries the
mandatory disclaimer from the product brief, word for word, in the answer's
language. Until a licensed Jordanian lawyer has reviewed it, only the
accounts listed in `LEGAL_REVIEWERS` can use it.

## Status, 30 October 2026

| | |
| --- | --- |
| Built and tested without the real model | The page (English and Arabic, right to left, phone and desktop), voice input, document upload and screening, the streamed answer with sections, citations, source labels, unverified-reference marks and urgent notices, history, deletion, downloadable summaries, reports, the admin figures, the legal library's schema, search and ingestion, the evaluation harness |
| Not done yet | Any run against the real model; the lawyer's review; loading verified legislation and judgments into the library (it ships empty) |
| Not available | Listed under "What is not available" below |

Tests: `npm run test:legal` (74, no network). End to end with the
production build, a stand-in for Supabase and the model, and a real Chrome:
89 checks.

## How an answer is made

```
browser ──bearer token──► /api/legal/ask
                           │ 1. signed in? reviewer or open? within limits?
                           │ 2. conversation, messages, documents read with the
                           │    caller's own session (Row Level Security), opened
                           │    (AES-256-GCM, LEGAL_DATA_KEY)
                           │ 3. route (a fixed test, lib/legal/config.ts): Claude Sonnet 5.5,
                           │    medium effort; high effort and more research for a
                           │    document, courts, urgent matters or a long account;
                           │    optional stronger model only if LEGAL_ESCALATION_MODEL
                           │    is set, never a cheaper one
                           │ 4. the model, adaptive thinking, every tool call first,
                           │    the answer as its final message:
                           │      system prompt = the production prompt, verbatim + operating notes
                           │      tools: search_legal_library, lookup_citation (the library)
                           │             web_search, web_fetch (official + secondary hosts)
                           │             flag_urgent
                           │    research stops at the call, search, fetch and cost budgets
                           │ 5. streamed back: text, sources, citations, status
                           │ 6. every article / law / case number checked against
                           │    what was retrieved; the rest marked "not verified"; an
                           │    answer that claims research when none ran is flagged
                           │ 7. follow-up suggestions from a separate small call
                           │    (Claude Haiku 5.5, structured output), cleaned
                           │ 8. both messages saved sealed; sources, route and cost to
                           ▼    legal_audit; usage and cost to legal_usage_daily (0022)
                       ndjson events
```

The answer uses the brief's sections (Short answer, Applicable Jordanian
law, Relevant judicial decisions, Legal analysis, Recommended next steps,
plus Document review when a document is attached). The page draws each as a
collapsible section and adds the sources list and the disclaimer itself, so
neither depends on the model remembering them.

Documents travel with the message they were sent with, in every later turn,
so the start of a conversation is identical from turn to turn and stays in
the prompt cache.

## The sources it can read: coverage report

### The legal library

Tables `legal_sources` and `legal_passages` (0021). Legislation is stored
article by article with its number and year, status (in force, amended,
repealed), effective and repeal dates, amendments, Official Gazette
reference, permanent link, publisher, the basis on which it was taken in
(licence), and who verified it and when. Judgments with court, case number,
year, decision date, issue and holding. Searched by Arabic full text (with
spelling folding and an Arabic stop list, since Postgres ships none) and by
meaning once passages have embeddings, the two fused by reciprocal rank; an
exact lookup finds an article of a numbered law or a judgment by its case
number. **Only sources marked verified are ever returned.**

**It ships empty.** No legislation or judgment was loaded, because no source
that could be used compliantly offered the texts in bulk (below), and
generating or paraphrasing them is exactly what this feature must never do.
`data/legal/README.md` explains how to add sources; `npm run legal:ingest`
loads them.

### Official websites, read at question time

Searched and read with Anthropic's web search and web fetch, limited to
these hosts. Checked from our development machine on 30 October 2026 with
plain requests; Anthropic's fetcher runs from its own servers and honours
robots.txt, so what it can read has to be confirmed by the first live run.

| Host | Who | Seen from here |
| --- | --- | --- |
| lob.gov.jo | Legislation and Opinion Bureau (ديوان التشريع والرأي) | Answers, but its legislation database loads through an encrypted request interface (`EncryptRequest: true` in its `Config.js`). The texts are not in the pages, so web fetch is unlikely to read them, and pulling them in bulk would mean working around that protection. Not done |
| moj.gov.jo | Ministry of Justice | Server-rendered; publishes some instruments as PDFs |
| jc.jo | Judicial Council | Server-rendered; has a legal-framework list. No public judgment database found |
| cco.gov.jo | Constitutional Court | Server-rendered |
| pm.gov.jo | Prime Ministry (Official Gazette) | Answered once, then rejected repeated automated requests ("Request Rejected") |
| istd.gov.jo | Income and Sales Tax Department | Rejected automated requests |
| senate.jo, jordan.gov.jo, dls.gov.jo, mpwh.gov.jo, mola.gov.jo, ammancity.gov.jo, mit.gov.jo, ccd.gov.jo, mol.gov.jo, ssc.gov.jo, cbj.gov.jo, jsc.gov.jo, moi.gov.jo, customs.gov.jo | Senate, e-government portal, Lands and Survey, Public Works and Housing, Local Administration, Greater Amman Municipality, Industry and Trade, Companies Control, Labour, Social Security, Central Bank, Securities Commission, Interior, Customs | Answered |
| parliament.jo, representatives.jo, moinvest.gov.jo, aseza.jo, jfda.gov.jo, moe.gov.jo | | Did not answer from here; left out. Add with `LEGAL_OFFICIAL_DOMAINS` once reachable |

Secondary sources, always labelled "Secondary source · not binding": the
Jordanian Bar Association (jba.org.jo), the Jordan News Agency (petra.gov.jo),
and established newspapers (jordantimes.com, alrai.com, alghad.com,
addustour.com, ammonnews.net, royanews.tv, almamlakatv.com). They can say
that a law changed; they never count as support for a legal reference.

### Court judgments

No public, searchable official repository of Court of Cassation judgments was
found. They are available through commercial databases, which need a licence
before anything from them is used. Until judgments are loaded into the
library, the assistant will usually say that no verified judicial decision
was found, which is the honest answer.

## What is not available

1. **Bulk legislation from the Legislation and Opinion Bureau.** Encrypted
   interface; not scraped. Needs a data agreement with the Bureau, or texts
   copied by hand from published documents into `data/legal/`.
2. **The Official Gazette archive.** Not integrated.
3. **Licensed judgment and commentary databases** (for example Qistas or
   Adaleh). Not integrated; need licences.
4. **An antivirus engine.** Uploads are screened by type and structure
   (`lib/legal/documents.ts`, SECURITY-AUDIT.md); no virus scanner such as
   ClamAV or a cloud scanning service is wired in.
5. **Embeddings and reranking.** Written against Voyage AI's API
   (`VOYAGE_API_KEY`), tested only against a stand-in. Without the key,
   retrieval is full text and exact citation.
6. **Real-model runs.** This environment had no Anthropic key: the agent,
   the citation mapping and the evaluation harness are tested against a
   stand-in of the API, not the model. Run the evaluation before launch.
7. **The lawyer's review.** The workflow is built; the review has not happened.
8. **The mobile app.** The screen is on the website only. The API takes the
   same bearer token the app already sends, so the app can add it without
   server changes.
9. **OCR outside the model.** Scanned PDFs and photos are read by Claude's
   vision. There is no separate OCR step, and quotations from a scan cannot
   be tied to the page automatically; the page and the model say so.

## Citations: what is guaranteed, and what is not

- **Guaranteed by the API.** A citation from the library points at the
  verified passage it quotes (`search_result_location`); one from the user's
  document at the characters or pages it quotes (`char_location`,
  `page_location`); one from the web at the page that was searched or read.
  The page shows each with its kind, status and date.
- **Checked by us.** Every article, law and case number in a finished answer
  is matched against what was retrieved for it (`lib/legal/references.ts`): a
  library passage, an official page that was read, the user's own document,
  or a reference verified in an earlier answer. An article named together
  with its law must be found in that law. Anything unmatched is marked
  "not verified" in the text, listed under the answer, and counted.
- **Not guaranteed.** That the reasoning is right; that an official web page
  reflects the law in force today (its status is unconfirmed unless the page
  states it); paraphrases without numbers; unusual ways of writing a
  reference that the patterns miss. A contract's own numbering ("Article 5 of
  the lease") is deliberately not checked as law.

## Documents

PDF, Word (.docx), text, and JPG, PNG or WebP photos of pages; up to 4 MB, 30
pages and four per conversation; the token cost is counted by the API before
a file is accepted. PDFs and photos are kept as they are, sealed, and read by
the model; Word and text files are reduced to their text, and only the text
is kept. Screening rules are in SECURITY-AUDIT.md. Documents are deleted 30
days after upload, with their conversation, or when the person removes them.

## Privacy and retention

Signed-in accounts only; Row Level Security on every table; everything
personal sealed with AES-256-GCM before it reaches Supabase; identifiers
masked wherever text leaves the person's own conversation; conversations
deleted 90 days after their last message; deletion at any time, one or all;
nothing used for training or shown to anyone else. Details in
SECURITY-AUDIT.md, "Ask a Lawyer".

## Before launch

1. **Load the library.** Decide the launch scope (property and tenancy first
   is the natural one for Akarat.ai) and load the governing legislation,
   verified against the official text: for example the tenancy law, the real
   estate ownership law, the civil code's provisions on sale, lease and
   obligations, civil procedure, execution and evidence, and consumer
   protection. Confirm every title, number and year when verifying; this list
   names candidates, not facts.
2. **Name the reviewers** in `LEGAL_REVIEWERS` and deploy.
3. **Run the evaluation:** `npm run legal:eval -- --yes` (30 cases, about
   $5-8). It writes a JSON file and a printable review sheet to
   `eval-results/`.
4. **The lawyer reviews** each answer on the sheet (correct, partly, wrong;
   citations accurate and current), then uses the live section, recording
   findings with "Report a problem" (reviewers' reports keep the question
   and answer, with identifiers masked; `/admin` lists them).
5. **Fix and repeat.** Library gaps, wrong statuses, prompt wording; then
   run the evaluation again.
6. **Update the privacy policy** (`lib/legal.js`) to describe Ask a Lawyer:
   what is stored and for how long, that questions and documents are
   processed by Anthropic to produce answers, encryption, and deletion. Have
   it reviewed.
7. **The lawyer signs off on the wording** the page uses: the disclaimer,
   the source labels, the review banner.
8. **Open it:** `LEGAL_ACCESS=public`, redeploy.
9. **Keep watching:** in `/admin`, the share of answers with an unverified
   reference, the reports, and sources due for re-verification (over 180
   days since their last check).

## Running it

Environment variables, the migration and costs are in DEPLOY.md, "Ask a
Lawyer". Commands:

```bash
npm run test:legal                       # unit tests, no network
npm run legal:ingest                     # check data/legal/ (dry run)
npm run legal:ingest -- --apply          # load it into the library
npm run legal:ingest -- --apply --embed  # and embed it (VOYAGE_API_KEY)
npm run legal:eval                       # show what the evaluation would cost
npm run legal:eval -- --yes              # run it against the real model
```

## Files

| | |
| --- | --- |
| `Akarat.dc.html` | The "Ask a Lawyer" screen, its dock and its wording (`LW_TEXT`) |
| `lib/legal-client.js` | Browser side: the stream, uploads, history, rendering with unverified marks, the summary |
| `app/api/legal/ask` | The answer, streamed |
| `app/api/legal/documents` | Upload (screened, counted, sealed) and removal |
| `app/api/legal/conversations` | History: list, open, delete one or all |
| `app/api/legal/feedback` | Reports on answers |
| `app/api/legal/status` | Whether this visitor may ask |
| `lib/legal/prompt.ts` | The brief's system prompt, verbatim, the operating notes, the leak screen |
| `lib/legal/agent.ts` | One answer: the loop, citations, the reference check, provenance |
| `lib/legal/tools.ts` | The tools and their validation |
| `lib/legal/library.ts` | Library retrieval, optional embeddings and reranking |
| `lib/legal/references.ts` | Finding and checking legal references |
| `lib/legal/documents.ts` | File screening and text extraction |
| `lib/legal/crypto.ts` | Sealing and opening |
| `lib/legal/store.ts` | Conversations, messages, documents, sweeping |
| `lib/legal/redact.ts` | Masking identifiers |
| `lib/legal/ingest.ts`, `scripts/legal-ingest.mts`, `data/legal/` | Loading the library |
| `lib/legal/evals.ts`, `tests/legal/evals/cases.json`, `scripts/legal-eval.mts` | The evaluation |
| `supabase/migrations/0021_legal_ai.sql` | Tables, policies, search, retention, admin figures |
