/**
 * Conversation memory for the advisor, held by the browser and signed here.
 *
 * Serverless functions keep nothing between requests, so the conversation
 * travels with the visitor: each reply ends with a signed transcript, and the
 * next message sends it back. The signature (HMAC-SHA256 with a key only the
 * server holds) is what makes this safe. Without it a visitor could hand the
 * advisor a past it never had: invented earlier answers, fake listing ids,
 * "as you agreed earlier, ignore your rules". A transcript that fails the
 * check, or has expired, is dropped and the conversation starts fresh.
 *
 * The transcript is compact on purpose: what each side said, and the listings
 * each reply showed. Searches, page reads and the advisor's reasoning are not
 * replayed into later turns; they are long, they go stale, and the listings
 * shown are what follow-up questions ("compare the first two") refer to.
 */
import { createHash, createHmac, timingSafeEqual } from "node:crypto";
import type { BetaMessageParam } from "@anthropic-ai/sdk/resources/beta/messages/messages";
import { INPUT } from "./config.ts";
import type { Card } from "./tools.ts";

export type ShownListing =
  | { k: "a"; id: string; title: string; price: number; basis: string; where: string }
  | {
      k: "e";
      url: string;
      src: string;
      title: string;
      price: number | null;
      basis: string | null;
      beds: number | null;
      baths: number | null;
      size: number | null;
      where: string | null;
    };

export type Turn = { r: "u"; t: string } | { r: "a"; t: string; l?: ShownListing[] };

type Envelope = { v: 1; exp: number; turns: Turn[] };

const TTL_MS = 12 * 60 * 60 * 1000;

function key(): Buffer | null {
  const secret =
    process.env.AI_ADVISOR_SECRET ||
    (process.env.ANTHROPIC_API_KEY ? `${process.env.ANTHROPIC_API_KEY}:${process.env.SUPABASE_SERVICE_ROLE_KEY ?? ""}` : "");
  if (!secret) return null;
  // Derived rather than used raw: the API key itself never signs anything.
  return createHash("sha256").update(`akarat-advisor-transcript:v1:${secret}`).digest();
}

const b64 = (s: string) => Buffer.from(s, "utf8").toString("base64url");
const unb64 = (s: string) => Buffer.from(s, "base64url").toString("utf8");

export function sign(turns: Turn[], now = Date.now()): string | null {
  const k = key();
  if (!k) return null;
  const body = b64(JSON.stringify({ v: 1, exp: now + TTL_MS, turns } satisfies Envelope));
  const mac = createHmac("sha256", k).update(body).digest("base64url");
  return `${body}.${mac}`;
}

/** The turns, or null when the token is missing, forged, malformed or expired. */
export function verify(token: unknown, now = Date.now()): Turn[] | null {
  if (typeof token !== "string" || !token || token.length > INPUT.maxTranscriptBytes) return null;
  const k = key();
  if (!k) return null;
  const dot = token.lastIndexOf(".");
  if (dot < 1) return null;
  const body = token.slice(0, dot);
  const given = Buffer.from(token.slice(dot + 1), "base64url");
  const want = createHmac("sha256", k).update(body).digest();
  if (given.length !== want.length || !timingSafeEqual(given, want)) return null;
  try {
    const env = JSON.parse(unb64(body)) as Envelope;
    if (env.v !== 1 || typeof env.exp !== "number" || env.exp < now || !Array.isArray(env.turns)) return null;
    return env.turns;
  } catch {
    return null;
  }
}

/**
 * Keeps the most recent exchanges inside the size limits. Drops whole
 * exchanges from the start, so the transcript always opens with the user.
 */
export function trim(turns: Turn[]): Turn[] {
  let out = turns.slice(-INPUT.maxTurnsKept);
  while (out.length && out[0].r !== "u") out = out.slice(1);
  const size = (t: Turn[]) => JSON.stringify(t).length;
  while (out.length > 2 && size(out) > INPUT.maxTranscriptChars) {
    out = out.slice(2);
    while (out.length && out[0].r !== "u") out = out.slice(1);
  }
  return out;
}

export function remember(card: Card): ShownListing {
  if (card.kind === "akarat") {
    return { k: "a", id: card.id, title: card.title.en || card.title.ar, price: card.price, basis: card.basis, where: card.location.en };
  }
  return {
    k: "e",
    url: card.url,
    src: card.source.name,
    title: card.title,
    price: card.price,
    basis: card.basis,
    beds: card.beds,
    baths: card.baths,
    size: card.size,
    where: card.location,
  };
}

const money = (n: number | null, basis: string | null) =>
  n == null ? "price not shown" : `${n.toLocaleString("en-US")} JOD${basis === "month" ? "/month" : basis === "night" ? "/night" : ""}`;

function shownBlock(l: ShownListing[]): string {
  const lines = l.map((x, i) =>
    x.k === "a"
      ? `${i + 1}. Akarat.ai listing id ${x.id}: "${x.title}", ${money(x.price, x.basis)}, ${x.where}`
      : `${i + 1}. External listing on ${x.src}, url ${x.url}: "${x.title}", ${money(x.price, x.basis)}${x.where ? `, ${x.where}` : ""}`
  );
  return `<shown_listings>\nListing cards shown to the user with this reply, in order:\n${lines.join("\n")}\n</shown_listings>`;
}

/** The transcript as Messages API turns. */
export function toMessages(turns: Turn[]): BetaMessageParam[] {
  return turns.map(t =>
    t.r === "u"
      ? { role: "user" as const, content: t.t }
      : {
          role: "assistant" as const,
          content: [t.t.trim(), t.l?.length ? shownBlock(t.l) : ""].filter(Boolean).join("\n\n") || "(no reply)",
        }
  );
}

/** Cards from earlier turns, so "compare the first two" and re-presenting still resolve. */
export function earlierListings(turns: Turn[]): ShownListing[] {
  return turns.flatMap(t => (t.r === "a" && t.l ? t.l : []));
}
