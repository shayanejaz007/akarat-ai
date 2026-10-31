import Anthropic from "@anthropic-ai/sdk";
import type { NextRequest } from "next/server";
import { callerIp, resolveCaller } from "@/lib/caller";
import { allow } from "@/lib/rate-limit";
import { runTurn, type ClientEvent } from "@/lib/advisor/agent";
import { INPUT, LIMITS } from "@/lib/advisor/config";
import { Evidence, normalizeUrl } from "@/lib/advisor/evidence";
import { supabaseListings, type Lang } from "@/lib/advisor/listings";
import { ammanDate } from "@/lib/advisor/prompt";
import type { Card } from "@/lib/advisor/tools";
import { earlierListings, sign, trim, verify, type Turn } from "@/lib/advisor/transcript";
import { callerKey, recordTurn, takeTurn } from "@/lib/advisor/usage";
import { inFlight } from "@/lib/inflight";

/**
 * POST /api/ai/advisor
 *
 *   { message: string, lang: "en" | "ar", transcript?: string }
 *   → application/x-ndjson: one ClientEvent per line (lib/advisor/agent.ts),
 *     ending with { t: "done", transcript } or { t: "error", code }.
 *
 * The conversational property advisor behind the website's AI search. The
 * Anthropic key stays in this function's environment; the browser sends text
 * and gets text, cards and links back, and never talks to a model or a third
 * party itself.
 *
 * Callers are anyone: signed in (cookie on the website, bearer token from the
 * app) or not. Signed-in callers get a larger allowance. What they can reach
 * is the same either way: public listings through Row Level Security, and the
 * approved web sources in lib/advisor/config.ts.
 *
 * /api/ai/search is unchanged and still serves the app's structured search.
 */

export const runtime = "nodejs";
export const dynamic = "force-dynamic";
// The same ceiling on every Vercel plan. The turn budgets its own time inside
// it (TURN in lib/advisor/config.ts) and closes the stream before it is cut.
export const maxDuration = 60;

let client: Anthropic | null = null;

const reply = (status: number, code: Extract<ClientEvent, { t: "error" }>["code"]) =>
  new Response(`${JSON.stringify({ t: "error", code })}\n`, {
    status,
    headers: { "Content-Type": "application/x-ndjson; charset=utf-8", "Cache-Control": "no-store" },
  });

// Control characters other than newline and tab, and the bidi overrides that
// can make text read differently from what it contains.
const CONTROL = /[\u0000-\u0008\u000b\u000c\u000e-\u001f\u007f\u202a-\u202e\u2066-\u2069\ue000-\uf8ff]/g;

