/**
 * Builders for Ask a Lawyer's tests: small PDFs and Word files with exactly
 * the features a test needs, an in-memory library, and library passages.
 *
 * The passages are written for these tests. They are not real legal text and
 * must never be loaded into the library.
 */
import { crc32, deflateRawSync, deflateSync } from "node:zlib";
import type { Hit, LibraryDb } from "../../lib/legal/library.ts";

/* ── PDF ─────────────────────────────────────────────────────────────── */

export function pdf(o: { pages?: number; fonts?: boolean; images?: boolean; extra?: string; hidden?: string; eof?: boolean } = {}): Buffer {
  const pages = o.pages ?? 1;
  const parts: string[] = ["%PDF-1.7\n%âãÏÓ\n"];
  parts.push(`1 0 obj << /Type /Catalog /Pages 2 0 R >> endobj\n`);
  parts.push(`2 0 obj << /Type /Pages /Count ${pages} /Kids [] >> endobj\n`);
  for (let i = 0; i < pages; i++) {
    parts.push(`${10 + i} 0 obj << /Type /Page /Parent 2 0 R /Resources << ${o.fonts !== false ? "/Font << /F1 3 0 R >>" : ""} ${o.images ? "/XObject << /Im1 4 0 R >>" : ""} >> >> endobj\n`);
  }
  if (o.fonts !== false) parts.push(`3 0 obj << /Type /Font /Subtype /Type1 /BaseFont /Helvetica >> endobj\n`);
  if (o.images) parts.push(`4 0 obj << /Type /XObject /Subtype /Image /Width 10 /Height 10 /Length 0 >> stream\n\nendstream endobj\n`);
  if (o.extra) parts.push(`${o.extra}\n`);
  const head = Buffer.from(parts.join(""), "latin1");
  let hidden = Buffer.alloc(0);
  if (o.hidden) {
    const data = deflateSync(Buffer.from(o.hidden, "latin1"));
    hidden = Buffer.concat([
      Buffer.from(`90 0 obj << /Type /ObjStm /N 1 /First 4 /Filter /FlateDecode /Length ${data.length} >>\nstream\n`, "latin1"),
      data,
      Buffer.from("\nendstream\nendobj\n", "latin1"),
    ]);
  }
  const tail = Buffer.from(`trailer << /Root 1 0 R >>\n${o.eof === false ? "" : "%%EOF\n"}`, "latin1");
  return Buffer.concat([head, hidden, tail]);
}

/* ── ZIP / DOCX ──────────────────────────────────────────────────────── */

export type ZipFile = { name: string; data: string | Buffer; stored?: boolean; claimSize?: number; flags?: number };

export function zip(files: ZipFile[]): Buffer {
  const locals: Buffer[] = [];
  const centrals: Buffer[] = [];
  let offset = 0;
  for (const f of files) {
    const raw = typeof f.data === "string" ? Buffer.from(f.data, "utf8") : f.data;
    const body = f.stored ? raw : deflateRawSync(raw);
    const name = Buffer.from(f.name, "utf8");
    const crc = crc32(raw);
    const usize = f.claimSize ?? raw.length;
    const local = Buffer.alloc(30);
    local.writeUInt32LE(0x04034b50, 0);
    local.writeUInt16LE(20, 4);
    local.writeUInt16LE(f.flags ?? 0, 6);
    local.writeUInt16LE(f.stored ? 0 : 8, 8);
    local.writeUInt32LE(crc, 14);
    local.writeUInt32LE(body.length, 18);
    local.writeUInt32LE(usize, 22);
    local.writeUInt16LE(name.length, 26);
    locals.push(local, name, body);
    const central = Buffer.alloc(46);
    central.writeUInt32LE(0x02014b50, 0);
    central.writeUInt16LE(20, 4);
    central.writeUInt16LE(20, 6);
    central.writeUInt16LE(f.flags ?? 0, 8);
    central.writeUInt16LE(f.stored ? 0 : 8, 10);
    central.writeUInt32LE(crc, 16);
    central.writeUInt32LE(body.length, 20);
    central.writeUInt32LE(usize, 24);
    central.writeUInt16LE(name.length, 28);
    central.writeUInt32LE(offset, 42);
    centrals.push(central, name);
    offset += local.length + name.length + body.length;
  }
  const cd = Buffer.concat(centrals);
  const end = Buffer.alloc(22);
  end.writeUInt32LE(0x06054b50, 0);
  end.writeUInt16LE(files.length, 8);
  end.writeUInt16LE(files.length, 10);
  end.writeUInt32LE(cd.length, 12);
  end.writeUInt32LE(offset, 16);
  return Buffer.concat([...locals, cd, end]);
}

const TYPES = `<?xml version="1.0" encoding="UTF-8"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/></Types>`;

