import Anthropic from "@anthropic-ai/sdk";
import type { NextRequest } from "next/server";
import { LEGAL_POOL, recordTurn, takeTurn } from "@/lib/advisor/usage";
import { runTurn, type ClientEvent, type DocInput, type ErrorCode, type HistoryTurn } from "@/lib/legal/agent";
import { INPUT, LIMITS } from "@/lib/legal/config";
import { inFlight } from "@/lib/inflight";
import { gate } from "@/lib/legal/http";
import { libraryCounts } from "@/lib/legal/library";
import { ammanDate } from "@/lib/legal/prompt";
import { redact } from "@/lib/legal/redact";
import {
  createConversation,
  getConversation,
  isUuid,
  libraryDb,
  listDocuments,
  loadDocumentBody,
  loadMessages,
  maybeSweep,
  renameConversation,
  saveMessage,
  serviceClient,
  titleOf,
  touchConversation,
  type AssistantBody,
  type Conversation,
  type DocMeta,
} from "@/lib/legal/store";
import { allow } from "@/lib/rate-limit";

/**
 * POST /api/legal/ask
 *
 *   { conversationId?: uuid, message: string, lang: "en" | "ar" }
 *   → application/x-ndjson: one ClientEvent per line (lib/legal/agent.ts):
 *     { t: "conversation", id, title } first, then the answer as it is
 *     written, then { t: "saved", messageId } and { t: "done", lang },
 *     or { t: "error", code }.
 *
 * Signed-in callers only, and before launch only reviewers (lib/legal/http.ts).
 * The conversation and its documents are read through the caller's own
 * session, so Row Level Security decides what this request can see; both
 * are stored sealed (lib/legal/crypto.ts). Documents uploaded to the
 * conversation since its last message travel with this one.
 */
export const runtime = "nodejs";
export const dynamic = "force-dynamic";
export const maxDuration = 60;

let client: Anthropic | null = null;

const reply = (status: number, code: ErrorCode) =>
  new Response(`${JSON.stringify({ t: "error", code })}\n`, {
    status,
    headers: { "Content-Type": "application/x-ndjson; charset=utf-8", "Cache-Control": "no-store" },
  });

const CONTROL = /[\u0000-\u0008\u000b\u000c\u000e-\u001f\u007f\u202a-\u202e\u2066-\u2069\ue000-\uf8ff]/g;

const WITHDRAWN = { en: "(This answer was withdrawn.)", ar: "(سُحبت هذه الإجابة.)" };

