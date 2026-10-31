/**
 * One turn of the advisor: the user's message in, a streamed reply out.
 *
 * A manual loop rather than the SDK's tool runner, because the turn is also a
 * stream to the browser: text, progress, listing cards and sources are
 * forwarded as they happen, every tool result is checked before the model
 * sees it, and the loop owns the time and cost limits in config.ts. The
 * contract with the browser is the ClientEvent union below, sent as one JSON
 * object per line.
 */
import Anthropic from "@anthropic-ai/sdk";
import { apiErrorCode, arabicShare, claimsResearch, echoable } from "../claude-shared.ts";
import type {
  BetaContentBlock,
  BetaMessage,
  BetaMessageParam,
  BetaTextBlockParam,
  BetaTextCitation,
  BetaToolResultBlockParam,
  BetaToolUseBlockParam,
} from "@anthropic-ai/sdk/resources/beta/messages/messages";
import { budgetCostUsd, estimateCostUsd } from "../ai-models.ts";
import { suggestFollowups } from "../followups.ts";
import { INVESTMENT_TALK, TURN, WEB_DOMAINS, hostAllowed, routeAdvisor, type Route } from "./config.ts";
import { normalizeUrl } from "./evidence.ts";
import { CANARY, SYSTEM_PROMPT, looksLikePromptLeak, turnContext, type TurnContext } from "./prompt.ts";
import { TOOLS, runTool, type Card, type PageEvent, type ToolEnv } from "./tools.ts";
import { remember, toMessages, type ShownListing, type Turn } from "./transcript.ts";
import type { TurnUsage } from "./usage.ts";

export type Source = { n: number; url: string; title: string; host: string; date: string | null };

export type ClientEvent =
  | { t: "status"; s: string; q?: string; host?: string }
  | { t: "text"; d: string }
  | { t: "source"; s: Source }
  | { t: "cite"; n: number[] }
  | { t: "redact"; reason: "leak" | "refused" }
  | { t: "notice"; kind: "disclaimer" | "partial" | "memory_reset" | "unbacked_claim"; lang?: "en" | "ar" }
  | PageEvent
  | { t: "followups"; items: string[] }
  | { t: "done"; transcript: string | null }
  | { t: "error"; code: "busy" | "unavailable" | "not_configured" | "rate_limited" | "quota" | "quota_total" | "bad_request" | "too_long" };

export type TurnOptions = {
  client: Anthropic;
  history: Turn[];
  message: string;
  context: TurnContext;
  env: ToolEnv;
  emit: (e: ClientEvent) => void;
  signal: AbortSignal;
  now?: () => number;
  /** Which model and effort answer; routeAdvisor(message) when not given. */
  route?: Route;
  /** Follow-up suggestions after the answer; tests switch them off. */
  followups?: boolean;
};

export type TurnResult = {
  status: "complete" | "partial" | "refused" | "leak" | "error" | "aborted";
  reply: string;
  shown: ShownListing[];
  usage: TurnUsage;
  flags: string[];
  tools: string[];
  route: Route;
  /** Estimated US dollars for the whole turn, follow-ups included. */
  costUsd: number | null;
  error?: Extract<ClientEvent, { t: "error" }>["code"];
};

const STATUS_OF: Record<string, string> = {
  search_akarat_listings: "akarat_search",
  get_akarat_listing: "akarat_listing",
  akarat_price_stats: "akarat_stats",
  investment_calculator: "calc",
  compare_listings: "compare",
};

// Text that must never reach the page: the private-use characters the page
// uses to mark citations, and the rest of the invisible formatting set.
const STRIP = /[\ue000-\uf8ff\u202a-\u202e\u2066-\u2069]/g;

const DISCLAIMED = /involves? risk|do your own research|conduct your own research|verify all information|فيه مخاطر|بحثك الخاص|مخاطر الاستثمار/i;

