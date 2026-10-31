/**
 * Encryption for what people ask Ask a Lawyer and what they upload to it.
 *
 * AES-256-GCM, done here on the server before anything reaches Supabase, so
 * the database and the storage bucket only ever hold ciphertext: a dump, a
 * backup, a support session or a mistaken policy shows nothing readable. The
 * key, LEGAL_DATA_KEY (32 random bytes, base64 or hex), lives in the
 * server's environment and nowhere else.
 *
 * Every sealed value is bound to where it belongs (its conversation, its
 * role) as associated data. Ciphertext copied to another row, or a user's
 * message relabelled as the assistant's, fails to open instead of being
 * believed.
 *
 * Format: "<key id>.<base64url(iv | tag | ciphertext)>". The key id lets a
 * new key take over while LEGAL_DATA_KEY_PREVIOUS still opens older rows.
 */
import { createCipheriv, createDecipheriv, createHash, createHmac, hkdfSync, randomBytes } from "node:crypto";

type Key = { id: string; enc: Buffer; mac: Buffer };

function parseKey(raw: string | undefined): Key | null {
  if (!raw) return null;
  const s = raw.trim();
  let bytes: Buffer | null = null;
  if (/^[0-9a-f]{64}$/i.test(s)) bytes = Buffer.from(s, "hex");
  else {
    const b = Buffer.from(s, "base64");
    if (b.length === 32) bytes = b;
  }
  if (!bytes || bytes.length !== 32) return null;
  const derive = (info: string) => Buffer.from(hkdfSync("sha256", bytes!, "akarat-legal", info, 32));
  return {
    id: createHash("sha256").update(bytes).digest("hex").slice(0, 8),
    enc: derive("encryption"),
    mac: derive("fingerprint"),
  };
}

let keys: { current: Key | null; all: Key[] } | null = null;

function load() {
  if (keys) return keys;
  const current = parseKey(process.env.LEGAL_DATA_KEY);
  const previous = parseKey(process.env.LEGAL_DATA_KEY_PREVIOUS);
  keys = { current, all: [current, previous].filter((k): k is Key => !!k) };
  return keys;
}

/** For tests: forget the cached keys so a changed environment is read again. */
export function resetKeys() {
  keys = null;
}

export function dataKeyReady(): boolean {
  return !!load().current;
}

export function seal(plain: string | Uint8Array, aad: string): string {
  const k = load().current;
  if (!k) throw new Error("LEGAL_DATA_KEY is not set or is not 32 bytes");
  const iv = randomBytes(12);
  const c = createCipheriv("aes-256-gcm", k.enc, iv);
  c.setAAD(Buffer.from(aad, "utf8"));
  const body = Buffer.concat([c.update(typeof plain === "string" ? Buffer.from(plain, "utf8") : Buffer.from(plain)), c.final()]);
  return `${k.id}.${Buffer.concat([iv, c.getAuthTag(), body]).toString("base64url")}`;
}

/** The plaintext, or null when the value is not ours, was moved, or was altered. */
export function open(sealed: unknown, aad: string): Buffer | null {
  if (typeof sealed !== "string") return null;
  const dot = sealed.indexOf(".");
  if (dot !== 8) return null;
  const k = load().all.find(x => x.id === sealed.slice(0, dot));
  if (!k) return null;
  const raw = Buffer.from(sealed.slice(dot + 1), "base64url");
  if (raw.length < 28) return null;
  try {
    const d = createDecipheriv("aes-256-gcm", k.enc, raw.subarray(0, 12));
    d.setAAD(Buffer.from(aad, "utf8"));
    d.setAuthTag(raw.subarray(12, 28));
    return Buffer.concat([d.update(raw.subarray(28)), d.final()]);
  } catch {
    return null;
  }
}

export function openText(sealed: unknown, aad: string): string | null {
  const b = open(sealed, aad);
  return b ? b.toString("utf8") : null;
}

/**
 * The same, as bytes, for files in the storage bucket: key id (8 ASCII
 * characters), iv, tag, ciphertext. No base64, so a 4 MB upload stays 4 MB.
 */
export function sealBytes(plain: Uint8Array, aad: string): Buffer {
  const s = seal(plain, aad);
  return Buffer.concat([Buffer.from(s.slice(0, 8), "ascii"), Buffer.from(s.slice(9), "base64url")]);
}

export function openBytes(sealed: Uint8Array | null, aad: string): Buffer | null {
  if (!sealed || sealed.length < 8 + 28) return null;
  const b = Buffer.from(sealed);
  return open(`${b.subarray(0, 8).toString("ascii")}.${b.subarray(8).toString("base64url")}`, aad);
}

/**
 * A keyed fingerprint of a document, to notice the same file uploaded twice.
 * Keyed, so the stored value cannot be used to confirm whether a known
 * document was uploaded.
 */
export function fingerprint(data: Uint8Array): string {
  const k = load().current;
  if (!k) throw new Error("LEGAL_DATA_KEY is not set or is not 32 bytes");
  return createHmac("sha256", k.mac).update(data).digest("hex").slice(0, 32);
}

/** What each sealed value is bound to. One place, so writer and reader agree. */
export const AAD = {
  title: (conversationId: string) => `legal:title:${conversationId}`,
  message: (conversationId: string, role: "user" | "assistant") => `legal:message:${conversationId}:${role}`,
  docName: (conversationId: string, docId: string) => `legal:docname:${conversationId}:${docId}`,
  docBody: (conversationId: string, docId: string) => `legal:docbody:${conversationId}:${docId}`,
  feedbackNote: (messageId: number) => `legal:feedback:${messageId}`,
  snapshot: (messageId: number) => `legal:snapshot:${messageId}`,
};