export async function POST(request: NextRequest) {
  const g = await gate(request);
  if ("error" in g) return reply(g.status, g.error);
  const { supabase: sb, user } = g;

  let body: Record<string, unknown>;
  try {
    const raw = await request.text();
    if (raw.length > 24_000) return reply(413, "too_long");
    body = JSON.parse(raw);
    if (!body || typeof body !== "object" || Array.isArray(body)) throw new Error("not an object");
  } catch {
    return reply(400, "bad_request");
  }
  const message = typeof body.message === "string" ? body.message.replace(CONTROL, "").trim() : "";
  if (!message) return reply(400, "bad_request");
  if (message.length > INPUT.maxMessageChars) return reply(413, "too_long");
  const lang = body.lang === "ar" ? "ar" : "en";
  const askedFor = body.conversationId;
  if (askedFor != null && !isUuid(askedFor)) return reply(400, "bad_request");

  const key = `u:${user.id}`;
  if (!(await allow(`legal:${key}`, LIMITS.perMinute))) {
    console.info(JSON.stringify({ evt: "legal_limited", scope: "minute" }));
    return reply(429, "rate_limited");
  }
  // The same question in the same conversation while it is still being
  // answered (a double click, a second tab): refused, not paid for twice.
  const release = inFlight(`legal:${key}`, `${String(askedFor ?? "")}\u0000${message}`);
  if (!release) return reply(409, "busy");
  const quota = await takeTurn(key, LIMITS.perDay, LIMITS.perDayTotal, LEGAL_POOL);
  if (quota !== "ok") {
    release();
    console.info(JSON.stringify({ evt: "legal_limited", scope: quota === "global" ? "day_total" : "day" }));
    return reply(429, quota === "global" ? "quota_total" : "quota");
  }

  // The conversation so far, through the caller's own session.
  let conv: Conversation | null = null;
  if (typeof askedFor === "string") {
    conv = await getConversation(sb, askedFor);
    if (!conv) {
      release();
      return reply(404, "not_found");
    }
  }
  const stored = conv ? await loadMessages(sb, conv.id) : [];
  const docsMeta = conv ? await listDocuments(sb, conv.id) : [];

  // Documents: each is numbered by upload order and travels with the message
  // it was first sent with. Any not yet sent go with this one.
  const sentWith = new Map<string, number>();
  stored.forEach((m, i) => {
    if (m.role === "user") for (const id of m.body.docs ?? []) if (!sentWith.has(id)) sentWith.set(id, i);
  });
  const bodies = await Promise.all(docsMeta.map(d => loadDocumentBody(sb, d)));
  const inputs = new Map<string, DocInput>();
  docsMeta.forEach((d: DocMeta, i) => {
    const b = bodies[i];
    if (b) inputs.set(d.id, { id: d.id, n: i + 1, name: d.name, kind: d.kind, mediaType: d.mediaType, body: b, pages: d.pages, scanned: d.scanned });
  });
  const newDocs = docsMeta.filter(d => !sentWith.has(d.id)).map(d => inputs.get(d.id)).filter((d): d is DocInput => !!d);

  // History: alternating user and assistant turns, the newest that fit.
  let history: HistoryTurn[] = [];
  for (const [i, m] of stored.entries()) {
    if (m.role === "user") {
      if (history.length && history[history.length - 1].role === "user") history.push({ role: "assistant", text: "…" });
      const docs = (m.body.docs ?? []).filter(id => sentWith.get(id) === i).map(id => inputs.get(id)).filter((d): d is DocInput => !!d);
      history.push({ role: "user", text: m.body.text, docs });
    } else if (history.length && history[history.length - 1].role === "user") {
      history.push({ role: "assistant", text: m.body.withdrawn ? WITHDRAWN[m.body.lang] : m.body.text });
    }
  }
  if (history.length && history[history.length - 1].role === "user") history.push({ role: "assistant", text: "…" });
  let chars = 0;
  let keepFrom = history.length;
  while (keepFrom >= 2 && history.length - keepFrom < INPUT.maxTurnsKept * 2) {
    const add = history[keepFrom - 2].text.length + history[keepFrom - 1].text.length;
    if (chars + add > INPUT.maxHistoryChars) break;
    chars += add;
    keepFrom -= 2;
  }
  if (keepFrom > 0) {
    // Earlier documents stay in view: they move to the first exchange kept.
    const carried = history.slice(0, keepFrom).flatMap(t => (t.role === "user" ? t.docs : []));
    history = history.slice(keepFrom);
    const first = history[0];
    if (first && first.role === "user") history[0] = { ...first, docs: [...carried, ...first.docs] };
    else if (carried.length) newDocs.unshift(...carried);
  }
  const knownRefs = stored.flatMap(m => (m.role === "assistant" ? m.body.refs ?? [] : []));

  if (!conv) {
    conv = await createConversation(sb, user.id, redact(titleOf(message)));
    if (!conv) {
      release();
      return reply(500, "unavailable");
    }
  } else if (!stored.length) {
    // Started by an upload, so named after the file until now: the first
    // question is the better name.
    const title = redact(titleOf(message));
    await renameConversation(sb, conv.id, title);
    conv = { ...conv, title };
  }
  const conversation = conv;

  const svc = serviceClient();
  const db = libraryDb(svc);
  const counts = db ? await libraryCounts(db) : null;
  const documents = [...inputs.values()].map(d => ({ n: d.n, name: d.name, kind: d.kind, pages: d.pages, scanned: d.scanned }));

  client ??= new Anthropic({ maxRetries: 1, timeout: 50_000 });
  const encoder = new TextEncoder();

  const stream = new ReadableStream<Uint8Array>({
    async start(controller) {
      let open = true;
      const emit = (e: ClientEvent) => {
        if (!open) return;
        try {
          controller.enqueue(encoder.encode(`${JSON.stringify(e)}\n`));
        } catch {
          open = false;
        }
      };
      emit({ t: "conversation", id: conversation.id, title: conversation.title });

      const started = Date.now();
      const result = await runTurn({
        client: client!,
        history,
        message,
        docs: newDocs,
        context: { today: ammanDate(), uiLang: lang, library: counts, documents },
        env: { db },
        knownRefs,
        emit,
        signal: request.signal,
      });

      // Saved whenever the person saw an answer, cut short or not; a failed
      // call leaves nothing behind, and the page offers to ask again.
      let messageId: number | null = null;
      if (result.status !== "error") {
        await saveMessage(sb, conversation.id, "user", { text: message, docs: newDocs.map(d => d.id) });
        const answer: AssistantBody = {
          text: result.reply.slice(0, 60_000),
          status: result.status === "aborted" ? "stopped" : result.status,
          lang: result.lang,
          sources: result.sources,
          refs: result.refs,
          unverified: result.unverified,
          urgent: result.urgent,
          followups: result.followups,
          ...(result.status === "leak" || result.status === "refused" ? { withdrawn: result.status } : {}),
        };
        messageId = await saveMessage(sb, conversation.id, "assistant", answer);
        await touchConversation(sb, conversation.id);
        emit({ t: "saved", messageId });
        emit({ t: "done", lang: result.lang });
      }

      // Provenance and cost, written before the stream closes: a serverless
      // function may stop the moment its response ends. Counts, outcomes and
      // source references only; never the question or the answer.
      if (svc && result.status !== "error") {
        const row = {
          conversation_id: conversation.id,
          message_id: messageId,
          model: result.route.model,
          status: result.status,
          sources: result.provenance.slice(0, 60),
          cited: result.sources.length,
          unverified: result.unverified.length,
          flags: [...new Set(result.flags)].slice(0, 10),
        };
        const measured = { route: [result.route.route, result.route.effort, ...result.route.reasons].join(":").slice(0, 80), cost_micros: result.costUsd == null ? null : Math.round(result.costUsd * 1_000_000) };
        // Before 0022 the table has no route or cost columns; the row goes in without them.
        const audit = await svc.from("legal_audit").insert({ ...row, ...measured });
        if (audit.error) await svc.from("legal_audit").insert(row);
      }
      console.info(
        JSON.stringify({
          evt: "legal_turn",
          model: result.route.model,
          effort: result.route.effort,
          route: result.route.route,
          reasons: result.route.reasons,
          costUsd: result.costUsd == null ? null : Math.round(result.costUsd * 10000) / 10000,
          status: result.status,
          ms: Date.now() - started,
          tools: result.tools,
          flags: result.flags,
          cited: result.sources.length,
          unverified: result.unverified.length,
          documents: documents.length,
          usage: result.usage,
        })
      );
      await recordTurn(key, result.usage, result.flags, LEGAL_POOL, { costUsd: result.costUsd, route: `${result.route.model}|${result.route.effort}` });
      release();
      await maybeSweep();

      if (open) {
        open = false;
        try {
          controller.close();
        } catch {
          /* already gone */
        }
      }
    },
  });

  return new Response(stream, {
    headers: {
      "Content-Type": "application/x-ndjson; charset=utf-8",
      "Cache-Control": "no-store",
      "X-Accel-Buffering": "no",
    },
  });
}
