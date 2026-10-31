/**
 * Pieces of a streamed Claude turn that the property advisor (lib/advisor)
 * and Ask a Lawyer (lib/legal) both need and that belong to neither: what to
 * send back after a mid-answer model switch, how an API failure reads to the
 * page, and which language a reply is in.
 */
import Anthropic from "@anthropic-ai/sdk";
import type { BetaContentBlock, BetaContentBlockParam } from "@anthropic-ai/sdk/resources/beta/messages/messages";

/**
 * What goes back to the API after a turn that switched models mid-answer.
 * Before the last switch point, only text and completed server-tool pairs are
 * echoed; the declined model's thinking and unfinished tool calls are not.
 */
export function echoable(content: BetaContentBlock[]): BetaContentBlockParam[] {
  const last = content.map(b => b.type).lastIndexOf("fallback");
  if (last < 0) return content as BetaContentBlockParam[];
  const answered = new Set(
    content.flatMap(b => (b.type === "web_search_tool_result" || b.type === "web_fetch_tool_result" ? [b.tool_use_id] : []))
  );
  return content.filter((b, i) => {
    if (i > last) return true;
    switch (b.type) {
      case "text":
      case "fallback":
      case "web_search_tool_result":
      case "web_fetch_tool_result":
        return true;
      case "server_tool_use":
        return answered.has(b.id);
      default:
        return false;
    }
  }) as BetaContentBlockParam[];
}

/** An API failure as the page's error codes put it. */
export function apiErrorCode(e: unknown): "not_configured" | "busy" | "unavailable" {
  if (e instanceof Anthropic.AuthenticationError || e instanceof Anthropic.PermissionDeniedError) return "not_configured";
  if (e instanceof Anthropic.RateLimitError) return "busy";
  if (e instanceof Anthropic.APIError && (e.status === 529 || e.status === 503)) return "busy";
  return "unavailable";
}

// "I searched…", "after checking…", "بحثت…": a claim to have researched. An
// answer making one when no tool ran in its turn is flagged by the agents.
const RESEARCH_CLAIM =
  /\b(?:I|I've|I have|we|we've)\s+(?:just\s+)?(?:searched|looked (?:up|through|into)|checked|researched|browsed|verified|reviewed (?:the|our|current) (?:listings|sources|market|law|laws))\b|\b(?:after|from) (?:searching|checking|my search|my research)\b|\baccording to my (?:search|research)\b|بحثت|دوّرت|دورت|تحققت|تحقّقت|راجعت المصادر|حسب بحثي|بعد البحث|من خلال بحثي/i;

export function claimsResearch(text: string): boolean {
  return RESEARCH_CLAIM.test(text);
}

/** The share of a text's letters that are Arabic. */
export function arabicShare(s: string): number {
  const letters = s.match(/\p{L}/gu)?.length ?? 0;
  const arabic = s.match(/[ء-ي]/g)?.length ?? 0;
  return letters ? arabic / letters : 0;
}