export async function POST(request: NextRequest) {
  if (!process.env.ANTHROPIC_API_KEY) return reply(503, "not_configured");

  let body: Record<string, unknown>;
  try {
    const raw = await request.text();
    if (raw.length > INPUT.maxTranscriptBytes + 20_000) return reply(413, "too_long");
    body = JSON.parse(raw);
    if (!body || typeof body !== "object" || Array.isArray(body)) throw new Error("not an object");
  } catch {
    return reply(400, "bad_request");
  }
  const message = typeof body.message === "string" ? body.message.replace(CONTROL, "").trim() : "";
  if (!message) return reply(400, "bad_request");
  if (message.length > INPUT.maxMessageChars) return reply(413, "too_long");
  const lang: Lang = body.lang === "ar" ? "ar" : "en";

  const { supabase, user } = await resolveCaller(request);
  const ip = callerIp(request);
  const key = callerKey(user?.id ?? null, ip);

  if (!(await allow(`advisor:${key}`, user ? LIMITS.perMinuteSignedIn : LIMITS.perMinuteAnonymous))) {
    console.info(JSON.stringify({ evt: "advisor_limited", key, scope: "minute" }));
    return reply(429, "rate_limited");
  }
  // The same message from the same caller while it is still being answered
  // (a double click, a second tab): refused, so it is not paid for twice.
  const release = inFlight(`advisor:${key}`, `${message}\u0000${typeof body.transcript === "string" ? body.transcript.slice(-200) : ""}`);
  if (!release) return reply(409, "busy");
  const quota = await takeTurn(key, user ? LIMITS.perDaySignedIn : LIMITS.perDayAnonymous, LIMITS.perDayTotal);
  if (quota !== "ok") {
    release();
    console.info(JSON.stringify({ evt: "advisor_limited", key, scope: quota === "global" ? "day_total" : "day" }));
    // The caller's own allowance, or everyone's: they read differently.
    return reply(429, quota === "global" ? "quota_total" : "quota");
  }

  // The conversation so far, if it is genuinely one this server signed.
  const supplied = typeof body.transcript === "string" && body.transcript.length > 0;
  const history = supplied ? verify(body.transcript) : [];
  const forgotten = supplied && history === null;
  const turns: Turn[] = history ?? [];

  const evidence = new Evidence();
  const cards = new Map<string, Card>();
  for (const l of earlierListings(turns)) {
    if (l.k === "a") {
      evidence.listingIds.add(l.id);
    } else {
      const k = normalizeUrl(l.url);
      if (!k) continue;
      evidence.shownExternal.set(k, { url: l.url, title: l.title });
      cards.set(`ext:${k}`, {
        key: `ext:${k}`,
        kind: "external",
        url: l.url,
        source: { name: l.src, nameAr: l.src, host: new URL(l.url).hostname.replace(/^www\./, "") },
        title: l.title,
        price: l.price,
        basis: (l.basis as "total" | "month" | "night" | null) ?? null,
        beds: l.beds,
        baths: l.baths,
        size: l.size,
        location: l.where,
        checked: true,
        seen: null,
        why: "",
      });
    }
  }

  client ??= new Anthropic({ maxRetries: 1, timeout: 50_000 });
  const today = ammanDate();
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
      if (forgotten) emit({ t: "notice", kind: "memory_reset" });

      const started = Date.now();
      const result = await runTurn({
        client: client!,
        history: turns,
        message,
        context: { today, uiLang: lang, signedIn: !!user },
        env: { db: supabaseListings(supabase), lang, evidence, today, cards, shownThisTurn: [] },
        emit,
        signal: request.signal,
      });

      if (result.status !== "error" && result.status !== "aborted") {
        // A withdrawn reply is remembered as withdrawn, so a follow-up does
        // not build on text the visitor never saw.
        const said =
          result.status === "leak" || result.status === "refused" ? "(This reply was withdrawn.)" : result.reply.slice(0, 6000);
        const next = trim([
          ...turns,
          { r: "u", t: message },
          { r: "a", t: said, ...(result.shown.length ? { l: result.shown } : {}) },
        ]);
        emit({ t: "done", transcript: sign(next) });
      }

      // One line per turn for the logs, and the day's record for the admin
      // panel. Counts and outcomes only: never the conversation itself.
      // Written before the stream closes: a serverless function is free to
      // stop the moment its response ends, and the page already has "done".
      console.info(
        JSON.stringify({
          evt: "advisor_turn",
          model: result.route.model,
          effort: result.route.effort,
          route: result.route.route,
          costUsd: result.costUsd == null ? null : Math.round(result.costUsd * 10000) / 10000,
          key,
          status: result.status,
          ms: Date.now() - started,
          tools: result.tools,
          flags: result.flags,
          usage: result.usage,
        })
      );
      await recordTurn(key, result.usage, result.flags, undefined, { costUsd: result.costUsd, route: `${result.route.model}|${result.route.effort}` });
      release();

      if (open) {
        open = false;
        try {
          controller.close();
        } catch {
          /* the visitor already left */
        }
      }
    },
  });

  return new Response(stream, {
    headers: {
      "Content-Type": "application/x-ndjson; charset=utf-8",
      "Cache-Control": "no-store",
      // Proxies that buffer would hold the whole reply until the end.
      "X-Accel-Buffering": "no",
    },
  });
}
