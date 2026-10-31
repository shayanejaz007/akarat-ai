import type { NextRequest } from "next/server";
import { gate, json } from "@/lib/legal/http";
import {
  deleteConversations,
  getConversation,
  isUuid,
  listConversations,
  listDocuments,
  loadMessages,
  maybeSweep,
} from "@/lib/legal/store";

/**
 * GET    /api/legal/conversations            → { conversations: [{ id, title, updatedAt, expiresAt }] }
 * GET    /api/legal/conversations?id=<uuid>  → { conversation, messages, documents }
 * DELETE /api/legal/conversations?id=<uuid>  → { deleted: true }
 * DELETE /api/legal/conversations?all=1      → { deleted: true }   every conversation of the caller
 *
 * The caller's own history, opened here and nowhere else. Deleting removes
 * the messages, the documents and their files at once; nothing is kept
 * after that except the provenance log, which never held the conversation.
 */
export const runtime = "nodejs";
export const dynamic = "force-dynamic";

export async function GET(request: NextRequest) {
  const g = await gate(request);
  if ("error" in g) return json(g.status, { error: g.error });
  const id = request.nextUrl.searchParams.get("id");
  if (!id) {
    await maybeSweep(0.05);
    return json(200, { conversations: await listConversations(g.supabase) });
  }
  if (!isUuid(id)) return json(400, { error: "bad_request" });
  const conversation = await getConversation(g.supabase, id);
  if (!conversation) return json(404, { error: "not_found" });
  const [messages, documents] = await Promise.all([loadMessages(g.supabase, id), listDocuments(g.supabase, id)]);
  return json(200, {
    conversation,
    messages: messages.map(m =>
      m.role === "user"
        ? { id: m.id, role: "user", at: m.at, text: m.body.text, docs: m.body.docs ?? [] }
        : {
            id: m.id,
            role: "assistant",
            at: m.at,
            text: m.body.withdrawn ? "" : m.body.text,
            status: m.body.status,
            lang: m.body.lang,
            sources: m.body.sources ?? [],
            unverified: m.body.unverified ?? [],
            urgent: m.body.urgent ?? null,
            followups: m.body.followups ?? [],
            withdrawn: m.body.withdrawn ?? null,
          }
    ),
    documents: documents.map(d => ({ id: d.id, name: d.name, kind: d.kind, pages: d.pages, scanned: d.scanned, bytes: d.bytes, expiresAt: d.expiresAt })),
  });
}

export async function DELETE(request: NextRequest) {
  const g = await gate(request);
  if ("error" in g) return json(g.status, { error: g.error });
  const sp = request.nextUrl.searchParams;
  if (sp.get("all") === "1") {
    return (await deleteConversations(g.supabase, "all")) ? json(200, { deleted: true }) : json(500, { error: "unavailable" });
  }
  const id = sp.get("id");
  if (!isUuid(id)) return json(400, { error: "bad_request" });
  if (!(await getConversation(g.supabase, id))) return json(404, { error: "not_found" });
  return (await deleteConversations(g.supabase, [id])) ? json(200, { deleted: true }) : json(500, { error: "unavailable" });
}
