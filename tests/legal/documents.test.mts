import assert from "node:assert/strict";
import { test } from "node:test";
import { deflateSync } from "node:zlib";
import { cleanName, prepareDocument } from "../../lib/legal/documents.ts";
import { docx, para, pdf, zip } from "./fixtures.mts";

const prep = (b: Buffer) => prepareDocument(new Uint8Array(b));
const rejected = (b: Buffer) => {
  const r = prep(b);
  return "error" in r ? r.error : null;
};

/* ── PDF ── */

test("a PDF with text is kept whole, its pages counted, and not taken for a scan", () => {
  const r = prep(pdf({ pages: 3 }));
  assert.ok(!("error" in r));
  assert.equal(r.kind, "pdf");
  assert.equal(r.mediaType, "application/pdf");
  assert.equal(r.pages, 3);
  assert.equal(r.scanned, false);
});

test("a PDF of page images and no fonts is a scan", () => {
  const r = prep(pdf({ pages: 2, fonts: false, images: true }));
  assert.ok(!("error" in r) && r.scanned === true);
});

test("encrypted or password-protected PDFs are refused", () => {
  assert.equal(rejected(pdf({ extra: "5 0 obj << /Filter /Standard /V 2 >> endobj\ntrailer << /Encrypt 5 0 R >>" })), "encrypted");
});

test("PDFs carrying scripts, launch actions, attachments or dynamic forms are refused", () => {
  for (const extra of [
    "6 0 obj << /S /JavaScript /JS (app.alert(1)) >> endobj",
    "6 0 obj << /OpenAction << /S /Launch /F (cmd.exe) >> >> endobj",
    "6 0 obj << /Names << /EmbeddedFiles 7 0 R >> >> endobj",
    "6 0 obj << /AcroForm << /XFA 8 0 R >> >> endobj",
    "6 0 obj << /Type /Annot /Subtype /RichMedia >> endobj",
  ]) {
    assert.equal(rejected(pdf({ extra })), "active_content", extra);
  }
});

test("a script hidden inside a compressed object stream is still found", () => {
  assert.equal(rejected(pdf({ hidden: "6 0 << /S /JavaScript /JS (x) >>" })), "active_content");
});

test("pages hidden inside an object stream are counted", () => {
  const hidden = Array.from({ length: 40 }, (_, i) => `${100 + i} 0 << /Type /Page /Parent 2 0 R >>`).join("\n");
  const r = prep(pdf({ pages: 0, hidden }));
  assert.equal("error" in r ? r.error : null, "too_many_pages");
});

test("too many pages, a truncated file, and an empty file are refused", () => {
  assert.equal(rejected(pdf({ pages: 31 })), "too_many_pages");
  assert.ok(!("error" in prep(pdf({ pages: 30 }))));
  assert.equal(rejected(pdf({ eof: false })), "damaged");
  assert.equal(rejected(Buffer.alloc(0)), "empty");
});

test("the size limit holds whatever the file is", () => {
  assert.equal(rejected(Buffer.concat([pdf(), Buffer.alloc(4_000_001)])), "too_big");
});

/* ── Word ── */

test("Word text comes out with paragraphs, tabs, breaks and table cells", () => {
  const body =
    para("عقد إيجار") +
    `<w:p><w:r><w:t>Rent:</w:t></w:r><w:r><w:tab/><w:t>500 JOD</w:t><w:br/><w:t>monthly</w:t></w:r></w:p>` +
    `<w:tbl><w:tr><w:tc>${para("Clause")}</w:tc><w:tc>${para("Term")}</w:tc></w:tr></w:tbl>` +
    para("&lt;tenant&gt; &amp; landlord &#1575;");
  const r = prep(docx(body));
  assert.ok(!("error" in r));
  assert.equal(r.kind, "docx");
  assert.equal(r.mediaType, "text/plain");
  const text = r.body.toString("utf8");
  assert.match(text, /^عقد إيجار\nRent:\t500 JOD\nmonthly\n/);
  assert.match(text, /\nClause \| Term\n/);
  assert.match(text, /<tenant> & landlord ا$/);
});

test("deleted text, field codes and fallback copies are left out", () => {
  const body =
    `<w:p><w:del><w:r><w:delText>struck clause</w:delText></w:r></w:del><w:r><w:t>kept clause</w:t></w:r></w:p>` +
    `<w:p><w:r><w:instrText> HYPERLINK "http://x" </w:instrText></w:r></w:p>` +
    `<w:p><mc:AlternateContent><mc:Choice><w:r><w:t>box</w:t></w:r></mc:Choice><mc:Fallback><w:r><w:t>box</w:t></w:r></mc:Fallback></mc:AlternateContent></w:p>`;
  const r = prep(docx(body));
  assert.ok(!("error" in r));
  const text = r.body.toString("utf8");
  assert.ok(!text.includes("struck"));
  assert.ok(!text.includes("HYPERLINK"));
  assert.equal(text.match(/box/g)?.length, 1);
  assert.ok(text.includes("kept clause"));
});