// What the model is told when a turn ends without a visible answer. On Claude
// Sonnet 5.5 and Opus 5.5, text written before a tool call comes back as a
// hidden progress note, so an answer placed there never reaches the page.
export const NO_ANSWER_NOTE =
  "Your answer did not reach the user: text written before a tool call is not shown. " +
  "Write your complete answer now as your final message, using what your tools returned, and do not call any tool.";

// Shared with Ask a Lawyer; re-exported because the advisor's tests import it from here.
export { echoable };
const errorCode = apiErrorCode;

export async function runTurn(o: TurnOptions): Promise<TurnResult> {
  const now = o.now ?? Date.now;
  const started = now();
  const { env, emit } = o;
  const route = o.route ?? routeAdvisor(o.message);
  // Set when a turn ended with nothing visible and the model is asked once
  // for its answer, with no tools.
  let answerRetried = false;
  let forceFinal = false;

  const ac = new AbortController();
  let timedOut = false;
  const onClientGone = () => ac.abort();
  o.signal.addEventListener("abort", onClientGone);
  const hard = setTimeout(() => {
    timedOut = true;
    ac.abort();
  }, TURN.hardMs);

  const system: BetaTextBlockParam[] = [
    { type: "text", text: SYSTEM_PROMPT, cache_control: { type: "ephemeral" } },
    { type: "text", text: turnContext(o.context) },
  ];
  const messages: BetaMessageParam[] = [...toMessages(o.history), { role: "user", content: o.message }];

  const usage: TurnUsage = { input: 0, output: 0, cacheRead: 0, cacheWrite: 0, searches: 0, fetches: 0 };
  const flags: string[] = [];
  const toolsUsed: string[] = [];
  const sources = new Map<string, Source>();
  let reply = "";
  let afterTool = false;
  let checkedAt = 0;
  let leaked = false;
  let status: TurnResult["status"] = "complete";
  let wrapUpSent = false;
  let errorOut: TurnResult["error"];
  // The stream in flight, so a turn cut short still counts what it used.
  let live: { currentMessage: BetaMessage | undefined } | null = null;

  // The last HOLD characters of the reply are held back until more arrives,
  // so the screening below sees text before the page does: a canary split
  // across two deltas, or the opening words of a recital, never leave here.
  // At about two short sentences it is not a delay anyone reads.
  const HOLD = 120;
  let held = "";
  const release = (all: boolean) => {
    if (leaked) return;
    const keep = all ? 0 : HOLD;
    if (held.length <= keep) return;
    emit({ t: "text", d: held.slice(0, held.length - keep) });
    held = held.slice(held.length - keep);
  };
  const onText = (raw: string) => {
    const d = raw.replace(STRIP, "");
    if (!d || leaked) return;
    const tail = reply.slice(-CANARY.length) + d;
    reply += d;
    held += d;
    // The canary on every delta; the comparison against the instructions
    // every few dozen characters, which is cheap at these lengths.
    if (tail.includes(CANARY) || (reply.length - checkedAt >= 40 && looksLikePromptLeak(reply))) {
      leaked = true;
      held = "";
      return;
    }
    if (reply.length - checkedAt >= 40) checkedAt = reply.length;
    release(false);
  };
  // A text block has ended: screen what is held, then let it go.
  const settle = () => {
    if (!leaked && looksLikePromptLeak(reply)) {
      leaked = true;
      held = "";
    }
    release(true);
  };

  const cite = (citations: BetaTextCitation[]) => {
    const ns = new Set<number>();
    for (const c of citations) {
      let url: string | undefined;
      let title: string | null | undefined;
      if (c.type === "web_search_result_location") {
        url = c.url;
        title = c.title;
      } else if (c.type === "char_location") {
        const doc = env.evidence.documents[c.document_index] ?? env.evidence.documents.find(d => d.title === c.document_title);
        url = doc?.url;
        title = doc?.title || c.document_title;
      }
      if (!url) continue;
      const k = normalizeUrl(url);
      let host = "";
      try {
        host = new URL(url).hostname.replace(/^www\./, "");
      } catch {
        continue;
      }
      if (!k || !hostAllowed(host, WEB_DOMAINS)) continue;
      let s = sources.get(k);
      if (!s) {
        s = {
          n: sources.size + 1,
          url,
          title: String(title || host).replace(STRIP, "").slice(0, 160),
          host,
          date: env.evidence.result(url)?.pageAge ?? env.evidence.page(url)?.retrievedAt ?? null,
        };
        sources.set(k, s);
        emit({ t: "source", s });
      }
      ns.add(s.n);
    }
    if (ns.size) emit({ t: "cite", n: [...ns].sort((a, b) => a - b) });
  };

  // Results of web_search and web_fetch, recorded as they stream so the
  // checks in evidence.ts and the citations above can use them at once.
  const serverInputs = new Map<string, { name: string; input: Record<string, unknown> }>();
  // Each result once: it is seen as it streams and again in the final copy of
  // the message, and a page read twice would shift every citation after it.
  const recorded = new Set<string>();
  const recordServerResult = (b: BetaContentBlock) => {
    if (b.type === "web_search_tool_result" || b.type === "web_fetch_tool_result") {
      if (recorded.has(b.tool_use_id)) return;
      recorded.add(b.tool_use_id);
    }
    if (b.type === "web_search_tool_result") {
      if (Array.isArray(b.content)) {
        for (const r of b.content) {
          if (r.type === "web_search_result") env.evidence.addResult({ url: r.url, title: r.title, pageAge: r.page_age });
        }
      }
    } else if (b.type === "web_fetch_tool_result") {
      const c = b.content;
      if (c.type === "web_fetch_result") {
        const src = c.content.source;
        env.evidence.addPage({
          url: c.url,
          title: c.content.title ?? "",
          text: src.type === "text" ? src.data : "",
          retrievedAt: c.retrieved_at,
        });
      } else {
        const asked = serverInputs.get(b.tool_use_id)?.input.url;
        if (typeof asked === "string") env.evidence.addFailure(asked);
      }
    }
  };

  const addUsage = (m: BetaMessage) => {
    const u = m.usage;
    usage.input += u.input_tokens ?? 0;
    usage.output += u.output_tokens ?? 0;
    usage.cacheRead += u.cache_read_input_tokens ?? 0;
    usage.cacheWrite += u.cache_creation_input_tokens ?? 0;
    usage.searches += u.server_tool_use?.web_search_requests ?? 0;
    usage.fetches += u.server_tool_use?.web_fetch_requests ?? 0;
  };

  emit({ t: "status", s: "thinking" });

  try {
    for (let call = 1; ; call++) {
      const last = call >= TURN.maxModelCalls;
      const stream = o.client.beta.messages.stream(
        {
          model: route.model,
          max_tokens: route.maxTokens,
          system,
          tools: TOOLS,
          messages,
          thinking: { type: "adaptive" },
          output_config: { effort: route.effort },
          cache_control: { type: "ephemeral" },
          // A policy decline on an ordinary property question would be a
          // false positive; the API retries it on its recommended model.
          betas: ["server-side-fallback-2026-07-01"],
          fallbacks: "default",
          ...(last || forceFinal ? { tool_choice: { type: "none" as const } } : {}),
        },
        { signal: ac.signal }
      );
      live = stream;

      const blocks = new Map<number, { type: string; name: string; id: string; json: string; cites: BetaTextCitation[] }>();
      for await (const ev of stream) {
        if (ev.type === "content_block_start") {
          const b = ev.content_block;
          blocks.set(ev.index, {
            type: b.type,
            name: "name" in b && typeof b.name === "string" ? b.name : "",
            id: "id" in b && typeof b.id === "string" ? b.id : "",
            json: "",
            cites: [],
          });
          recordServerResult(b);
          if (b.type === "text") {
            // Text written either side of a tool call is two paragraphs, not
            // one run-on sentence. Text split only by citations stays joined.
            if (afterTool && reply && !/\n\s*$/.test(reply)) onText("\n\n");
            afterTool = false;
            if (b.text) onText(b.text);
          } else if (b.type !== "thinking" && b.type !== "redacted_thinking") {
            afterTool = true;
          }
        } else if (ev.type === "content_block_delta") {
          const st = blocks.get(ev.index);
          const d = ev.delta;
          if (d.type === "text_delta") onText(d.text);
          else if (d.type === "input_json_delta" && st) st.json += d.partial_json;
          else if (d.type === "citations_delta" && st) st.cites.push(d.citation);
        } else if (ev.type === "content_block_stop") {
          const st = blocks.get(ev.index);
          if (!st) continue;
          if (st.type === "text") {
            settle();
            if (st.cites.length && !leaked) cite(st.cites);
          }
          if (st.type === "server_tool_use" || st.type === "tool_use") {
            let input: Record<string, unknown> = {};
            try {
              input = st.json ? JSON.parse(st.json) : {};
            } catch {
              /* reported when the tool runs */
            }
            if (st.type === "server_tool_use") {
              serverInputs.set(st.id, { name: st.name, input });
              if (st.name === "web_search") emit({ t: "status", s: "web_search", q: String(input.query ?? "").replace(STRIP, "").slice(0, 120) });
              if (st.name === "web_fetch") {
                let host = "";
                try {
                  host = new URL(String(input.url)).hostname.replace(/^www\./, "");
                } catch {
                  /* the API will refuse it */
                }
                emit({ t: "status", s: "web_fetch", host });
              }
            } else if (STATUS_OF[st.name]) {
              emit({ t: "status", s: STATUS_OF[st.name] });
            }
          }
        }
        if (leaked) break;
      }
      if (leaked) {
        // What was generated before the cut is still billed: count it.
        const partial = stream.currentMessage;
        stream.abort();
        if (partial) addUsage(partial);
        status = "leak";
        break;
      }

      const msg = await stream.finalMessage();
      live = null;
      addUsage(msg);
      // Anything the stream events missed (they should not), from the final copy.
      for (const b of msg.content) recordServerResult(b);

      if (msg.stop_reason === "refusal") {
        status = "refused";
        break;
      }
      const content = echoable(msg.content);
      if (msg.stop_reason === "pause_turn") {
        // The server paused its own search loop; send the turn back unchanged
        // and it resumes. Counts as a call, so the loop still ends.
        messages.push({ role: "assistant", content });
        if (last) {
          status = "partial";
          break;
        }
        continue;
      }
      // Every tool_use is ours (server tools arrive as server_tool_use); a
      // name that is not a tool gets an error result from runTool.
      const uses = content.filter((b): b is BetaToolUseBlockParam => b.type === "tool_use");
      if (msg.stop_reason === "max_tokens") {
        // A tool call cut off mid-input can still parse; never run it.
        status = "partial";
        break;
      }
      if (!uses.length) {
        // The model has finished. If nothing it wrote is visible (its answer
        // went before a tool call and came back as a hidden note), it is
        // asked once for the answer, with tools off.
        if (!reply.trim() && !answerRetried && call < TURN.maxModelCalls && now() - started < TURN.softMs + 8000) {
          answerRetried = true;
          forceFinal = true;
          flags.push("answer_retry");
          messages.push({ role: "assistant", content });
          messages.push({ role: "system", content: NO_ANSWER_NOTE });
          continue;
        }
        break;
      }

      messages.push({ role: "assistant", content });
      const outcomes = await Promise.all(uses.map(u => runTool(u.name, u.input, env)));
      const results: BetaToolResultBlockParam[] = uses.map((u, i) => ({
        type: "tool_result",
        tool_use_id: u.id,
        content: outcomes[i].content,
        ...(outcomes[i].isError ? { is_error: true } : {}),
      }));
      for (const [i, out] of outcomes.entries()) {
        toolsUsed.push(uses[i].name);
        if (out.flag) flags.push(out.flag);
        for (const e of out.events ?? []) emit(e);
      }

      if (last) {
        status = "partial";
        break;
      }

      messages.push({ role: "user", content: results });

      const late = now() - started > TURN.softMs;
      const spent =
        usage.searches >= TURN.webSearchesPerTurn ||
        usage.fetches >= TURN.webFetchesPerTurn ||
        usage.output >= TURN.outputBudget ||
        budgetCostUsd(usage, route.model) >= TURN.maxCostUsd ||
        call + 1 >= TURN.maxModelCalls;
      if ((late || spent) && !wrapUpSent) {
        // An operator note appended to the conversation, not an edit to it:
        // the cached prefix and this turn's earlier reasoning stay valid.
        messages.push({
          role: "system",
          content:
            "Time and research budget for this reply are used up. Do not call web_search or web_fetch again. " +
            "If you found suitable listings, present them, then write your answer as your final message with what you have, and say what you could not check.",
        });
        wrapUpSent = true;
      }
    }
  } catch (e) {
    const partial = live?.currentMessage;
    if (partial) addUsage(partial);
    if (e instanceof Anthropic.APIUserAbortError || ac.signal.aborted) {
      status = timedOut ? "partial" : "aborted";
    } else {
      status = "error";
      errorOut = errorCode(e);
      // The status and the API's own message are enough to diagnose a schema
      // or configuration problem; the conversation is never logged.
      console.error("advisor turn failed", e instanceof Anthropic.APIError ? { status: e.status, message: e.message } : e);
    }
  } finally {
    clearTimeout(hard);
    o.signal.removeEventListener("abort", onClientGone);
  }

  // Whatever is still held: screened, then sent, unless the reply is being
  // withdrawn anyway.
  if (status !== "refused") settle();
  if (leaked) status = "leak";
  if (status === "leak") {
    flags.push("prompt_leak");
    emit({ t: "redact", reason: "leak" });
    reply = "";
  } else if (status === "refused") {
    flags.push("refusal");
    emit({ t: "redact", reason: "refused" });
    reply = "";
  } else if (status === "partial") {
    emit({ t: "notice", kind: "partial" });
  } else if (status === "error" && errorOut) {
    emit({ t: "error", code: errorOut });
  }

  const lang: "en" | "ar" = arabicShare(reply || o.message) > 0.3 ? "ar" : "en";
  const answered = (status === "complete" || status === "partial") && !!reply.trim();
  const aboutInvesting = toolsUsed.includes("investment_calculator") || INVESTMENT_TALK.test(`${o.message}\n${reply}`);
  if (answered && aboutInvesting && !DISCLAIMED.test(reply)) {
    emit({ t: "notice", kind: "disclaimer", lang });
  }
  // An answer that says it searched when nothing was searched: checked here,
  // not left to the model.
  if (answered && !toolsUsed.length && !usage.searches && !usage.fetches && claimsResearch(reply)) {
    flags.push("unbacked_research_claim");
    emit({ t: "notice", kind: "unbacked_claim", lang });
  }

  let costUsd = estimateCostUsd(usage, route.model);
  // Follow-up suggestions, from a separate small call once the answer is
  // written, while there is time left in the function's budget.
  if (answered && o.followups !== false && now() - started < TURN.hardMs - 7000) {
    const f = await suggestFollowups(o.client, { domain: "property", lang, question: o.message, answer: reply });
    if (f.items.length) emit({ t: "followups", items: f.items });
    // Priced at its own model's rate; usage stays the answering model's,
    // which is what the admin panel's token-based estimate prices.
    const extra = estimateCostUsd(f.usage, f.model);
    costUsd = costUsd == null || extra == null ? costUsd : costUsd + extra;
  }

  const shown = env.shownThisTurn.map(k => env.cards.get(k)).filter((c): c is Card => !!c).map(remember);
  return { status, reply: reply.trim(), shown, usage, flags, tools: toolsUsed, route, costUsd, error: errorOut };
}
