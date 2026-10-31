import Anthropic from "@anthropic-ai/sdk";
import type { NextRequest } from "next/server";
import { docBlocks, type DocInput } from "@/lib/legal/agent";
import { DOCS, LIMITS, MODEL } from "@/lib/legal/config";
import { cleanName, prepareDocument, type Prepared } from "@/lib/legal/documents";
import { gate, json } from "@/lib/legal/http";
import { redact } from "@/lib/legal/redact";
import {
  createConversation,
  deleteDocument,
  getConversation,
  getDocument,
  isUuid,
  listDocuments,
  maybeSweep,
  saveDocument,
  titleOf,
  type Conversation,
} from "@/lib/legal/store";
import { allow } from "@/lib/rate-limit";

/**
 * POST /api/legal/documents   multipart/form-data: file, conversationId?
 *   → { conversationId, title, document: { id, name, kind, pages, scanned, bytes } }
 *     or { error: code } (the codes are listed in LEGAL-AI.md)
 * DELETE /api/legal/documents?id=<uuid>
 *
 * A document joins a conversation (a new one when none is given) and goes
 * to the model with the next question. It is screened (lib/legal/documents.ts),
 * measured in tokens by the API before it is accepted, sealed, and stored in
 * the caller's own folder of a private bucket.
 */
export const runtime = "nodejs";
export const dynamic = "force-dynamic";
export const maxDuration = 30;

let client: Anthropic | null = null;

// What reading the document costs the model: counted by the API, which also
// refuses a file it cannot read. Without an answer from it, an estimate.
async function countTokens(doc: Prepared): Promise<number | { error: "damaged" }> {
  const input: DocInput = { id: "count", n: 1, name: "document", kind: doc.kind, mediaType: doc.mediaType, body: doc.body, pages: doc.pages, scanned: doc.scanned };
  client ??= new Anthropic({ maxRetries: 1, timeout: 20_000 });
  try {
    const r = await client.beta.messages.countTokens({
      model: MODEL,
      messages: [{ role: "user", content: [...docBlocks(input), { type: "text", text: "Read this document." }] }],
    });
    return r.input_tokens;
  } catch (e) {
    if (e instanceof Anthropic.BadRequestError) return { error: "damaged" };
    if (doc.kind === "pdf") return (doc.pages ?? Math.ceil(doc.body.length / 60_000)) * 3_000;
    if (doc.kind === "image") return 1_600;
    return Math.ceil((doc.textChars ?? doc.body.length) / 2.5);
  }
}

export async function POST(request: NextRequest) {
  const g = await gate(request);
  if ("error" in g) return json(g.status, { error: g.error });
  const { supabase: sb, user } = g;

  if (!(await allow(`legal-upload:u:${user.id}`, LIMITS.uploadsPerMinute))) return json(429, { error: "rate_limited" });
  const declared = Number(request.headers.get("content-length") || 0);
  if (declared > DOCS.maxBytes + 100_000) return json(413, { error: "too_big" });

  let form: FormData;
  try {
    form = await request.formData();
  } catch {
    return json(400, { error: "bad_request" });
  }
  const file = form.get("file");
  if (!file || typeof file === "string") return json(400, { error: "bad_request" });
  if (file.size > DOCS.maxBytes) return json(413, { error: "too_big" });

  const doc = prepareDocument(new Uint8Array(await file.arrayBuffer()));
  if ("error" in doc) return json(422, { error: doc.error });
  const name = cleanName(file.name);

  const asked = form.get("conversationId");
  let conv: Conversation | null = null;
  if (typeof asked === "string" && asked) {
    if (!isUuid(asked)) return json(400, { error: "bad_request" });
    conv = await getConversation(sb, asked);
    if (!conv) return json(404, { error: "not_found" });
  }
  const existing = conv ? await listDocuments(sb, conv.id) : [];
  if (existing.length >= DOCS.maxPerConversation) return json(409, { error: "too_many_documents" });

  const tokens = await countTokens(doc);
  if (typeof tokens !== "number") return json(422, tokens);
  if (tokens > DOCS.maxTokensPerDoc) return json(413, { error: "too_long" });
  if (existing.reduce((s, d) => s + (d.tokens ?? 0), 0) + tokens > DOCS.maxTokensAll) return json(409, { error: "conversation_full" });

  if (!conv) {
    conv = await createConversation(sb, user.id, redact(titleOf(name)));
    if (!conv) return json(500, { error: "unavailable" });
  }
  const saved = await saveDocument(sb, user.id, conv.id, name, doc, tokens);
  if (!saved) return json(500, { error: "unavailable" });
  await maybeSweep(0.1);

  return json(200, {
    conversationId: conv.id,
    title: conv.title,
    document: { id: saved.id, name: saved.name, kind: saved.kind, pages: saved.pages, scanned: saved.scanned, bytes: saved.bytes },
  });
}

export async function DELETE(request: NextRequest) {
  const g = await gate(request);
  if ("error" in g) return json(g.status, { error: g.error });
  const id = request.nextUrl.searchParams.get("id");
  if (!isUuid(id)) return json(400, { error: "bad_request" });
  const doc = await getDocument(g.supabase, id);
  if (!doc) return json(404, { error: "not_found" });
  return (await deleteDocument(g.supabase, doc)) ? json(200, { deleted: true }) : json(500, { error: "unavailable" });
}
