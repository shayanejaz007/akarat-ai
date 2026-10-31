/**
 * Where Ask a Lawyer keeps things (0021_legal_ai.sql).
 *
 * Conversations, messages and documents are read and written with the
 * caller's own Supabase session, so Row Level Security decides what each
 * request can touch: a bug here that asked for someone else's conversation
 * would get nothing back. Everything personal is sealed (crypto.ts) before
 * it leaves this process and opened only here.
 *
 * The service-role client is for what belongs to no one user: the library,
 * the provenance log, feedback, and sweeping out what has expired.
 */
import { randomUUID } from "node:crypto";
import { createClient, type SupabaseClient } from "@supabase/supabase-js";
import type { LegalSource } from "./agent.ts";
import { AAD, openBytes, openText, seal, sealBytes } from "./crypto.ts";
import type { DocKind, MediaType, Prepared } from "./documents.ts";
import type { LibraryDb } from "./library.ts";

export const BUCKET = "legal-documents";

export type UserBody = { text: string; docs?: string[] };
export type AssistantBody = {
  text: string;
  status: string;
  lang: "en" | "ar";
  sources: LegalSource[];
  refs: string[];
  unverified: string[];
  urgent: { level: "urgent" | "important"; text: string } | null;
  followups: string[];
  withdrawn?: "leak" | "refused";
};
export type StoredMessage =
  | { id: number; role: "user"; at: string; body: UserBody }
  | { id: number; role: "assistant"; at: string; body: AssistantBody };

export type Conversation = { id: string; title: string; updatedAt: string; expiresAt: string };

export type DocMeta = {
  id: string;
  conversationId: string;
  name: string;
  kind: DocKind;
  mediaType: MediaType;
  bytes: number;
  pages: number | null;
  tokens: number | null;
  scanned: boolean;
  objectPath: string;
  createdAt: string;
  expiresAt: string;
};

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
export const isUuid = (v: unknown): v is string => typeof v === "string" && UUID.test(v);

let service: SupabaseClient | null = null;

export function serviceClient(): SupabaseClient | null {
  const url = process.env.NEXT_PUBLIC_SUPABASE_URL;
  const key = process.env.SUPABASE_SERVICE_ROLE_KEY;
  if (!url || !key) return null;
  service ??= createClient(url, key, { auth: { persistSession: false, autoRefreshToken: false } });
  return service;
}

/** The library's two functions and its size, through the service role. */
export function libraryDb(sb: SupabaseClient | null): LibraryDb | null {
  if (!sb) return null;
  return {
    rpc: async (fn, args) => {
      const { data, error } = await sb.rpc(fn, args);
      return { data, error };
    },
    counts: async () => {
      const { data, error } = await sb.from("legal_sources").select("kind").eq("verification", "verified").limit(20000);
      return error ? null : (data as { kind: string }[]);
    },
  };
}

/** A title fit for a list: the first line of the question, short. */
export function titleOf(text: string): string {
  const line = text.replace(/\s+/g, " ").trim();
  return line.length > 80 ? `${line.slice(0, 79).trimEnd()}…` : line || "Untitled";
}

/* ── Conversations ───────────────────────────────────────────────────── */

export async function createConversation(sb: SupabaseClient, userId: string, title: string): Promise<Conversation | null> {
  const id = randomUUID();
  const { data, error } = await sb
    .from("legal_conversations")
    .insert({ id, user_id: userId, title_enc: seal(title, AAD.title(id)) })
    .select("id, updated_at, expires_at")
    .single();
  if (error || !data) return null;
  return { id, title, updatedAt: data.updated_at, expiresAt: data.expires_at };
}

export async function getConversation(sb: SupabaseClient, id: string): Promise<Conversation | null> {
  if (!isUuid(id)) return null;
  const { data, error } = await sb.from("legal_conversations").select("id, title_enc, updated_at, expires_at").eq("id", id).maybeSingle();
  if (error || !data) return null;
  return { id: data.id, title: openText(data.title_enc, AAD.title(data.id)) ?? "", updatedAt: data.updated_at, expiresAt: data.expires_at };
}

export async function listConversations(sb: SupabaseClient, limit = 200): Promise<Conversation[]> {
  const { data, error } = await sb
    .from("legal_conversations")
    .select("id, title_enc, updated_at, expires_at")
    .order("updated_at", { ascending: false })
    .limit(limit);
  if (error || !data) return [];
  return data.map(r => ({ id: r.id, title: openText(r.title_enc, AAD.title(r.id)) ?? "", updatedAt: r.updated_at, expiresAt: r.expires_at }));
}

export async function renameConversation(sb: SupabaseClient, id: string, title: string): Promise<void> {
  await sb.from("legal_conversations").update({ title_enc: seal(title, AAD.title(id)) }).eq("id", id);
}

/** Marks the conversation used now: its 90 days start again (the trigger sets them). */
export async function touchConversation(sb: SupabaseClient, id: string): Promise<void> {
  await sb.from("legal_conversations").update({ updated_at: new Date().toISOString() }).eq("id", id);
}

/** Its files first, then the rows; the database takes messages and documents with the conversation. */
export async function deleteConversations(sb: SupabaseClient, ids: string[] | "all"): Promise<boolean> {
  let q = sb.from("legal_documents").select("object_path");
  if (ids !== "all") q = q.in("conversation_id", ids);
  const { data: docs } = await q;
  const paths = (docs ?? []).map(d => d.object_path as string);
  if (paths.length) await sb.storage.from(BUCKET).remove(paths);
  let del = sb.from("legal_conversations").delete();
  del = ids === "all" ? del.not("id", "is", null) : del.in("id", ids);
  const { error } = await del;
  return !error;
}

