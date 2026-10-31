/**
 * The Claude models Akarat.ai's two assistants may run on, what they cost,
 * and how a model is chosen from the environment. Server-only.
 *
 * IDs and prices are from Anthropic's model catalogue as of October 2026:
 *   claude-sonnet-5-5  $2 / $10 per million input / output tokens, cache reads $0.20,
 *                      1M context, 128K output, effort low..max (default high,
 *                      levels recalibrated from Sonnet 5)
 *   claude-sonnet-5    the previous Sonnet, same prices
 *   claude-opus-5-5    $4 / $20, cache reads $0.20, effort default medium
 *   claude-haiku-5-5   $0.10 / $0.50 (prompts up to 100K tokens), for small jobs
 * Five-minute cache writes cost 1.25 times input; each web search $0.01.
 * The Anthropic Console's invoice is the record; these drive the estimates
 * the admin panel shows and the per-answer cost ceilings.
 */

export type Effort = "low" | "medium" | "high" | "xhigh";

export const KNOWN_MODELS = ["claude-sonnet-5-5", "claude-sonnet-5", "claude-opus-5-5", "claude-haiku-5-5"] as const;

const PRICES: Record<string, { input: number; output: number; cacheRead: number }> = {
  "claude-sonnet-5-5": { input: 2, output: 10, cacheRead: 0.2 },
  "claude-sonnet-5": { input: 2, output: 10, cacheRead: 0.2 },
  "claude-opus-5-5": { input: 4, output: 20, cacheRead: 0.2 },
  "claude-haiku-5-5": { input: 0.1, output: 0.5, cacheRead: 0.01 },
};
const PER_SEARCH = 0.01;

export type UsageLike = { input: number; output: number; cacheRead: number; cacheWrite: number; searches: number };

/** US dollars for some usage on a model, or null for a model with no known price. */
export function estimateCostUsd(u: UsageLike, model: string): number | null {
  const p = PRICES[model];
  if (!p) return null;
  const perM = (n: number, price: number) => (n / 1_000_000) * price;
  return perM(u.input, p.input) + perM(u.output, p.output) + perM(u.cacheRead, p.cacheRead) + perM(u.cacheWrite, p.input * 1.25) + u.searches * PER_SEARCH;
}

/**
 * Dollars counted against a per-answer ceiling. A model with no known price
 * is counted at the dearest known one, so the ceiling still holds for it.
 */
export function budgetCostUsd(u: UsageLike, model: string): number {
  return estimateCostUsd(u, model) ?? (estimateCostUsd(u, "claude-opus-5-5") as number);
}

/**
 * Whether a model costs at least as much per token as another: how "never a
 * cheaper model" is checked. A model with no known price is not, since
 * nothing here has tested it.
 */
export function notCheaper(model: string, than: string): boolean {
  const a = PRICES[model];
  const b = PRICES[than];
  return !!a && !!b && a.input >= b.input && a.output >= b.output;
}

const env = (name: string) => (process.env[name] ?? "").trim();

/**
 * A model from the environment, or the default. An id this code does not
 * know is still used (a newer model may not be listed here yet), but its
 * cost cannot be estimated, so the server says so once in its log.
 */
export function modelFromEnv(name: string, fallback: string): string {
  const v = env(name);
  if (!v) return fallback;
  if (!(KNOWN_MODELS as readonly string[]).includes(v)) {
    console.warn(JSON.stringify({ evt: "unknown_model", variable: name, model: v }));
  }
  return v;
}

export function effortFromEnv(name: string, fallback: Effort): Effort {
  const v = env(name);
  return v === "low" || v === "medium" || v === "high" || v === "xhigh" ? v : fallback;
}

export function numberFromEnv(name: string, fallback: number, min: number, max: number): number {
  const n = Number(env(name));
  return Number.isFinite(n) && env(name) !== "" && n >= min && n <= max ? n : fallback;
}
