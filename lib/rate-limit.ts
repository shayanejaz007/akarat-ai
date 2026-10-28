/* A counter in Postgres rather than in this process. Every serverless
   instance gets its own module scope, so the Map this replaced reset on each
   cold start and was never shared between concurrent instances — the limit it
   appeared to enforce was mostly decorative.

   Failing open is deliberate: a rate limiter that takes search down when the
   database hiccups is worse than the abuse it prevents.

   Shared by /api/ai/search and /api/translate. Keys are namespaced by the
   caller (e.g. "translate:<user id>") so one route's traffic does not spend
   another's allowance. */

/* Per-instance fallback, used only when the shared counter is unavailable
   because it was never configured. Weaker than the Postgres one — each
   serverless instance keeps its own map, so the effective limit is this
   number times however many instances are warm — but it bounds a single
   caller hammering one instance, which an unconfigured deployment otherwise
   has no answer to at all. */
const localHits = new Map<string, number[]>();

function allowLocally(key: string, perMinute: number): boolean {
  const now = Date.now();
  const recent = (localHits.get(key) ?? []).filter(t => now - t < 60_000);
  recent.push(now);
  localHits.set(key, recent);
  // Unbounded growth would be its own denial of service.
  if (localHits.size > 5000) {
    for (const [k, v] of localHits) {
      if (!v.length || now - v[v.length - 1] > 60_000) localHits.delete(k);
    }
  }
  return recent.length <= perMinute;
}

export async function allow(key: string, perMinute: number): Promise<boolean> {
  const url = process.env.NEXT_PUBLIC_SUPABASE_URL;
  const serviceKey = process.env.SUPABASE_SERVICE_ROLE_KEY;
  // Not configured is not the same as temporarily broken. Returning true here
  // meant a deployment that never set SUPABASE_SERVICE_ROLE_KEY had no limit
  // at all, permanently and silently: an audit of the live site ran 25
  // searches in a few seconds past a documented limit of 15 a minute without
  // one being refused. Fall back to the in-process counter, not to nothing.
  if (!url || !serviceKey) return allowLocally(key, perMinute);

  try {
    const res = await fetch(`${url}/rest/v1/rpc/check_rate_limit`, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        apikey: serviceKey,
        Authorization: `Bearer ${serviceKey}`,
      },
      body: JSON.stringify({ p_key: key, p_limit: perMinute, p_window_seconds: 60 }),
      cache: "no-store",
    });
    // 404 means the function was never installed (0008_hardening.sql has not
    // been run); 401/403 that the key is wrong. Those are configuration, not
    // a hiccup, so they get the fallback rather than a free pass.
    if (res.status === 404 || res.status === 401 || res.status === 403) {
      return allowLocally(key, perMinute);
    }
    // Anything else — a timeout, a 500 — is transient, and failing open there
    // is deliberate: taking search down when the database stumbles is worse
    // than the abuse it would prevent.
    if (!res.ok) return true;
    return (await res.json()) !== false;
  } catch {
    return true;
  }
}
