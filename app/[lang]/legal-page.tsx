import type { Metadata } from "next";
// Plain ESM, the same module the browser document loads at runtime.
import { legalDoc, LEGAL_UPDATED } from "../../lib/legal.js";

/**
 * The privacy policy and the terms of use, rendered on the server.
 *
 * These exist as their own URLs rather than only as a screen inside the
 * client-rendered document, because a policy that lives in client state has no
 * address. It cannot be linked in an email, cited in an app-store listing or a
 * payment provider's onboarding form, or indexed — and those are precisely the
 * places something asks for a privacy policy URL.
 *
 * The content comes from lib/legal.js, the same module the in-app screen
 * reads, so the two cannot say different things.
 */

export const revalidate = 3600;

const SITE = "https://akarat.ai";
type Lang = "en" | "ar";
type Which = "privacy" | "terms" | "deletion";

// The document key and its URL segment are not the same word: "deletion" is
// the key, /data-deletion is the path, because that is the phrase Facebook,
// Google Play and the App Store all use for the field they ask for. Building
// a URL straight from the key silently produced /ar/deletion, which 404s.
const PATH: Record<Which, string> = {
  privacy: "privacy",
  terms: "terms",
  deletion: "data-deletion",
};

const ink = "#17170F";
const cream = "#F7F2E7";

export function asLang(v: string): Lang {
  return v === "ar" ? "ar" : "en";
}

export function legalMetadata(which: Which, langRaw: string): Metadata {
  const lang = asLang(langRaw);
  const doc = legalDoc(which, lang);
  const path = `/${lang}/${PATH[which]}`;
  return {
    title: doc.title,
    description: doc.intro,
    alternates: {
      canonical: path,
      languages: {
        "ar-JO": `/ar/${PATH[which]}`,
        "en-JO": `/en/${PATH[which]}`,
        "x-default": `/en/${PATH[which]}`,
      },
    },
    openGraph: {
      type: "article",
      title: `${doc.title} — Akarat.ai`,
      description: doc.intro,
      url: path,
      locale: lang === "ar" ? "ar_JO" : "en_JO",
    },
    robots: { index: true, follow: true },
  };
}

export default function LegalPage({ which, langRaw }: { which: Which; langRaw: string }) {
  const lang = asLang(langRaw);
  const rtl = lang === "ar";
  const doc = legalDoc(which, lang);
  // The other two documents, so each page links to its siblings rather than
  // to a single hard-coded partner.
  const siblings: Which[] = (["privacy", "terms", "deletion"] as Which[]).filter((w) => w !== which);

  return (
    <main
      lang={lang}
      dir={rtl ? "rtl" : "ltr"}
      style={{
        background: cream,
        color: ink,
        minHeight: "100vh",
        margin: 0,
        fontFamily: rtl
          ? "'IBM Plex Sans Arabic', system-ui, sans-serif"
          : "system-ui, -apple-system, 'Segoe UI', sans-serif",
        fontWeight: 300,
      }}
    >
      <div style={{ maxWidth: 820, margin: "0 auto", padding: "40px 20px 80px" }}>
        <a
          href={`/${lang}`}
          style={{ fontSize: 13.5, color: "rgba(23,23,15,0.6)", textDecoration: "none" }}
        >
          {rtl ? "العودة إلى أكارات" : "Back to Akarat.ai"}
        </a>

        <div style={{ display: "flex", alignItems: "center", gap: 12, margin: "30px 0 14px" }}>
          <span style={{ width: 20, height: 1, background: "#CE1126", display: "block" }} />
          <span
            style={{
              fontSize: 11,
              letterSpacing: rtl ? "normal" : "0.2em",
              textTransform: rtl ? "none" : "uppercase",
              color: "rgba(23,23,15,0.54)",
            }}
          >
            {doc.kicker}
          </span>
        </div>

        <h1 style={{ margin: "0 0 10px", fontSize: "2.3rem", fontWeight: 300, letterSpacing: "-0.03em" }}>
          {doc.title}
        </h1>
        <p style={{ margin: "0 0 12px", fontSize: 15.5, lineHeight: 1.7, color: "rgba(23,23,15,0.6)" }}>
          {doc.intro}
        </p>
        <div
          style={{
            fontSize: 12.5,
            color: "rgba(23,23,15,0.5)",
            fontFamily: "ui-monospace, monospace",
            marginBottom: 42,
          }}
        >
          {LEGAL_UPDATED[lang]}
        </div>

        <div style={{ display: "grid", gap: 32 }}>
          {doc.sections.map((s: { h: string; p: string }) => (
            <section key={s.h}>
              <h2 style={{ margin: "0 0 10px", fontSize: 19, fontWeight: 400, letterSpacing: "-0.018em" }}>
                {s.h}
              </h2>
              <p style={{ margin: 0, fontSize: 15, lineHeight: 1.75, color: "rgba(23,23,15,0.7)" }}>
                {s.p}
              </p>
            </section>
          ))}
        </div>

        <div
          style={{
            marginTop: 48,
            paddingTop: 24,
            borderTop: "1px solid rgba(23,23,15,0.12)",
            display: "flex",
            gap: 18,
            flexWrap: "wrap",
            fontSize: 14,
          }}
        >
          {siblings.map((w) => (
            <a key={w} href={`/${lang}/${PATH[w]}`} style={{ color: "#007A3D", textDecoration: "none" }}>
              {legalDoc(w, lang).title}
            </a>
          ))}
          <a
            href={`/${lang === "ar" ? "en" : "ar"}/${PATH[which]}`}
            style={{ color: "rgba(23,23,15,0.6)", textDecoration: "none" }}
          >
            {rtl ? "English" : "عربي"}
          </a>
          <a href="mailto:privacy@akarat.ai" style={{ color: "rgba(23,23,15,0.6)", textDecoration: "none" }}>
            privacy@akarat.ai
          </a>
        </div>
      </div>
    </main>
  );
}

export { SITE };
