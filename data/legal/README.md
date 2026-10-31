# The Akarat legal library: source files

Ask a Lawyer answers from two kinds of material: official Jordanian websites
it reads at question time, and this library. The library holds Jordanian
legislation, court judgments and commentary that a person has checked against
the official text. **Only sources marked `verified` are ever searched.**

The library ships empty. Nothing in it was generated, and nothing was taken
from a database that requires a licence. Each source added here is one Markdown
file, loaded with:

```bash
node scripts/legal-ingest.mts                 # check every file, write nothing
node scripts/legal-ingest.mts --apply         # write them to Supabase
node scripts/legal-ingest.mts --apply --embed # and embed them for meaning search (needs VOYAGE_API_KEY)
```

`--apply` needs `NEXT_PUBLIC_SUPABASE_URL` and `SUPABASE_SERVICE_ROLE_KEY`, and
migration `0021_legal_ai.sql`. Running it again updates a source in place (by
its `slug`) and replaces its passages, so a corrected file is simply loaded
again. Files whose names start with `_` are ignored; `_template.md` is the
starting point.

## Where the text may come from

| Source | How to take it in |
| --- | --- |
| Laws, regulations, instructions | The official text as published in the Official Gazette (الجريدة الرسمية) or by the Legislation and Opinion Bureau (ديوان التشريع والرأي), copied by hand from the published document. `license: official public text`. |
| Court of Cassation and other judgments | Only judgments the Judicial Council or a court has published, or ones held under a licence or written permission from their publisher. Name the licence in `license`. |
| Commentary, textbooks, articles | Only with the author's or publisher's permission. `kind: commentary`; Ask a Lawyer always presents it as secondary, never as the law. |

The Legislation and Opinion Bureau's website loads its texts through an
encrypted interface. It must not be scraped or worked around: copy from the
published document, or ask the Bureau for the data. Commercial databases
(Qistas, Adaleh and others) need a licence before anything from them goes
in here.

Official legal texts are generally outside copyright in Jordan, but have a
licensed Jordanian lawyer confirm that for your use before relying on it.

## The file

An illustration of the shape. Every value in a real file is copied from, and
checked against, the official text.

```markdown
---
slug: landlords-tenants-law-11-1994
kind: law
title_ar: قانون المالكين والمستأجرين
title_en: [the official English title, if there is one]
number: 11
year: 1994
status: [in_force | amended | repealed, as of last_verified]
effective_date: YYYY-MM-DD
amendments: [Amending law] | YYYY-MM-DD | [Gazette issue and page]; [Next amending law] | YYYY-MM-DD | [...]
gazette_ref: [Official Gazette issue number, page, date]
url: https://[permanent link to the official text]
publisher: ديوان التشريع والرأي
license: official public text
verification: unverified
---

المادة 1
[The article's text, exactly as published.]

المادة 2
[repealed: by [the repealing law]]
[The article's text as it last stood, if you keep it for history.]
```

Header fields:

| Field | Required | Meaning |
| --- | --- | --- |
| `slug` | always | A stable id: lower-case letters, digits, hyphens. |
| `kind` | always | `constitution`, `law`, `temporary_law`, `regulation`, `instructions`, `decision`, `judgment`, `official_guidance` or `commentary`. |
| `title_ar` | always | The official Arabic title, exactly. |
| `url` | always | The permanent https link to the source. A licensed source with no public page gets its licensor's reference URL and `public_access: false`. |
| `publisher` | always | Who published the text. |
| `license` | always | `official public text`, or the licence or permission the text is held under. |
| `number`, `year` | legislation | Needed for exact citation lookups ("Article 5 of Law No. 11 of 1994"). |
| `court`, `case_number`, `year`, `decision_date` | judgments | `case_number` is the number alone (`1234`); the year goes in `year`. |
| `issue`, `holding` | judgments | The legal question, and what the court held on it. |
| `status` | | `in_force`, `amended`, `repealed` or `unknown` (the default). |
| `effective_date`, `repealed_date`, `repealed_by` | | Dates as `YYYY-MM-DD`. |
| `amendments` | | `law \| date \| gazette` entries separated by `;`, or a JSON array. |
| `gazette_ref` | | The Official Gazette publication reference. |
| `public_access` | | `false` for a licensed source readers cannot open. |
| `verification` | | `verified` once checked (see below); anything else is stored but never searched. |
| `verified_by`, `last_verified` | when verified | Who checked it, and the date (`YYYY-MM-DD`). |

In the text, legislation is split into articles at lines that start with
`المادة`, `مادة` or `Article` and a number (`المادة 5`, `المادة (5)`,
`المادة 5 مكررة`). Chapter lines (`الفصل`, `الباب`, `Chapter`, `Part`)
become the heading of the articles that follow. A line `[repealed]` or
`[amended: …]` right after an article's first line marks that article. A
judgment's or commentary's text is kept in paragraphs.

## Verifying a source

A source is `verified` when someone qualified (a licensed Jordanian lawyer,
or someone working under one) has compared the file, word for word, with the
official text, and has checked its status, amendments and dates as of
`last_verified`. Record that in the header and commit the file: the history of
this folder is the record of who verified what, and when.

Re-check every source at least every six months, and whenever a law changes.
The admin panel counts the sources verified more than 180 days ago under
"Due for re-verification".
