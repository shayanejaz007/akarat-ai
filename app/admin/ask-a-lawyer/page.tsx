"use client";

import { PageLoading } from "../_components/AdminApp";
import { BarList, ColumnChart, Meter, Sparkline, StackedBar } from "../_components/charts";
import { useAdmin } from "../_components/context";
import { Badge, Callout, Card, Empty, Figure, KV, LoadError, PageHeader, StatTile, StatusBadge } from "../_components/ui";
import { ago, compact, full, pct, plainAnswer, plural, usd, usdTick } from "../_lib/format";
import { FEEDBACK, LEGAL_FLAG, labelOf } from "../_lib/labels";
import { mixSegments } from "../_lib/mix";
import type { LegalFeedback, Overview } from "../_lib/types";

/* Ask a Lawyer (POST /api/legal/ask): use and cost, whether answers stand on
   what was retrieved, how much of the legal library is verified and fresh,
   and the reports from the launch review (0021_legal_ai.sql). Report notes
   and reviewers' snapshots are opened by the server for this panel only. */

export default function AskALawyerPage() {
  const { overview, overviewError, refreshOverview } = useAdmin();
  if (!overview) return overviewError ? <LoadError error={overviewError} onRetry={() => void refreshOverview()} /> : <PageLoading />;
  const law = overview.legal;
  return (
    <>
      <PageHeader
        eyebrow="AI assistants"
        title="Ask a Lawyer"
        subtitle="Legal answers grounded in Jordanian law: use and cost, how well answers stand on their sources, the state of the legal library, and what reviewers reported."
      />
      {law ? (
        <Lawyer law={law} />
      ) : (
        <Card>
          <Empty icon="scale" title="Not recording yet" body={<>Run <code>supabase/migrations/0021_legal_ai.sql</code> in Supabase to turn Ask a Lawyer&apos;s records on.</>} />
        </Card>
      )}
    </>
  );
}

