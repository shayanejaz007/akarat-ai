"use client";

import { useEffect, useState } from "react";
import { useAdmin } from "../_components/context";
import { Icon, type IconName } from "../_components/icons";
import { Badge, Button, Card, KV, PageHeader, cx } from "../_components/ui";
import { full, when } from "../_lib/format";

/*
 * What is set up and what is not: which database migrations the panel can
 * see, how the two AI assistants are configured, this session, and where
 * the dashboards are. Everything here is read from the server's answers;
 * a feature the overview cannot read shows as missing, whatever the reason.
 */

type State = "ok" | "missing" | "unknown";

const SUPABASE = process.env.NEXT_PUBLIC_SUPABASE_URL ?? "";
const supabaseRef = /^https:\/\/([a-z0-9]+)\.supabase\.co/i.exec(SUPABASE)?.[1] ?? null;

export default function SystemPage() {
  const { api, overview, overviewError, signOut, theme } = useAdmin();
  const [expiresAt, setExpiresAt] = useState<number | null>(null);
  const [reports, setReports] = useState<State>("unknown");

  useEffect(() => {
    api<{ ok: boolean; expiresAt?: number }>("/api/admin/session")
      .then(s => setExpiresAt(s.expiresAt ?? null))
      .catch(() => setExpiresAt(null));
    api<{ notSetUp?: boolean }>("/api/admin/reports?status=open")
      .then(r => setReports(r.notSetUp ? "missing" : "ok"))
      .catch(() => setReports("unknown"));
  }, [api]);

  const known = !!overview;
  const has = (v: unknown): State => (known ? (v ? "ok" : "missing") : "unknown");
  const measured = overview?.advisor ?? overview?.legal;
  const checks: { name: string; file: string; what: string; state: State }[] = [
    { name: "Analytics and live activity", file: "0018_admin_analytics.sql", what: "Views, sessions and the overview", state: known ? "ok" : overviewError?.status === 501 ? "missing" : "unknown" },
    { name: "Listing reports", file: "0015_listing_reports.sql", what: "“Report this listing” in the app", state: reports },
    { name: "Daily rentals and bookings", file: "0019_daily_rentals.sql", what: "The review queue and booking requests", state: has(overview?.dailyRentals) },
    { name: "Property AI records", file: "0020_ai_advisor.sql", what: "The advisor's use, limits and flags", state: has(overview?.advisor) },
    { name: "Ask a Lawyer", file: "0021_legal_ai.sql", what: "The legal library, answers and reports", state: has(overview?.legal) },
    { name: "Measured AI cost", file: "0022_ai_cost.sql", what: "What each answer cost, and which model gave it", state: measured ? has(measured.measured) : "unknown" },
  ];
  const left = expiresAt ? Math.max(0, expiresAt - Date.now()) : null;

  return (
    <>
      <PageHeader title="System" subtitle="What is set up, how the assistants are configured, and this session." />

      <div className="adm-grid g-12">
        <Card className="span-7" title="Database features" caption="Each comes from a migration in supabase/migrations, run in Supabase → SQL Editor">
          <ul className="adm-checks">
            {checks.map(c => (
              <li key={c.file}>
                <StateIcon state={c.state} />
                <div className="adm-check-text">
                  <div className="adm-cell-strong">{c.name}</div>
                  <div className="adm-cell-sub">{c.what} · <code>{c.file}</code></div>
                </div>
                <Badge tone={c.state === "ok" ? "good" : c.state === "missing" ? "warn" : "neutral"}>
                  {c.state === "ok" ? "Working" : c.state === "missing" ? "Not available" : "Checking…"}
                </Badge>
              </li>
            ))}
          </ul>
          <p className="adm-hint">“Not available” means the panel can&apos;t read that feature: usually its migration hasn&apos;t been run yet.</p>
        </Card>

        <Card className="span-5" title="This session" icon="lock">
          <KV
            items={[
              { k: "Signed in as", v: "admin (ADMIN_PASSWORD)" },
              { k: "Session ends", v: expiresAt ? `${when(new Date(expiresAt).toISOString())} · in ${Math.floor((left ?? 0) / 3_600_000)} h ${Math.floor(((left ?? 0) % 3_600_000) / 60_000)} min` : "—" },
              { k: "Theme", v: theme === "system" ? "Matches the device" : theme === "dark" ? "Dark" : "Light" },
            ]}
          />
          <p className="adm-hint">
            Sessions last 12 hours. To sign every admin out at once, change <code>ADMIN_PASSWORD</code> in Vercel and redeploy.
          </p>
          <Button variant="secondary" icon="logout" onClick={() => void signOut()}>Sign out</Button>
        </Card>
      </div>

      <div className="adm-grid g-2">
        <Card title="Property AI" icon="sparkles" caption="POST /api/ai/advisor">
          {overview?.advisor ? (
            <KV
              items={[
                { k: "Default model", v: <code>{overview.advisor.model}</code> },
                { k: "Each signed-in person", v: `${full(overview.advisor.limits.perDaySignedIn)} questions a day` },
                { k: "Each visitor not signed in", v: `${full(overview.advisor.limits.perDayAnonymous)} questions a day` },
                { k: "Everyone together", v: `${full(overview.advisor.limits.perDayTotal)} questions a day` },
              ]}
            />
          ) : (
            <p className="adm-cell-sub">Not recording: run <code>0020_ai_advisor.sql</code>.</p>
          )}
        </Card>
        <Card title="Ask a Lawyer" icon="scale" caption="/api/legal/*">
          {overview?.legal ? (
            <KV
              items={[
                { k: "Default model", v: <code>{overview.legal.model}</code> },
                {
                  k: "Who can ask",
                  v: overview.legal.access === "public" ? (
                    <Badge tone="good" dot>Every signed-in account</Badge>
                  ) : (
                    <Badge tone="warn" dot>{full(overview.legal.reviewers)} reviewers (LEGAL_REVIEWERS)</Badge>
                  ),
                },
                { k: "Each person", v: `${full(overview.legal.limits.perDay)} questions a day` },
                { k: "Everyone together", v: `${full(overview.legal.limits.perDayTotal)} questions a day` },
              ]}
            />
          ) : (
            <p className="adm-cell-sub">Not recording: run <code>0021_legal_ai.sql</code>.</p>
          )}
        </Card>
      </div>

      <Card title="Dashboards" caption="Where the rest of Akarat.ai is run">
        <div className="adm-links">
          {supabaseRef && <DashLink href={`https://supabase.com/dashboard/project/${supabaseRef}`} icon="database" title="Supabase" body="Database, accounts, storage and SQL" />}
          <DashLink href="https://vercel.com/dashboard" icon="layers" title="Vercel" body="Deployments and environment variables" />
          <DashLink href="https://console.anthropic.com/settings/billing" icon="dollar" title="Anthropic Console" body="Credit, invoices and usage for both assistants" />
          <DashLink href="/" icon="home" title="akarat.ai" body="The public website" />
        </div>
      </Card>
    </>
  );
}

function StateIcon({ state }: { state: State }) {
  const name: IconName = state === "ok" ? "circleCheck" : state === "missing" ? "alert" : "clock";
  return (
    <span className={cx("adm-check-icon", `is-${state}`)}>
      <Icon name={name} size={18} />
    </span>
  );
}

function DashLink({ href, icon, title, body }: { href: string; icon: IconName; title: string; body: string }) {
  return (
    <a className="adm-dash-link" href={href} target="_blank" rel="noreferrer">
      <span className="adm-dash-icon"><Icon name={icon} size={18} /></span>
      <span>
        <b>{title}</b>
        <span className="adm-cell-sub">{body}</span>
      </span>
      <Icon name="external" size={15} className="adm-dash-go" />
    </a>
  );
}
