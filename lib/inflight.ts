/**
 * Requests still being answered, so an identical one (a double click, the
 * same question from a second tab) is refused instead of paid for twice.
 *
 * Per server instance, like the fallback rate limiter: two instances can
 * each take one copy. That is enough for what it is for; the per-minute and
 * daily limits still bound everything else.
 */
import { createHash } from "node:crypto";

const busy = new Map<string, number>();
// A request that never released (a crashed stream) frees itself after this.
const STALE_MS = 70_000;

/**
 * Marks a request as in flight. Returns the function that releases it, or
 * null when the same request from the same caller is already running.
 */
export function inFlight(caller: string, request: string): (() => void) | null {
  const now = Date.now();
  if (busy.size > 5000) {
    for (const [k, t] of busy) if (now - t > STALE_MS) busy.delete(k);
  }
  const key = `${caller}:${createHash("sha256").update(request).digest("hex").slice(0, 32)}`;
  const since = busy.get(key);
  if (since !== undefined && now - since < STALE_MS) return null;
  busy.set(key, now);
  let released = false;
  return () => {
    if (released) return;
    released = true;
    busy.delete(key);
  };
}