/* ── Messages ────────────────────────────────────────────────────────── */

export async function loadMessages(sb: SupabaseClient, conversationId: string): Promise<StoredMessage[]> {
  const { data, error } = await sb
    .from("legal_messages")
    .select("id, role, content_enc, created_at")
    .eq("conversation_id", conversationId)
    .order("id", { ascending: true })
    .limit(400);
  if (error || !data) return [];
  const out: StoredMessage[] = [];
  for (const r of data) {
    if (r.role !== "user" && r.role !== "assistant") continue;
    const json = openText(r.content_enc, AAD.message(conversationId, r.role));
    if (!json) continue;
    try {
      const body = JSON.parse(json);
      if (!body || typeof body.text !== "string") continue;
      out.push({ id: Number(r.id), role: r.role, at: r.created_at, body });
    } catch {
      /* not one of ours */
    }
  }
  return out;
}

export async function saveMessage(
  sb: SupabaseClient,
  conversationId: string,
  role: "user" | "assistant",
  body: UserBody | AssistantBody
): Promise<number | null> {
  const { data, error } = await sb
    .from("legal_messages")
    .insert({ conversation_id: conversationId, role, content_enc: seal(JSON.stringify(body), AAD.message(conversationId, role)) })
    .select("id")
    .single();
  return error || !data ? null : Number(data.id);
}

/* ── Documents ───────────────────────────────────────────────────────── */

type DocRow = {
  id: string;
  conversation_id: string;
  name_enc: string;
  kind: DocKind;
  media_type: MediaType;
  bytes: number;
  pages: number | null;
  tokens: number | null;
  scanned: boolean;
  object_path: string;
  created_at: string;
  expires_at: string;
};

const DOC_COLUMNS = "id, conversation_id, name_enc, kind, media_type, bytes, pages, tokens, scanned, object_path, created_at, expires_at";

const docMeta = (r: DocRow): DocMeta => ({
  id: r.id,
  conversationId: r.conversation_id,
  name: openText(r.name_enc, AAD.docName(r.conversation_id, r.id)) ?? "document",
  kind: r.kind,
  mediaType: r.media_type,
  bytes: r.bytes,
  pages: r.pages,
  tokens: r.tokens,
  scanned: r.scanned,
  objectPath: r.object_path,
  createdAt: r.created_at,
  expiresAt: r.expires_at,
});

export async function listDocuments(sb: SupabaseClient, conversationId: string): Promise<DocMeta[]> {
  const { data, error } = await sb
    .from("legal_documents")
    .select(DOC_COLUMNS)
    .eq("conversation_id", conversationId)
    .order("created_at", { ascending: true })
    .limit(50);
  if (error || !data) return [];
  return (data as DocRow[]).map(docMeta);
}

export async function getDocument(sb: SupabaseClient, id: string): Promise<DocMeta | null> {
  if (!isUuid(id)) return null;
  const { data, error } = await sb.from("legal_documents").select(DOC_COLUMNS).eq("id", id).maybeSingle();
  return error || !data ? null : docMeta(data as DocRow);
}

/** Sealed, then into the caller's own folder; the row only once the file is there. */
export async function saveDocument(
  sb: SupabaseClient,
  userId: string,
  conversationId: string,
  name: string,
  doc: Prepared,
  tokens: number | null
): Promise<DocMeta | null> {
  const id = randomUUID();
  const objectPath = `${userId}/${id}`;
  const up = await sb.storage
    .from(BUCKET)
    .upload(objectPath, sealBytes(doc.body, AAD.docBody(conversationId, id)), { contentType: "application/octet-stream", upsert: false });
  if (up.error) return null;
  const { data, error } = await sb
    .from("legal_documents")
    .insert({
      id,
      conversation_id: conversationId,
      user_id: userId,
      name_enc: seal(name, AAD.docName(conversationId, id)),
      kind: doc.kind,
      media_type: doc.mediaType,
      bytes: doc.body.length,
      pages: doc.pages,
      tokens,
      scanned: doc.scanned,
      object_path: objectPath,
    })
    .select(DOC_COLUMNS)
    .single();
  if (error || !data) {
    await sb.storage.from(BUCKET).remove([objectPath]);
    return null;
  }
  return docMeta(data as DocRow);
}

export async function loadDocumentBody(sb: SupabaseClient, d: DocMeta): Promise<Buffer | null> {
  const { data, error } = await sb.storage.from(BUCKET).download(d.objectPath);
  if (error || !data) return null;
  return openBytes(new Uint8Array(await data.arrayBuffer()), AAD.docBody(d.conversationId, d.id));
}

export async function deleteDocument(sb: SupabaseClient, d: DocMeta): Promise<boolean> {
  await sb.storage.from(BUCKET).remove([d.objectPath]);
  const { error } = await sb.from("legal_documents").delete().eq("id", d.id);
  return !error;
}

/* ── Service-role records ────────────────────────────────────────────── */

/**
 * Expired conversations and documents out, and their files with them. Called
 * now and then by the routes; cheap when there is nothing to do.
 */
export async function sweepExpired(): Promise<number> {
  const sb = serviceClient();
  if (!sb) return 0;
  const { data, error } = await sb.rpc("legal_sweep", { p_limit: 200 });
  if (error || !Array.isArray(data)) return 0;
  const paths = data.map(r => (typeof r === "string" ? r : (r as Record<string, string>).legal_sweep)).filter(Boolean);
  for (let i = 0; i < paths.length; i += 100) await sb.storage.from(BUCKET).remove(paths.slice(i, i + 100));
  return paths.length;
}

export function maybeSweep(chance = 0.05): Promise<number> {
  return Math.random() < chance ? sweepExpired().catch(() => 0) : Promise.resolve(0);
}
