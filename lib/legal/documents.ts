/**
 * Uploaded documents: what a file really is, whether it is safe to keep and
 * to show the model, and its text where we can read it ourselves.
 *
 *   PDF    kept as it is; the model reads it, text and page images, which is
 *          how a scanned contract is read (OCR by the model's vision). A PDF
 *          with no fonts is a scan: readable, but its quotations cannot be
 *          tied to the page automatically, and the page says so.
 *   DOCX   text extracted here, from the main document part; only the text
 *          is kept, never the file.
 *   TXT    decoded here (UTF-8, UTF-16 with a byte order mark, or Windows
 *          Arabic, 1256); only the text is kept.
 *   Images JPEG, PNG or WebP photos or scans of a page; kept as they are.
 *
 * Screening, in place of a virus scanner (none is wired in; see LEGAL-AI.md):
 * the type is read from the bytes, never the name or the browser's word for
 * it. Refused: encrypted or password-protected files; PDFs carrying scripts,
 * launch actions, attached files, rich media or dynamic (XFA) forms; Word
 * files with macros, ActiveX controls, embedded objects or remote templates;
 * archives that expand past fixed limits (zip bombs) or that are encrypted;
 * and anything else. Nothing uploaded is ever executed, rendered on our
 * servers, or served back to a browser.
 */
import { inflateRawSync, inflateSync } from "node:zlib";
import { DOCS } from "./config.ts";

export type DocKind = "pdf" | "docx" | "txt" | "image";
export type MediaType = "application/pdf" | "text/plain" | "image/jpeg" | "image/png" | "image/webp";

export type Prepared = {
  kind: DocKind;
  mediaType: MediaType;
  /** What is kept (encrypted) and shown to the model: the PDF or image, or the extracted text as UTF-8. */
  body: Buffer;
  pages: number | null;
  scanned: boolean;
  textChars: number | null;
};

export type Rejection =
  | "empty"
  | "too_big"
  | "unsupported"
  | "old_word"
  | "encrypted"
  | "active_content"
  | "macros"
  | "damaged"
  | "too_many_pages"
  | "not_text"
  | "no_text"
  | "too_long";

const startsWith = (b: Uint8Array, sig: number[], at = 0) => sig.every((v, i) => b[at + i] === v);

function sniff(b: Buffer): "pdf" | "zip" | "ole" | "jpeg" | "png" | "webp" | "gif" | null {
  if (b.subarray(0, 1024).includes("%PDF-")) return "pdf";
  if (startsWith(b, [0x50, 0x4b, 0x03, 0x04])) return "zip";
  if (startsWith(b, [0xd0, 0xcf, 0x11, 0xe0, 0xa1, 0xb1, 0x1a, 0xe1])) return "ole";
  if (startsWith(b, [0xff, 0xd8, 0xff])) return "jpeg";
  if (startsWith(b, [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a])) return "png";
  if (startsWith(b, [0x52, 0x49, 0x46, 0x46]) && startsWith(b, [0x57, 0x45, 0x42, 0x50], 8)) return "webp";
  if (startsWith(b, [0x47, 0x49, 0x46, 0x38])) return "gif";
  return null;
}

/** The single entry point: a file in, a prepared document or the reason it was refused. */
export function prepareDocument(bytes: Uint8Array): Prepared | { error: Rejection } {
  const b = Buffer.from(bytes);
  if (b.length === 0) return { error: "empty" };
  if (b.length > DOCS.maxBytes) return { error: "too_big" };
  switch (sniff(b)) {
    case "pdf": {
      const p = inspectPdf(b);
      if ("error" in p) return p;
      return { kind: "pdf", mediaType: "application/pdf", body: b, pages: p.pages, scanned: p.scanned, textChars: null };
    }
    case "zip": {
      const t = docxText(b);
      if (typeof t !== "string") return t;
      return textDoc("docx", t);
    }
    case "ole":
      return { error: "old_word" };
    case "jpeg":
      return { kind: "image", mediaType: "image/jpeg", body: b, pages: 1, scanned: true, textChars: null };
    case "png":
      return { kind: "image", mediaType: "image/png", body: b, pages: 1, scanned: true, textChars: null };
    case "webp":
      return { kind: "image", mediaType: "image/webp", body: b, pages: 1, scanned: true, textChars: null };
    case "gif":
      return { error: "unsupported" };
    default: {
      const t = decodeText(b);
      if (t === null) return { error: "not_text" };
      return textDoc("txt", t);
    }
  }
}

