import type { NextRequest } from "next/server";
import { AAD, seal } from "@/lib/legal/crypto";
import { gate, json } from "@/lib/legal/http";
import { redact } from "@/lib/legal/redact";
import { loadMessages, serviceClient } from "@/lib/legal/store";
import { allow } from "@/lib/rate-limit";

/**
 * POST /api/legal/feedback   { messageId: number, kind, note?: string }
 *
 * A report on an answer: "good", or what was wrong with it. The admin panel
 * lists them; before launch they are how the reviewing lawyer's findings are
 * collected (LEGAL-AI.md, "Before launch").
 *
 * The message must be the caller's own, which is checked through their
 * session. The report itself is written with the service role, so nobody can
 * mark their own report as a reviewer's. A note is redacted and sealed. A
 * reviewer's report also carries the question and answer it is about,
 * redacted and sealed, so the review survives the conversation being deleted;
 * anyone else's carries only the kind and the note.
 */
export const runtime = "nodejs";
export const dynamic = "force-dynamic";

const KINDS = ["good", "wrong_law", "wrong_citation", "outdated", "fabricated", "missing", "unclear", "other"] as const;

export async function POST(request: NextRequest) {
  const g = await gate(request);
  if ("error" in g) return json(g.status, { error: g.error });
  if (!(await allow(`legal-feedback:u:${g.user.id}`, 10))) return json(429, { error: "rate_limited" });

  let body: Record<string, unknown>;
  try {
    const raw = await request.text();
    if (raw.length > 8000) return json(413, { error: "too_long" });
    body = JSON.parse(raw);
  } catch {
    return json(400, { error: "bad_request" });
  }
  const messageId = Number(body?.messageId);
  const kind = KINDS.find(k => k === body?.kind);
  if (!Number.isInteger(messageId) || messageId <= 0 || !kind) return json(400, { error: "bad_request" });
  const note = typeof body.note === "string" ? redact(body.note.replace(/\s+/g, " ").trim()).slice(0, 2000) : "";

  // The caller's own message: Row Level Security returns nothing otherwise.
  const { data: row } = await g.supabase.from("legal_messages").select("id, conversation_id, role").eq("id", messageId).maybeSingle();
  if (!row || row.role !== "assistant") return json(404, { error: "not_found" });

  let snapshot: string | null = null;
  if (g.reviewer) {
    const messages = await loadMessages(g.supabase, row.conversation_id);
    const at = messages.findIndex(m => m.id === messageId);
    const answer = messages[at];
    const question = [...messages.slice(0, Math.max(at, 0))].reverse().find(m => m.role === "user");
    if (answer && answer.role === "assistant") {
      snapshot = seal(
        JSON.stringify({
          question: redact(question?.body.text ?? ""),
          answer: redact(answer.body.text),
          sources: answer.body.sources.map(s => ({ kind: s.kind, title: s.title, url: s.url, status: s.status ?? null })),
          unverified: answer.body.unverified,
        }),
        AAD.snapshot(messageId)
      );
    }
  }

  const svc = serviceClient();
  if (!svc) return json(503, { error: "not_configured" });
  const { error } = await svc.from("legal_feedback").insert({
    user_id: g.user.id,
    message_id: messageId,
    message_ref: messageId,
    kind,
    note_enc: note ? seal(note, AAD.feedbackNote(messageId)) : null,
    reviewer: g.reviewer,
    snapshot_enc: snapshot,
  });
  return error ? json(500, { error: "unavailable" }) : json(200, { saved: true });
}
