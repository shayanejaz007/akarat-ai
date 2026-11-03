"use client";

import { PageLoading } from "../_components/AdminApp";
import { BarList, ColumnChart, Meter, Sparkline, StackedBar } from "../_components/charts";
import { useAdmin } from "../_components/context";
import { Callout, Card, Empty, KV, LoadError, PageHeader, StatTile } from "../_components/ui";
import { compact, full, plural, usd, usdTick } from "../_lib/format";
import { ADVISOR_FLAG } from "../_lib/labels";
import type { Overview } from "../_lib/types";
import { mixSegments } from "../_lib/mix";

/* The AI advisor (POST /api/ai/advisor): use, cost, limits and flags, from
   the overview (0020_ai_advisor.sql, 0022_ai_cost.sql). */

export default function PropertyAiPage() {
  const { overview, overviewError, refreshOverview } = useAdmin();
  if (!overview) return overviewError ? <LoadError error={overviewError} onRetry={() => void refreshOverview()} /> : <PageLoading />;
  const ai = overview.advisor;
  return (
    <>
      <PageHeader
        eyebrow="AI assistants"
        title="Property AI"
        subtitle="The conversational property advisor on the website and in the app: how much it is used, what it costs, and what it flagged for a look."
      />
      {ai ? (
        <Advisor ai={ai} />
      ) : (
        <Card>
          <Empty
            icon="sparkles"
            title="Not recording yet"
            body={<>Run <code>supabase/migrations/0020_ai_advisor.sql</code> in Supabase to record the advisor&apos;s use and cost.</>}
          />
        </Card>
      )}
    </>
  );
}

function Advisor({ ai }: { ai: NonNullable<Overview["advisor"]> }) {
  const flagged = ai.flags.reduce((a, f) => a + f.count, 0);
  const today = ai.measured ? ai.measured.today : ai.today.cost;
  const month = ai.measured ? ai.measured.month : ai.month.cost;
  const cap = ai.limits.perDayTotal;
  const used = cap ? ai.today.turns / cap : 0;

  return (
    <>
      <div className="adm-grid g-4">
        <StatTile
          label="Questions today"
          icon="message"
          tone="good"
          value={compact(ai.today.turns)}
          note={`${plural(ai.today.people, "person", "people")} · ${compact(ai.month.turns)} in 30 days`}
          spark={<Sparkline values={ai.days.map(d => d.turns)} from={ai.days.length - 7} />}
        />
        <StatTile label={ai.measured ? "Cost today" : "Cost today (estimate)"} icon="dollar" tone="gold" value={usd(today)} note={`${usd(month)} over the last 30 days`} />
        <StatTile label="Web research today" icon="globe" tone="info" value={compact(ai.today.searches)} note={`searches · ${full(ai.today.fetches)} pages read`} />
        <StatTile label="Flagged, last 7 days" icon="flag" tone={flagged ? "warn" : "neutral"} value={compact(flagged)} note={flagged ? "listed below" : "nothing flagged"} />
      </div>

      <div className="adm-grid g-12">
        <Card className="span-8" title="Questions per day" caption="The last 30 days">
          <ColumnChart data={ai.days} field="turns" name="Questions" label="Property AI questions per day" height={240} />
        </Card>
        <Card className="span-4" title="Today's limit" caption="Questions answered so far against the daily cap">
          <div className="adm-big-figure">
            {full(ai.today.turns)} <small>of {full(cap)}</small>
          </div>
          <Meter value={ai.today.turns} max={cap} label="Questions today against the daily cap" tone={used >= 0.9 ? "bad" : used >= 0.7 ? "warn" : "accent"} />
          <KV
            items={[
              { k: "Each signed-in person", v: `${full(ai.limits.perDaySignedIn)} a day` },
              { k: "Each visitor not signed in", v: `${full(ai.limits.perDayAnonymous)} a day` },
              { k: "Everyone together", v: `${full(cap)} a day` },
            ]}
          />
        </Card>
      </div>

      <div className="adm-grid g-12">
        <Card className="span-8" title="Cost per day" caption="Estimated from token counts at list prices, in US dollars. The Anthropic Console has the invoice.">
          <ColumnChart
            data={ai.days.map(d => ({ day: d.day, cost: d.cost ?? 0 }))}
            field="cost"
            name="Cost"
            label="Property AI estimated cost per day"
            format={usdTick}
            valueFormat={usd}
            integer={false}
            height={220}
          />
        </Card>
        <Card className="span-4" title="Models used" caption="Answers by model and effort, last 30 days">
          {ai.measured?.mix.length ? (
            <StackedBar label="Answers by model" segments={mixSegments(ai.measured.mix)} />
          ) : (
            <Empty small icon="layers" title="Not recorded yet" body={<>Run <code>0022_ai_cost.sql</code> to record which model answered.</>} />
          )}
          <p className="adm-hint">Default model: <code>{ai.model}</code></p>
        </Card>
      </div>

      <Card title="Flagged events" caption="The last 7 days. A flag marks an answer worth a look; it never holds anyone's words.">
        <BarList rows={ai.flags.map(f => ({ key: f.kind, label: ADVISOR_FLAG[f.kind] ?? f.kind, n: f.count }))} empty="Nothing flagged in the last 7 days." />
      </Card>

      <Callout tone="info" title="When the advisor stops answering">
        If every question gets “unavailable”, check the Anthropic account&apos;s credit first:{" "}
        <a href="https://console.anthropic.com/settings/billing" target="_blank" rel="noreferrer">Anthropic Console → Billing</a>.
      </Callout>
    </>
  );
}