function textDoc(kind: "docx" | "txt", raw: string): Prepared | { error: Rejection } {
  const text = raw
    .replace(/\r\n?/g, "\n")
    .replace(/[ \t]+\n/g, "\n")
    .replace(/\n{3,}/g, "\n\n")
    .trim();
  if (!text) return { error: kind === "docx" ? "no_text" : "empty" };
  if (text.length > DOCS.maxTextChars) return { error: "too_long" };
  return { kind, mediaType: "text/plain", body: Buffer.from(text, "utf8"), pages: null, scanned: false, textChars: text.length };
}

/* ── PDF ─────────────────────────────────────────────────────────────── */

// Object streams (PDF 1.5+) hide page and font objects inside compressed
// data, so they are expanded before anything is counted, within limits.
const MAX_EXPANDED = 30_000_000;
const MAX_STREAMS = 400;

function expandObjectStreams(raw: string): string {
  const parts: string[] = [];
  let budget = MAX_EXPANDED;
  let seen = 0;
  const re = /stream\r?\n/g;
  let m: RegExpExecArray | null;
  while ((m = re.exec(raw)) && seen < MAX_STREAMS && budget > 0) {
    const dict = raw.slice(Math.max(0, m.index - 600), m.index);
    const open = dict.lastIndexOf("<<");
    if (open < 0) continue;
    const header = dict.slice(open);
    if (!/\/ObjStm\b/.test(header) || !/\/FlateDecode\b/.test(header)) continue;
    const start = m.index + m[0].length;
    const end = raw.indexOf("endstream", start);
    if (end < 0) break;
    seen += 1;
    try {
      const out = inflateSync(Buffer.from(raw.slice(start, end), "latin1"), { maxOutputLength: Math.min(budget, 8_000_000) });
      budget -= out.length;
      parts.push(out.toString("latin1"));
    } catch {
      /* a stream we cannot expand is skipped, not fatal */
    }
    re.lastIndex = end;
  }
  return parts.join("\n");
}

export function inspectPdf(b: Buffer): { pages: number | null; scanned: boolean } | { error: Rejection } {
  const raw = b.toString("latin1");
  if (!raw.slice(0, 1024).includes("%PDF-")) return { error: "damaged" };
  // A truncated upload ends without the trailer marker.
  if (!raw.includes("%%EOF")) return { error: "damaged" };
  const all = `${raw}\n${expandObjectStreams(raw)}`;
  if (/\/Encrypt\b/.test(all)) return { error: "encrypted" };
  if (/\/(JavaScript|JS|Launch|RichMedia|XFA|EmbeddedFiles?)\b/.test(all)) return { error: "active_content" };

  let pages = (all.match(/\/Type\s*\/Page(?![A-Za-z])/g) ?? []).length;
  if (!pages) {
    const counts = [...all.matchAll(/\/Type\s*\/Pages\b[^]{0,200}?\/Count\s+(\d+)/g)].map(x => Number(x[1]));
    pages = counts.length ? Math.max(...counts) : 0;
  }
  if (pages > DOCS.maxPages) return { error: "too_many_pages" };
  const hasFonts = /\/Font\b|\/FontDescriptor\b/.test(all);
  const hasImages = /\/Subtype\s*\/Image\b/.test(all);
  return { pages: pages || null, scanned: !hasFonts && hasImages };
}

/* ── DOCX ────────────────────────────────────────────────────────────── */

type ZipEntry = { name: string; method: number; flags: number; csize: number; usize: number; offset: number };