export const wordBody = (inner: string) =>
  `<?xml version="1.0" encoding="UTF-8"?><w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main" xmlns:mc="http://schemas.openxmlformats.org/markup-compatibility/2006"><w:body>${inner}</w:body></w:document>`;

export const para = (text: string) => `<w:p><w:r><w:t xml:space="preserve">${text}</w:t></w:r></w:p>`;

export function docx(inner: string, extra: ZipFile[] = [], types = TYPES): Buffer {
  return zip([
    { name: "[Content_Types].xml", data: types },
    { name: "word/document.xml", data: wordBody(inner) },
    { name: "word/_rels/document.xml.rels", data: `<?xml version="1.0"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"></Relationships>` },
    ...extra,
  ]);
}

/* ── The library ─────────────────────────────────────────────────────── */

let nextPassage = 1;

export function hit(o: Partial<Hit> = {}): Hit {
  const id = o.passageId ?? nextPassage++;
  return {
    passageId: id,
    sourceId: o.sourceId ?? `src-${o.slug ?? "test-law"}`,
    slug: "test-law",
    kind: "law",
    tier: "primary",
    titleAr: "قانون اختبار الإيجار",
    titleEn: null,
    number: "90",
    year: 2001,
    court: null,
    caseNumber: null,
    decisionDate: null,
    issue: null,
    holding: null,
    status: "in_force",
    passageStatus: null,
    effectiveDate: "2001-06-01",
    repealedDate: null,
    repealedBy: null,
    amendments: [],
    gazetteRef: "الجريدة الرسمية، العدد 0000",
    url: "https://www.lob.gov.jo/test-law",
    publisher: "ديوان التشريع والرأي",
    publicAccess: true,
    verifiedBy: "Test Reviewer",
    lastVerified: "2026-10-01",
    article: "المادة 5",
    articleNo: 5,
    heading: null,
    body: "نص اختباري: لا يجوز إخلاء المأجور قبل انتهاء مدة العقد إلا في الحالات المبينة في هذا القانون.",
    note: null,
    ...o,
  };
}

/** An in-memory library: search matches any query word in a passage; lookup is exact. */
export class FakeLibrary implements LibraryDb {
  calls: { fn: string; args: Record<string, unknown> }[] = [];
  failing = false;
  hits: Hit[];
  constructor(hits: Hit[] = []) {
    this.hits = hits;
  }

  async rpc(fn: "legal_search" | "legal_lookup", args: Record<string, unknown>) {
    this.calls.push({ fn, args });
    if (this.failing) return { data: null, error: { message: "down" } };
    const row = (h: Hit) => ({
      passage_id: h.passageId,
      source_id: h.sourceId,
      slug: h.slug,
      kind: h.kind,
      tier: h.tier,
      title_ar: h.titleAr,
      title_en: h.titleEn,
      number: h.number,
      year: h.year,
      court: h.court,
      case_number: h.caseNumber,
      decision_date: h.decisionDate,
      issue: h.issue,
      holding: h.holding,
      status: h.status,
      passage_status: h.passageStatus,
      effective_date: h.effectiveDate,
      repealed_date: h.repealedDate,
      repealed_by: h.repealedBy,
      amendments: h.amendments,
      gazette_ref: h.gazetteRef,
      url: h.url,
      publisher: h.publisher,
      public_access: h.publicAccess,
      verified_by: h.verifiedBy,
      last_verified: h.lastVerified,
      article: h.article,
      article_no: h.articleNo,
      heading: h.heading,
      body: h.body,
      note: h.note,
      score: 1,
    });
    if (fn === "legal_search") {
      const words = String(args.p_query).split(/\s+/).filter(w => w.length > 2);
      const kinds = args.p_kinds as string[] | null;
      const found = this.hits.filter(h => (!kinds || kinds.includes(h.kind)) && words.some(w => h.body.includes(w) || h.titleAr.includes(w)));
      return { data: found.slice(0, Number(args.p_limit) || 8).map(row), error: null };
    }
    const found = this.hits.filter(h =>
      args.p_case_number
        ? h.kind === "judgment" && h.caseNumber === args.p_case_number && (args.p_year == null || h.year === args.p_year)
        : h.kind !== "judgment" &&
          ((args.p_number != null && h.number === args.p_number && (args.p_year == null || h.year === args.p_year)) ||
            (args.p_number == null && args.p_title != null && h.titleAr.includes(String(args.p_title)))) &&
          (args.p_article == null || h.articleNo === args.p_article)
    );
    return { data: found.map(row), error: null };
  }

  async counts() {
    return this.failing ? null : [...new Map(this.hits.map(h => [h.sourceId, { kind: h.kind }])).values()];
  }
}
