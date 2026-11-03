"use client";

import { useState, type FormEvent, type KeyboardEvent } from "react";
import { ApiError, call } from "../_lib/api";
import { Icon, type IconName } from "./icons";
import { Button, Callout } from "./ui";

export type Notice = { tone: "info" | "good" | "warn" | "bad"; text: string };

const FEATURES: { icon: IconName; title: string; body: string }[] = [
  { icon: "activity", title: "Live, as it happens", body: "Who is on the website, Android and iPhone right now." },
  { icon: "shield", title: "Every review in one queue", body: "Daily rentals, reported listings and new accounts." },
  { icon: "sparkles", title: "Both AI assistants, measured", body: "Use, cost and answer quality for Property AI and Ask a Lawyer." },
];

/**
 * The sign-in screen: the brand on one side, the password on the other. The
 * password is ADMIN_PASSWORD in Vercel; /api/admin/session checks it (five
 * tries a minute per address) and sets the session cookie.
 */
export function Login({ notice, onSignedIn }: { notice: Notice | null; onSignedIn: () => void }) {
  const [password, setPassword] = useState("");
  const [shown, setShown] = useState(false);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState("");
  const [caps, setCaps] = useState(false);
  const [shake, setShake] = useState(false);

  async function submit(e: FormEvent) {
    e.preventDefault();
    if (!password) return setError("Enter the admin password.");
    setBusy(true);
    setError("");
    try {
      await call("/api/admin/session", { method: "POST", body: { password } });
      onSignedIn();
    } catch (err) {
      const status = err instanceof ApiError ? err.status : 0;
      setError(status === 401 ? "That password isn't right. Check it and try again." : (err as Error).message);
      setShake(true);
      setBusy(false);
    }
  }

  const capsCheck = (e: KeyboardEvent<HTMLInputElement>) => setCaps(e.getModifierState?.("CapsLock") ?? false);
  const year = new Date().getFullYear();

  return (
    <div className="adm-login">
      <aside className="adm-login-brand">
        <div className="adm-login-brand-top">
          <img src="/assets/akarat-mark.png" alt="" width={28} height={36} />
          <span className="adm-login-wordmark">Akarat.ai</span>
          <span className="adm-login-tag">Admin</span>
        </div>

        <div className="adm-login-hero">
          <div className="adm-login-glow" aria-hidden="true" />
          <img src="/assets/akarat-logo.png" alt="Akarat.ai" className="adm-login-logo" width={940} height={800} />
          <h2>The control room for Akarat.ai.</h2>
          <p>Listings, reviews, people and both AI assistants, live, in one place.</p>
          <ul className="adm-login-features">
            {FEATURES.map(f => (
              <li key={f.title}>
                <span className="adm-login-feature-icon"><Icon name={f.icon} size={17} /></span>
                <div>
                  <b>{f.title}</b>
                  <span>{f.body}</span>
                </div>
              </li>
            ))}
          </ul>
        </div>

        <div className="adm-login-brand-foot">
          <span>© {year} Akarat.ai · Amman, Jordan</span>
          <span className="adm-login-secure"><Icon name="lock" size={13} /> Encrypted session · signs out after 12 hours</span>
        </div>
        <Skyline />
      </aside>

      <main className="adm-login-main">
        <form className="adm-login-form" onSubmit={submit} noValidate>
          <div className="adm-login-mobile-brand">
            <img src="/assets/akarat-mark.png" alt="" width={34} height={43} />
            <span className="adm-login-wordmark">Akarat.ai</span>
            <span className="adm-login-tag">Admin</span>
          </div>

          <div className="adm-login-heading">
            <span className="adm-login-key"><Icon name="key" size={20} /></span>
            <h1>Sign in to the admin panel</h1>
            <p>Enter the admin password to continue.</p>
          </div>

          {notice && <Callout tone={notice.tone}>{notice.text}</Callout>}

          {/* For password managers: the panel has one account, "admin". */}
          <input type="text" name="username" autoComplete="username" value="admin" readOnly hidden />

          <div className="adm-field">
            <label className="adm-field-label" htmlFor="adm-password">Password</label>
            <div className={`adm-password${error ? " is-invalid" : ""}${shake ? " is-shaking" : ""}`} onAnimationEnd={() => setShake(false)}>
              <Icon name="lock" size={17} />
              <input
                id="adm-password"
                type={shown ? "text" : "password"}
                autoComplete="current-password"
                autoFocus
                value={password}
                onChange={e => {
                  setPassword(e.target.value);
                  if (error) setError("");
                }}
                onKeyDown={capsCheck}
                onKeyUp={capsCheck}
                aria-invalid={!!error || undefined}
                aria-describedby={error ? "adm-password-error" : caps ? "adm-password-caps" : undefined}
                placeholder="••••••••••"
                spellCheck={false}
              />
              <button type="button" className="adm-password-toggle" onClick={() => setShown(s => !s)} aria-label={shown ? "Hide password" : "Show password"} aria-pressed={shown}>
                <Icon name={shown ? "eyeOff" : "eye"} size={17} />
              </button>
            </div>
            {error ? (
              <span id="adm-password-error" className="adm-field-hint is-bad" role="alert">{error}</span>
            ) : caps ? (
              <span id="adm-password-caps" className="adm-field-hint is-warn">Caps Lock is on.</span>
            ) : null}
          </div>

          <Button type="submit" variant="primary" wide loading={busy} iconEnd="arrowRight">
            {busy ? "Signing in…" : "Sign in"}
          </Button>

          <p className="adm-login-help">
            The password is <code>ADMIN_PASSWORD</code> in Vercel → Project → Settings → Environment Variables.
            Changing it there and redeploying signs every admin out.
          </p>

          <a className="adm-login-back" href="/">
            <Icon name="chevronLeft" size={15} /> Back to akarat.ai
          </a>
        </form>
      </main>
    </div>
  );
}

/** A quiet skyline along the bottom of the brand panel, in the logo's gold. */
function Skyline() {
  return (
    <svg className="adm-login-skyline" viewBox="0 0 600 160" preserveAspectRatio="xMidYMax slice" aria-hidden="true">
      <path d="M0 160V118h34V92h22v26h18V70h30v48h16V100h26V54h20V36h26v18h18v64h22V84h34v34h14V64h28V20h30v44h18v54h22V96h26v22h20V74h34v44h18V58h24v60h22V90h28v28h26V104h24v56z" />
    </svg>
  );
}