const ZIP_LIMITS = { entries: 3000, entryBytes: 40_000_000, totalBytes: 120_000_000, ratio: 200 };

/** The archive's directory, or a reason to refuse it. Reads only; never trusts a size it has not checked. */
export function readZip(b: Buffer): ZipEntry[] | { error: Rejection } {
  const from = Math.max(0, b.length - 65_557);
  let eocd = -1;
  for (let i = b.length - 22; i >= from; i--) {
    if (b.readUInt32LE(i) === 0x06054b50) {
      eocd = i;
      break;
    }
  }
  if (eocd < 0) return { error: "damaged" };
  const count = b.readUInt16LE(eocd + 10);
  const cdOffset = b.readUInt32LE(eocd + 16);
  if (count > ZIP_LIMITS.entries) return { error: "damaged" };
  if (cdOffset === 0xffffffff || count === 0xffff) return { error: "unsupported" };
  const out: ZipEntry[] = [];
  let p = cdOffset;
  let total = 0;
  for (let i = 0; i < count; i++) {
    if (p + 46 > b.length || b.readUInt32LE(p) !== 0x02014b50) return { error: "damaged" };
    const flags = b.readUInt16LE(p + 8);
    const method = b.readUInt16LE(p + 10);
    const csize = b.readUInt32LE(p + 20);
    const usize = b.readUInt32LE(p + 24);
    const nameLen = b.readUInt16LE(p + 28);
    const extraLen = b.readUInt16LE(p + 30);
    const commentLen = b.readUInt16LE(p + 32);
    const offset = b.readUInt32LE(p + 42);
    const name = b.subarray(p + 46, p + 46 + nameLen).toString("utf8");
    p += 46 + nameLen + extraLen + commentLen;
    if (flags & 0x1) return { error: "encrypted" };
    if (csize === 0xffffffff || usize === 0xffffffff || offset === 0xffffffff) return { error: "unsupported" };
    if (usize > ZIP_LIMITS.entryBytes) return { error: "too_big" };
    if (usize > 1_000_000 && usize / Math.max(csize, 1) > ZIP_LIMITS.ratio) return { error: "too_big" };
    total += usize;
    if (total > ZIP_LIMITS.totalBytes) return { error: "too_big" };
    out.push({ name, method, flags, csize, usize, offset });
  }
  return out;
}

export function zipEntry(b: Buffer, e: ZipEntry): Buffer | null {
  if (e.offset + 30 > b.length || b.readUInt32LE(e.offset) !== 0x04034b50) return null;
  const start = e.offset + 30 + b.readUInt16LE(e.offset + 26) + b.readUInt16LE(e.offset + 28);
  const data = b.subarray(start, start + e.csize);
  if (data.length !== e.csize) return null;
  try {
    if (e.method === 0) return data.length <= ZIP_LIMITS.entryBytes ? Buffer.from(data) : null;
    // The declared size is a claim; the cap is what holds.
    if (e.method === 8) return inflateRawSync(data, { maxOutputLength: Math.min(e.usize + 1, ZIP_LIMITS.entryBytes) });
  } catch {
    return null;
  }
  return null;
}

