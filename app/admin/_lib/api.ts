"use client";

import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { useSearchParams } from "next/navigation";

/**
 * Talking to /api/admin/*. The session cookie (httpOnly, path /api/admin)
 * goes along on its own; every route checks it server-side before reading
 * anything, so nothing here decides who may see what.
 */

export class ApiError extends Error {
  status: number;
  constructor(message: string, status: number) {
    super(message);
    this.status = status;
  }
}

export type Api = <T>(path: string, init?: { method?: string; body?: unknown }) => Promise<T>;

export async function call<T>(path: string, init?: { method?: string; body?: unknown }): Promise<T> {
  let res: Response;
  try {
    res = await fetch(path, {
      method: init?.method ?? "GET",
      headers: init?.body !== undefined ? { "Content-Type": "application/json" } : {},
      body: init?.body !== undefined ? JSON.stringify(init.body) : undefined,
      cache: "no-store",
      credentials: "same-origin",
    });
  } catch {
    throw new ApiError("Can't reach the server. Check the connection and try again.", 0);
  }
  const body = (await res.json().catch(() => ({}))) as { error?: string };
  if (!res.ok) throw new ApiError(body.error || `Request failed (${res.status})`, res.status);
  return body as T;
}

/** call(), and a 401 (the session ran out, or the password changed) signs the panel out. */
export function makeApi(onExpired: () => void): Api {
  return async <T,>(path: string, init?: { method?: string; body?: unknown }) => {
    try {
      return await call<T>(path, init);
    } catch (e) {
      if (e instanceof ApiError && e.status === 401) onExpired();
      throw e;
    }
  };
}

/** A query string from the values that are set. */
export function qs(params: Record<string, string | number | null | undefined>): string {
  const u = new URLSearchParams();
  for (const [k, v] of Object.entries(params)) if (v !== null && v !== undefined && v !== "") u.set(k, String(v));
  return u.toString();
}

export type List<T> = {
  rows: T[] | null;
  total: number;
  pageSize: number;
  extra: Record<string, unknown>;
  error: ApiError | null;
  loading: boolean;
  reload: () => Promise<void>;
};

/**
 * One page of a list route. While a new page loads the old one stays on
 * screen (dimmed by the caller), so nothing jumps.
 */
export function useList<T>(api: Api, path: string, key: string, query: string): List<T> {
  const [data, setData] = useState<{ rows: T[] | null; total: number; pageSize: number; extra: Record<string, unknown> }>({
    rows: null,
    total: 0,
    pageSize: 50,
    extra: {},
  });
  const [error, setError] = useState<ApiError | null>(null);
  const [loading, setLoading] = useState(true);
  const seq = useRef(0);

  const reload = useCallback(async () => {
    const n = ++seq.current;
    setLoading(true);
    try {
      const body = await api<Record<string, unknown>>(query ? `${path}?${query}` : path);
      if (n !== seq.current) return; // a newer request has started
      setData({
        rows: Array.isArray(body[key]) ? (body[key] as T[]) : [],
        total: Number(body.total) || 0,
        pageSize: Number(body.pageSize) || 50,
        extra: body,
      });
      setError(null);
    } catch (e) {
      if (n === seq.current) setError(e instanceof ApiError ? e : new ApiError(String(e), 0));
    } finally {
      if (n === seq.current) setLoading(false);
    }
  }, [api, path, key, query]);

  useEffect(() => {
    void reload();
  }, [reload]);

  return { ...data, error, loading, reload };
}

export function useDebounced<T>(value: T, ms = 300): T {
  const [v, setV] = useState(value);
  useEffect(() => {
    const t = setTimeout(() => setV(value), ms);
    return () => clearTimeout(t);
  }, [value, ms]);
  return v;
}

/**
 * Filters kept in the address bar, so a filtered list can be bookmarked,
 * shared and reloaded. `defaults` must be a module-level constant. Writing
 * goes through history.replaceState: no navigation, no history entry per
 * keystroke, and Next keeps useSearchParams in step.
 */
export function useQuery<K extends string>(defaults: Record<K, string>): [Record<K, string>, (patch: Partial<Record<K, string>>) => void] {
  const params = useSearchParams();
  const key = params.toString();
  const values = useMemo(() => {
    const out = { ...defaults };
    for (const k of Object.keys(defaults) as K[]) {
      const v = params.get(k);
      if (v !== null) out[k] = v;
    }
    return out;
    // `key` stands for the params; `defaults` never changes.
  }, [key]);

  const set = useCallback(
    (patch: Partial<Record<K, string>>) => {
      const next = new URLSearchParams(window.location.search);
      for (const [k, v] of Object.entries(patch) as [K, string | undefined][]) {
        if (v === undefined || v === "" || v === defaults[k]) next.delete(k);
        else next.set(k, v);
      }
      const s = next.toString();
      window.history.replaceState(null, "", `${window.location.pathname}${s ? `?${s}` : ""}`);
    },
    [],
  );
  return [values, set];
}

/**
 * A search box over a value kept elsewhere (the address bar): what is typed
 * shows at once and is committed 300 ms after the last keystroke, and a
 * change from outside (the command palette) replaces what is typed.
 */
export function useSearchText(value: string, commit: (v: string) => void): [string, (v: string) => void] {
  const [text, setText] = useState(value);
  const debounced = useDebounced(text, 300);
  const commitRef = useRef(commit);
  commitRef.current = commit;
  useEffect(() => {
    if (debounced !== value) commitRef.current(debounced);
  }, [debounced]);
  useEffect(() => {
    if (value !== debounced) setText(value);
  }, [value]);
  return [text, setText];
}

/** A small preference kept in this browser. Only for conveniences: it may be unavailable. */
export function useStored<T extends string>(key: string, fallback: T, allowed: readonly T[]): [T, (v: T) => void] {
  const [value, setValue] = useState<T>(() => {
    try {
      const v = typeof window === "undefined" ? null : window.localStorage.getItem(key);
      return v !== null && (allowed as readonly string[]).includes(v) ? (v as T) : fallback;
    } catch {
      return fallback;
    }
  });
  const set = useCallback(
    (v: T) => {
      setValue(v);
      try {
        window.localStorage.setItem(key, v);
      } catch {
        /* private window or blocked storage: the choice lasts until reload */
      }
    },
    [key],
  );
  return [value, set];
}

/** Re-renders every `ms` so "updated 12s ago" stays true. */
export function useNow(ms: number): number {
  const [now, setNow] = useState(() => Date.now());
  useEffect(() => {
    const t = setInterval(() => setNow(Date.now()), ms);
    return () => clearInterval(t);
  }, [ms]);
  return now;
}