function Lawyer({ law }: { law: NonNullable<Overview["legal"]> }) {
  const lib = law.library;
  const a = law.answers;
  const flagged = law.flags.reduce((n, f) => n + f.count, 0);
  const today = law.measured ? law.measured.today : law.today.cost;
  const month = law.measured ? law.measured.month : law.month.cost;
  const unverifiedShare = a.total ? a.withUnverified / a.total : 0;
  const reports = law.feedback.counts.reduce((n, f) => n + f.count, 0);

  return (
    <>
      {law.access === "public" ? (
        <Callout tone="good" title="Open to every signed-in account">Anyone signed in on the website or the app can ask.</Callout>
      ) : (
        <Callout tone="warn" title="Reviewers only, until launch">
          Only the {plural(law.reviewers, "account")} listed in <code>LEGAL_REVIEWERS</code> can ask; everyone else is told it is
          being reviewed. When the review is done, set <code>LEGAL_ACCESS=public</code> in Vercel and redeploy.
        </Callout>
      )}

      <div className="adm-grid g-4">
        <StatTile
          label="Questions today"
          icon="message"
          tone="good"
          value={compact(law.today.turns)}
          note={`${plural(law.today.people, "person", "people")} · ${compact(law.month.turns)} in 30 days`}
          spark={<Sparkline values={law.days.map(d => d.turns)} from={law.days.length - 7} />}
        />
        <StatTile label={law.measured ? "Cost today" : "Cost today (estimate)"} icon="dollar" tone="gold" value={usd(today)} note={`${usd(month)} over the last 30 days`} />
        <StatTile
          label="Answers with an unverified reference"
          icon="alert"
          tone={unverifiedShare > 0.1 ? "bad" : unverifiedShare > 0 ? "warn" : "good"}
          value={pct(a.withUnverified, a.total)}
          note={`${full(a.withUnverified)} of ${full(a.total)} answers, last 30 days`}
        />
        <StatTile
          label="Verified library sources"
          icon="book"
          tone="info"
          value={compact(lib.verified)}
          note={lib.stale ? `${full(lib.stale)} due for re-checking` : "all checked within 180 days"}
        />
      </div>

      <div className="adm-grid g-12">
        <Card className="span-8" title="Questions per day" caption="The last 30 days">
          <ColumnChart data={law.days} field="turns" name="Questions" label="Ask a Lawyer questions per day" height={240} />
        </Card>
        <Card className="span-4" title="Answer quality" caption="Answers in the last 30 days">
          <div className="adm-meter-block">
            <div className="adm-meter-head"><span>Cite at least one source</span><b>{pct(a.withCitations, a.total)}</b></div>
            <Meter value={a.withCitations} max={a.total} label="Answers that cite a source" />
          </div>
          <div className="adm-meter-block">
            <div className="adm-meter-head"><span>Name a reference nothing supported</span><b>{pct(a.withUnverified, a.total)}</b></div>
            <Meter value={a.withUnverified} max={a.total} label="Answers with an unverified reference" tone={unverifiedShare > 0.1 ? "bad" : "warn"} />
          </div>
          <KV
            items={[
              { k: "Answers", v: full(a.total) },
              { k: "Citations given", v: full(a.cited) },
              { k: "Unverified references", v: full(a.unverified) },
            ]}
          />
        </Card>
      </div>

      <div className="adm-grid g-12">
        <Card className="span-8" title="Cost per day" caption="Estimated from token counts at list prices, in US dollars. The Anthropic Console has the invoice.">
          <ColumnChart
            data={law.days.map(d => ({ day: d.day, cost: d.cost ?? 0 }))}
            field="cost"
            name="Cost"
            label="Ask a Lawyer estimated cost per day"
            format={usdTick}
            valueFormat={usd}
            integer={false}
            height={220}
          />
        </Card>
        <Card className="span-4" title="The legal library" caption="Only verified sources are ever searched">
          <StackedBar
            label="Verified sources by kind"
            segments={[
              { key: "legislation", label: "Legislation", n: lib.legislation, color: "var(--c1)" },
              { key: "judgments", label: "Judgments", n: lib.judgments, color: "var(--c2)" },
              { key: "commentary", label: "Commentary", n: lib.commentary, color: "var(--c3)" },
            ]}
          />
          <div className="adm-meter-block">
            <div className="adm-meter-head"><span>Verified</span><b>{full(lib.verified)} of {full(lib.sources)}</b></div>
            <Meter value={lib.verified} max={lib.sources} label="Sources verified" />
          </div>
          <div className="adm-meter-block">
            <div className="adm-meter-head"><span>Passages searchable by meaning</span><b>{pct(lib.embedded, lib.passages)}</b></div>
            <Meter value={lib.embedded} max={lib.passages} label="Passages with embeddings" />
          </div>
          <KV
            items={[
              { k: "Articles and passages", v: full(lib.passages) },
              { k: "Marked repealed", v: full(lib.repealed) },
              { k: "Due for re-checking", v: lib.stale ? <Badge tone="warn">{full(lib.stale)}</Badge> : "None" },
              { k: "Oldest check", v: lib.oldestCheck ?? "—" },
            ]}
          />
        </Card>
      </div>

      <div className="adm-grid g-3">
        <Card title="Flagged events" caption="The last 7 days">
          <BarList rows={law.flags.map(f => ({ key: f.kind, label: LEGAL_FLAG[f.kind] ?? f.kind, n: f.count }))} empty="Nothing flagged in the last 7 days." />
          {flagged > 0 && <p className="adm-hint">A flag marks an answer worth a look; it never holds anyone&apos;s words.</p>}
        </Card>
        <Card title="Reports on answers" caption={`The last 30 days · ${full(reports)} in all`}>
          <BarList rows={law.feedback.counts.map(f => ({ key: f.kind, label: labelOf(FEEDBACK, f.kind).label, n: f.count }))} empty="No reports yet." />
        </Card>
        <Card title="Models used" caption="Answers by model and effort, last 30 days">
          {law.measured?.mix.length ? (
            <StackedBar label="Answers by model" segments={mixSegments(law.measured.mix)} />
          ) : (
            <Empty small icon="layers" title="Not recorded yet" body={<>Run <code>0022_ai_cost.sql</code> to record which model answered.</>} />
          )}
          <div className="adm-figures is-2">
            <Figure label="Daily cap, each person" value={full(law.limits.perDay)} />
            <Figure label="Daily cap, everyone" value={full(law.limits.perDayTotal)} />
          </div>
          <p className="adm-hint">Default model: <code>{law.model}</code></p>
        </Card>
      </div>

      <Card title="Latest reports" caption="Newest first. A reviewer's report carries the question and the answer, with identifiers masked.">
        {law.feedback.recent.length === 0 ? (
          <Empty small icon="message" title="No reports yet" body="Reports sent from an answer's “Report a problem” appear here." />
        ) : (
          <ul className="adm-reports">
            {law.feedback.recent.map(r => <Report key={r.id} r={r} />)}
          </ul>
        )}
      </Card>
    </>
  );
}

function Report({ r }: { r: LegalFeedback }) {
  return (
    <li className="adm-report">
      <div className="adm-report-head">
        <StatusBadge map={FEEDBACK} value={r.kind} />
        {r.reviewer && <Badge tone="gold" icon="shield">Reviewer</Badge>}
        <span className="adm-cell-sub">{ago(r.at)}</span>
      </div>
      {r.note ? <p className="adm-report-note" dir="auto">{r.note}</p> : !r.snapshot && <p className="adm-cell-sub">No note.</p>}
      {r.snapshot && (
        <details className="adm-disclosure">
          <summary>The question and the answer</summary>
          <div className="adm-disclosure-body">
            <p dir="auto"><b>Question:</b> {r.snapshot.question}</p>
            <div className="adm-answer" dir="auto">{plainAnswer(r.snapshot.answer)}</div>
            {r.snapshot.unverified.length > 0 && (
              <p><b>Not verified:</b> {r.snapshot.unverified.join(", ")}</p>
            )}
            {r.snapshot.sources.length > 0 && (
              <ol className="adm-sources">
                {r.snapshot.sources.map((s, i) => (
                  <li key={i} dir="auto">
                    {/^https?:\/\//i.test(s.url) ? <a href={s.url} target="_blank" rel="noreferrer">{s.title}</a> : s.title}{" "}
                    <span className="adm-cell-sub">({s.kind}{s.status ? `, ${s.status}` : ""})</span>
                  </li>
                ))}
              </ol>
            )}
          </div>
        </details>
      )}
    </li>
  );
}