test("Word files with macros, ActiveX, embedded objects or remote templates are refused", () => {
  assert.equal(rejected(docx(para("x"), [{ name: "word/vbaProject.bin", data: "macro" }])), "macros");
  assert.equal(
    rejected(docx(para("x"), [], `<Types><Default ContentType="application/vnd.ms-word.document.macroEnabled.main+xml"/></Types>`)),
    "macros"
  );
  assert.equal(rejected(docx(para("x"), [{ name: "word/activeX/activeX1.xml", data: "<x/>" }])), "active_content");
  assert.equal(rejected(docx(para("x"), [{ name: "word/embeddings/oleObject1.bin", data: "obj" }])), "active_content");
  const remote = `<Relationships><Relationship Id="r1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/attachedTemplate" Target="http://evil.example/t.dotm" TargetMode="External"/></Relationships>`;
  assert.equal(rejected(docx(para("x"), [{ name: "word/_rels/settings.xml.rels", data: remote }])), "active_content");
  // An ordinary external hyperlink is fine.
  const link = `<Relationships><Relationship Id="r2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/hyperlink" Target="https://lob.gov.jo" TargetMode="External"/></Relationships>`;
  assert.ok(!("error" in prep(docx(para("x"), [{ name: "word/_rels/footnotes.xml.rels", data: link }]))));
});

test("zip bombs and encrypted archives are refused before anything is expanded", () => {
  const bomb = zip([
    { name: "[Content_Types].xml", data: "<Types/>" },
    { name: "word/document.xml", data: "x".repeat(2000), claimSize: 900_000_000 },
  ]);
  assert.equal(rejected(bomb), "too_big");
  const ratio = zip([
    { name: "[Content_Types].xml", data: "<Types/>" },
    { name: "word/document.xml", data: Buffer.alloc(30_000_000) },
  ]);
  assert.equal(rejected(ratio), "too_big");
  const locked = zip([
    { name: "[Content_Types].xml", data: "<Types/>" },
    { name: "word/document.xml", data: "secret", flags: 1 },
  ]);
  assert.equal(rejected(locked), "encrypted");
});

test("a size claim smaller than the real content cannot get past the cap", () => {
  const liar = zip([
    { name: "[Content_Types].xml", data: "<Types/>" },
    { name: "word/document.xml", data: wordLike(50_000_000), claimSize: 1000 },
  ]);
  assert.equal(rejected(liar), "damaged");
});

function wordLike(n: number) {
  return Buffer.alloc(n, "a");
}

test("a zip that is not a Word document, an old .doc, and a Word file without text", () => {
  assert.equal(rejected(zip([{ name: "a.txt", data: "hello" }])), "unsupported");
  assert.equal(rejected(Buffer.from([0xd0, 0xcf, 0x11, 0xe0, 0xa1, 0xb1, 0x1a, 0xe1, 0, 0, 0])), "old_word");
  assert.equal(rejected(docx(`<w:p><w:r><w:drawing/></w:r></w:p>`)), "no_text");
});

/* ── Text ── */

test("text files: UTF-8, UTF-16 with a byte order mark, and Windows Arabic", () => {
  const utf8 = prep(Buffer.from("عقد إيجار\r\nالمادة 1", "utf8"));
  assert.ok(!("error" in utf8) && utf8.body.toString("utf8") === "عقد إيجار\nالمادة 1");
  const u16 = Buffer.concat([Buffer.from([0xff, 0xfe]), Buffer.from("lease terms", "utf16le")]);
  const r16 = prep(u16);
  assert.ok(!("error" in r16) && r16.body.toString("utf8") === "lease terms");
  // "عقد" in Windows-1256: ع=0xDA ق=0xDE د=0xCF
  const cp1256 = prep(Buffer.from([0xda, 0xde, 0xcf, 0x20, 0x31]));
  assert.ok(!("error" in cp1256));
  assert.equal(cp1256.body.toString("utf8"), "عقد 1");
});

test("binary data is not text", () => {
  assert.equal(rejected(Buffer.from([0x00, 0x01, 0x02, 0x03, 0x41])), "not_text");
  assert.equal(rejected(Buffer.from("\u0001\u0002\u0003\u0004\u0005\u0006".repeat(20), "latin1")), "not_text");
});

test("images are kept as they are; GIFs are not taken", () => {
  const jpeg = prep(Buffer.from([0xff, 0xd8, 0xff, 0xe0, 0, 0x10]));
  assert.ok(!("error" in jpeg) && jpeg.kind === "image" && jpeg.mediaType === "image/jpeg" && jpeg.scanned);
  const png = prep(Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 0, 0]));
  assert.ok(!("error" in png) && png.mediaType === "image/png");
  const webp = prep(Buffer.concat([Buffer.from("RIFF"), Buffer.alloc(4), Buffer.from("WEBPVP8 ")]));
  assert.ok(!("error" in webp) && webp.mediaType === "image/webp");
  assert.equal(rejected(Buffer.from("GIF89a....")), "unsupported");
});

test("file names lose direction overrides, controls and path separators", () => {
  assert.equal(cleanName("lease\u202e.fdp.exe"), "lease.fdp.exe");
  assert.equal(cleanName("../../etc/passwd"), ".._.._etc_passwd");
  assert.equal(cleanName("  "), "document");
  assert.equal(cleanName("a".repeat(300)).length, 120);
  assert.equal(cleanName(undefined), "document");
});

test("a PDF header hidden after junk in the first kilobyte is still a PDF", () => {
  const r = prep(Buffer.concat([Buffer.from("junk\n"), pdf()]));
  assert.ok(!("error" in r) && r.kind === "pdf");
  // Deflate output alone is not a document.
  assert.equal(rejected(deflateSync(Buffer.from("x".repeat(100)))), "not_text");
});
