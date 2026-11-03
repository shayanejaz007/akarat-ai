"use client";

import { Suspense, useCallback, useEffect, useMemo, useRef, useState, type ReactNode } from "react";
import { ApiError, call, makeApi, type Api } from "../_lib/api";
import type { Overview } from "../_lib/types";
import { AdminContext, type Theme } from "./context";
import { FeedbackProvider } from "./feedback";
import { Login, type Notice } from "./Login";
import { Shell } from "./Shell";
import { Skeleton } from "./ui";

/**
 * The admin panel's frame: checks the session, shows the sign-in screen when
 * there is none, and otherwise the panel with the overview kept fresh.
 *
 * Signing in is ADMIN_PASSWORD (Vercel environment variables), checked by
 * /api/admin/session, which sets an httpOnly cookie scoped to /api/admin.
 * Every figure comes from /api/admin/*, and each route checks that cookie
 * before reading anything. This file holds no key and decides nothing about
 * access: what it shows before or after signing in is only presentation.
 */

export const THEME_KEY = "akarat-admin-theme";

function readTheme(): Theme {
  try {
    const t = window.localStorage.getItem(THEME_KEY);
    return t === "light" || t === "dark" ? t : "system";
  } catch {
    return "system";
  }
}

/** Light or dark is set on #adm-root, which layout.tsx's script also reads before first paint. */
function applyTheme(t: Theme) {
  const root = document.getElementById("adm-root");
  if (t === "system") root?.removeAttribute("data-adm-theme");
  else root?.setAttribute("data-adm-theme", t);
  try {
    if (t === "system") window.localStorage.removeItem(THEME_KEY);
    else window.localStorage.setItem(THEME_KEY, t);
  } catch {
    /* storage blocked: the choice lasts until reload */
  }
}

export function AdminApp({ children }: { children: ReactNode }) {
  const [phase, setPhase] = useState<"checking" | "out" | "in">("checking");
  const [notice, setNotice] = useState<Notice | null>(null);
  const [theme, setThemeState] = useState<Theme>("system");

  useEffect(() => setThemeState(readTheme()), []);
  const setTheme = useCallback((t: Theme) => {
    setThemeState(t);
    applyTheme(t);
  }, []);

  useEffect(() => {
    let live = true;
    call("/api/admin/session")
      .then(() => live && setPhase("in"))
      .catch((e: ApiError) => {
        if (!live) return;
        if (e.status !== 401) setNotice({ tone: e.status === 503 ? "warn" : "bad", text: e.message });
        setPhase("out");
      });
    return () => {
      live = false;
    };
  }, []);

  const expired = useCallback(() => {
    setNotice({ tone: "info", text: "Your session ended. Sign in again to pick up where you left off." });
    setPhase("out");
  }, []);

  const signedOut = useCallback(() => {
    setNotice({ tone: "good", text: "You're signed out." });
    setPhase("out");
  }, []);

  return (
    <div className="adm">
      <FeedbackProvider>
        {phase === "checking" && <Splash />}
        {phase === "out" && (
          <Login
            notice={notice}
            onSignedIn={() => {
              setNotice(null);
              setPhase("in");
            }}
          />
        )}
        {phase === "in" && (
          <SignedIn onExpired={expired} onSignedOut={signedOut} theme={theme} setTheme={setTheme}>
            {children}
          </SignedIn>
        )}
      </FeedbackProvider>
    </div>
  );
}

function Splash() {
  return (
    <div className="adm-splash" role="status" aria-live="polite">
      {/* The brand mark; the words beside it name the screen. */}
      <img src="/assets/akarat-mark.png" alt="" width={44} height={56} className="adm-splash-mark" />
      <span className="adm-splash-text">Opening the admin panel…</span>
    </div>
  );
}

/** The overview: loaded on sign-in, then every 15 seconds while the tab is visible, and on return to it. */
function useOverview(api: Api) {
  const [overview, setOverview] = useState<Overview | null>(null);
  const [error, setError] = useState<ApiError | null>(null);
  const [at, setAt] = useState<number | null>(null);
  const busy = useRef(false);

  const refresh = useCallback(async () => {
    if (busy.current) return;
    busy.current = true;
    try {
      setOverview(await api<Overview>("/api/admin/overview"));
      setError(null);
      setAt(Date.now());
    } catch (e) {
      setError(e instanceof ApiError ? e : new ApiError(String(e), 0));
    } finally {
      busy.current = false;
    }
  }, [api]);

  useEffect(() => {
    void refresh();
    const t = setInterval(() => {
      if (document.visibilityState === "visible") void refresh();
    }, 15_000);
    const back = () => {
      if (document.visibilityState === "visible") void refresh();
    };
    document.addEventListener("visibilitychange", back);
    return () => {
      clearInterval(t);
      document.removeEventListener("visibilitychange", back);
    };
  }, [refresh]);

  return { overview, error, at, refresh };
}

function SignedIn({ children, onExpired, onSignedOut, theme, setTheme }: {
  children: ReactNode; onExpired: () => void; onSignedOut: () => void; theme: Theme; setTheme: (t: Theme) => void;
}) {
  const api = useMemo(() => makeApi(onExpired), [onExpired]);
  const { overview, error, at, refresh } = useOverview(api);

  const signOut = useCallback(async () => {
    await call("/api/admin/session", { method: "DELETE" }).catch(() => undefined);
    onSignedOut();
  }, [onSignedOut]);

  const value = useMemo(
    () => ({ api, overview, overviewError: error, overviewAt: at, refreshOverview: refresh, signOut, theme, setTheme }),
    [api, overview, error, at, refresh, signOut, theme, setTheme],
  );

  return (
    <AdminContext.Provider value={value}>
      <Shell>
        <Suspense fallback={<PageLoading />}>{children}</Suspense>
      </Shell>
    </AdminContext.Provider>
  );
}

export function PageLoading() {
  return (
    <div className="adm-page-loading" aria-busy="true" aria-label="Loading">
      <Skeleton w={220} h={28} r={8} />
      <Skeleton w={360} h={14} />
      <div className="adm-grid g-4" style={{ marginTop: 24 }}>
        {[0, 1, 2, 3].map(i => (
          <div key={i} className="adm-card adm-tile">
            <Skeleton w="50%" h={12} />
            <Skeleton w="40%" h={26} r={6} />
            <Skeleton w="70%" h={10} />
          </div>
        ))}
      </div>
    </div>
  );
}