// Relationships that make Word fetch or run something: a remote template,
// an embedded or linked object, a frame, a sub-document.
const RISKY_REL = /Type="[^"]*\/(attachedTemplate|oleObject|frame|subDocument|package)"[^>]*TargetMode="External"|TargetMode="External"[^>]*Type="[^"]*\/(attachedTemplate|oleObject|frame|subDocument|package)"/i;

export function docxText(b: Buffer): string | { error: Rejection } {
  const entries = readZip(b);
  if (!Array.isArray(entries)) return entries;
  const byName = new Map(entries.map(e => [e.name, e]));
  const types = byName.get("[Content_Types].xml");
  const main = byName.get("word/document.xml");
  if (!types || !main) return { error: "unsupported" };

  if (entries.some(e => /vbaProject\.bin$|vbaData\.xml$/i.test(e.name))) return { error: "macros" };
  const typesXml = zipEntry(b, types)?.toString("utf8") ?? "";
  if (/macroEnabled/i.test(typesXml)) return { error: "macros" };
  if (entries.some(e => /^word\/(activeX|embeddings)\//i.test(e.name))) return { error: "active_content" };
  for (const e of entries) {
    if (!/^word\/_rels\/.+\.rels$/i.test(e.name)) continue;
    const rels = zipEntry(b, e)?.toString("utf8") ?? "";
    for (const rel of rels.match(/<Relationship\b[^>]*>/g) ?? []) {
      if (RISKY_REL.test(rel)) return { error: "active_content" };
    }
  }

  const xml = zipEntry(b, main);
  if (!xml) return { error: "damaged" };
  return wordXmlText(xml.toString("utf8"));
}

const ENTITY: Record<string, string> = { amp: "&", lt: "<", gt: ">", quot: '"', apos: "'" };

/** The visible text of a WordprocessingML body: paragraphs, tabs, breaks and table cells; no deleted text or field codes. */
export function wordXmlText(xml: string): string {
  return xml
    .replace(/<mc:Fallback\b[^]*?<\/mc:Fallback>/g, "")
    .replace(/<w:delText\b[^>]*>[^]*?<\/w:delText>/g, "")
    .replace(/<w:instrText\b[^>]*>[^]*?<\/w:instrText>/g, "")
    // A paragraph that ends a table cell ends the cell, not the line.
    .replace(/<\/w:p>\s*<\/w:tc>/g, "</w:tc>")
    .replace(/<w:tab\/>/g, "\t")
    .replace(/<w:(br|cr)\b[^>]*\/>/g, "\n")
    .replace(/<\/w:p>/g, "\n")
    .replace(/<\/w:tc>/g, " | ")
    .replace(/<\/w:tr>/g, "\n")
    .replace(/<[^>]+>/g, "")
    .replace(/&(#x[0-9a-f]+|#\d+|amp|lt|gt|quot|apos);/gi, (_, e: string) => {
      if (e[0] !== "#") return ENTITY[e.toLowerCase()] ?? "";
      const n = e[1] === "x" || e[1] === "X" ? parseInt(e.slice(2), 16) : parseInt(e.slice(1), 10);
      return n > 0 && n < 0x110000 ? String.fromCodePoint(n) : "";
    })
    .replace(/ \| \n/g, "\n");
}

/* ── Text ────────────────────────────────────────────────────────────── */

export function decodeText(b: Buffer): string | null {
  let text: string | null = null;
  if (startsWith(b, [0xef, 0xbb, 0xbf])) text = new TextDecoder("utf-8").decode(b.subarray(3));
  else if (startsWith(b, [0xff, 0xfe])) text = new TextDecoder("utf-16le").decode(b.subarray(2));
  else if (startsWith(b, [0xfe, 0xff])) text = new TextDecoder("utf-16be").decode(b.subarray(2));
  else {
    if (b.includes(0)) return null;
    try {
      text = new TextDecoder("utf-8", { fatal: true }).decode(b);
    } catch {
      // Arabic text saved by older Windows software.
      try {
        text = new TextDecoder("windows-1256").decode(b);
      } catch {
        return null;
      }
    }
  }
  // Binary that happened to decode: too many control characters to be prose.
  const controls = (text.match(/[\u0000-\u0008\u000e-\u001f\u007f]/g) ?? []).length;
  if (controls > Math.max(4, text.length * 0.01)) return null;
  return text.replace(/[\u0000-\u0008\u000b\u000c\u000e-\u001f\u007f]/g, "");
}

/** A file name fit to keep and to show: no control or direction characters, bounded. */
export function cleanName(name: unknown): string {
  const s = typeof name === "string" ? name : "";
  const cleaned = s
    .replace(/[\u0000-\u001f\u007f\u200b-\u200f\u202a-\u202e\u2066-\u2069\ue000-\uf8ff]/g, "")
    .replace(/[\\/]/g, "_")
    .replace(/\s+/g, " ")
    .trim();
  return (cleaned || "document").slice(0, 120);
}
