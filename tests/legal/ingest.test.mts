import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { mkdtempSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";
import { parseSourceFile } from "../../lib/legal/ingest.ts";

// Test files: the structure is real, the text is not law.
const law = (head: string, body: string) => `---\n${head}\n---\n${body}`;
const HEAD = [
  "slug: test-law-90-2001",
  "kind: law",
  "title_ar: قانون اختبار",
  "number: ٩٠",
  "year: 2001",
  "status: amended",
  "amendments: قانون معدل اختباري | 2011-05-01 | العدد 0000; قانون معدل ثانٍ | 2013-01-01",
  "url: https://www.lob.gov.jo/example",
  "publisher: ديوان التشريع والرأي",
  "license: official public text",
  "verification: verified",
  "verified_by: Test Reviewer",
  "last_verified: 2026-10-01",
].join("\n");

test("a law: header, preamble, chapters, articles and their marks", () => {
  const r = parseSourceFile(law(HEAD, [
    "نص تمهيدي اختباري.",
    "الفصل الأول: أحكام عامة",
    "المادة (1)",
    "نص اختباري للمادة الأولى.",
    "المادة ٢: نص اختباري للمادة الثانية.",
    "المادة 2 مكررة",
    "[amended: بموجب القانون المعدل الاختباري]",
    "نص اختباري مكرر.",
    "الباب الثاني",
    "Article 3",
    "[repealed]",
    "نص اختباري ملغى.",
    "الفصل في النزاع من اختصاص المحكمة.",
  ].join("\n")));
  assert.ok(!("errors" in r), JSON.stringify(r));
  assert.equal(r.source.number, "90");
  assert.equal(r.source.verification, "verified");
  assert.deepEqual(r.source.amendments, [
    { law: "قانون معدل اختباري", date: "2011-05-01", gazette: "العدد 0000" },
    { law: "قانون معدل ثانٍ", date: "2013-01-01" },
  ]);
  assert.deepEqual(r.passages.map(p => [p.ord, p.article, p.article_no, p.heading, p.status]), [
    [0, null, null, null, null],
    [1, "المادة 1", 1, "الفصل الأول: أحكام عامة", null],
    [2, "المادة 2", 2, "الفصل الأول: أحكام عامة", null],
    [3, "المادة 2 مكررة", 2, "الفصل الأول: أحكام عامة", "amended"],
    [4, "المادة 3", 3, "الباب الثاني", "repealed"],
  ]);
  assert.equal(r.passages[2].body, "نص اختباري للمادة الثانية.");
  assert.equal(r.passages[3].note, "بموجب القانون المعدل الاختباري");
  // "الفصل في النزاع" is part of the article's text, not a new chapter.
  assert.equal(r.passages[4].body, "نص اختباري ملغى.\nالفصل في النزاع من اختصاص المحكمة.");
  assert.ok(!r.passages.some(p => p.body.includes("[repealed]")));
});

test("a judgment: identified by court, case number and year, kept in paragraphs", () => {
  const r = parseSourceFile(law([
    "slug: test-cassation-1234-2019",
    "kind: judgment",
    "title_ar: حكم اختباري",
    "court: محكمة التمييز",
    "case_number: 1234/2019",
    "year: 2019",
    "decision_date: 2019-05-01",
    "url: https://www.jc.jo/example",
    "publisher: المجلس القضائي",
    "license: published by the Judicial Council",
  ].join("\n"), "الفقرة الأولى من نص اختباري.\n\nالفقرة الثانية."));
  assert.ok(!("errors" in r), JSON.stringify(r));
  assert.equal(r.source.case_number, "1234");
  assert.equal(r.passages.length, 2);
  assert.ok(r.warnings.some(w => w.startsWith("unverified")));
});

test("every missing or malformed piece of provenance is named", () => {
  const r = parseSourceFile(law([
    "slug: Bad Slug",
    "kind: statute",
    "url: http://insecure.example",
    "verification: verified",
    "last_verified: 01/10/2026",
  ].join("\n"), "المادة 1\nنص."));
  assert.ok("errors" in r);
  const all = r.errors.join(" | ");
  for (const want of ["kind must be", "slug:", "title_ar is required", "url is required", "publisher is required", "license is required", "last_verified must be", "verified sources need"]) {
    assert.ok(all.includes(want), `${want} in ${all}`);
  }
  assert.deepEqual(parseSourceFile("no header"), { errors: ["The file must start with a header between two lines of ---."] });
  const judgment = parseSourceFile(law("slug: j\nkind: judgment\ntitle_ar: حكم\nurl: https://a.jo\npublisher: p\nlicense: l", "نص."));
  assert.ok("errors" in judgment && judgment.errors.some(e => e.includes("court")) && judgment.errors.some(e => e.includes("case_number")));
});

test("a long article is cut at paragraph breaks and keeps its number", () => {
  const para = "نص اختباري طويل. ".repeat(300);
  const r = parseSourceFile(law(HEAD, `المادة 1\n${Array.from({ length: 8 }, () => para).join("\n")}`));
  assert.ok(!("errors" in r));
  assert.ok(r.passages.length > 1);
  assert.ok(r.passages.every(p => p.article === "المادة 1" && p.body.length <= 18000));
  assert.deepEqual(r.passages.map(p => p.ord), r.passages.map((_, i) => i));
});

test("warnings for a repeated article and for text with no articles", () => {
  const twice = parseSourceFile(law(HEAD, "المادة 1\nأ\nالمادة 1\nب"));
  assert.ok(!("errors" in twice) && twice.warnings.some(w => w.includes("appears more than once")));
  const none = parseSourceFile(law(HEAD, "نص بلا مواد."));
  assert.ok(!("errors" in none) && none.warnings.some(w => w.startsWith("no articles found")));
});

test("the command: a dry run reads and checks, and writes nothing", () => {
  const dir = mkdtempSync(join(tmpdir(), "legal-src-"));
  writeFileSync(join(dir, "test-law.md"), law(HEAD, "المادة 1\nنص اختباري."));
  writeFileSync(join(dir, "_draft.md"), "ignored");
  writeFileSync(join(dir, "README.md"), "ignored");
  const ok = spawnSync(process.execPath, ["scripts/legal-ingest.mts", dir], { encoding: "utf8", env: { ...process.env, NEXT_PUBLIC_SUPABASE_URL: "", SUPABASE_SERVICE_ROLE_KEY: "" } });
  assert.equal(ok.status, 0, ok.stdout + ok.stderr);
  assert.match(ok.stdout, /✓ test-law\.md {2}test-law-90-2001 {2}law {2}verified {2}1 passages, 1 with article numbers/);
  assert.match(ok.stdout, /Dry run: 1 source\(s\) read/);
  writeFileSync(join(dir, "broken.md"), "no header");
  const bad = spawnSync(process.execPath, ["scripts/legal-ingest.mts", dir], { encoding: "utf8" });
  assert.equal(bad.status, 1);
  assert.match(bad.stdout, /✗ broken\.md/);
  assert.match(bad.stdout, /nothing was written/);
});
