"use client";

import Link from "next/link";
import { useRouter } from "next/navigation";
import { useEffect, type ReactNode } from "react";
import { PageLoading } from "./_components/AdminApp";
import { BarList, ColumnChart, LineChart, Sparkline, StackedBar, type BarRow, type Segment } from "./_components/charts";
import { useAdmin } from "./_components/context";
import { Icon, type IconName } from "./_components/icons";
import { Badge, ButtonLink, Card, Empty, Figure, LoadError, PageHeader, Segmented, StatTile, StatusBadge, cx } from "./_components/ui";
import { useStored } from "./_lib/api";
import { compact, full, plural, titleOf, usd } from "./_lib/format";
import { LISTING_STATUS, labelOf, type Tone } from "./_lib/labels";
import { change, column, foldTail, lastN, trend } from "./_lib/stats";
import type { AssistantUse, Day, Overview, Ranked } from "./_lib/types";

const RANGES = ["7", "14", "30"] as const;
type Range = (typeof RANGES)[number];

// Links to the old one-page panel's tabs (/admin#listings) still land.
const LEGACY: Record<string, string> = {
  listings: "/admin/listings",
  daily: "/admin/daily-rentals",
  bookings: "/admin/bookings",
  inquiries: "/admin/inquiries",
  users: "/admin/users",
  reports: "/admin/reports",
};

export default function OverviewPage() {
  const { overview, overviewError, refreshOverview } = useAdmin();
  const router = useRouter();
  const [range, setRange] = useStored<Range>("akarat-admin-range", "14", RANGES);

  useEffect(() => {
    const to = LEGACY[window.location.hash.slice(1)];
    if (to) router.replace(to);
  }, [router]);

  if (!overview) {
    if (!overviewError) return <PageLoading />;
    return (
      <>
        <PageHeader title="Overview" />
        <LoadError error={overviewError} onRetry={() => void refreshOverview()} />
      </>
    );
  }
  return <Dashboard o={overview} range={range} setRange={setRange} />;
}

function Dashboard({ o, range, setRange }: { o: Overview; range: Range; setRange: (r: Range) => void }) {
  const n = Number(range);
  const days = o.daily;
  const shown = lastN(days, n);
  const from = days.length - shown.length;
  const versus = n * 2 <= days.length ? `vs previous ${n} days` : undefined;
  const kpi = (field: keyof Day) => {
    const c = change(days, field, n);
    return { value: compact(c.current), trend: trend(c), spark: <Sparkline values={column(days, field)} from={from} /> };
  };
  const views = kpi("views");
  const inquiries = kpi("inquiries");
  const signups = kpi("signups");
  const listings = kpi("listings");
  const today = new Date().toLocaleDateString("en-GB", { weekday: "long", day: "numeric", month: "long", timeZone: "Asia/Amman" });

  return (
    <>
      <PageHeader
        eyebrow={today}
        title="Overview"
        subtitle="Everything happening on Akarat.ai, refreshed every 15 seconds. Days are Amman days."
      />

      <div className="adm-grid g-12">
        <LiveHero o={o} />
        <Attention o={o} />
      </div>

      <SectionBar title="Activity" caption={`The last ${n} days${versus ? `, compared with the ${n} before` : ""}`}>
        <Segmented
          label="Period"
          value={range}
          onChange={setRange}
          options={[
            { value: "7", label: "7 days" },
            { value: "14", label: "14 days" },
            { value: "30", label: "30 days" },
          ]}
        />
      </SectionBar>

      <div className="adm-grid g-4">
        <StatTile label="Listing views" icon="eye" tone="good" {...views} trendNote={versus} note={`${compact(o.views.total)} all time`} />
        <StatTile label="Inquiries" icon="inbox" tone="info" {...inquiries} trendNote={versus} note={`${compact(o.inquiries.total)} all time`} href="/admin/inquiries" />
        <StatTile label="New accounts" icon="users" tone="gold" {...signups} trendNote={versus} note={`${compact(o.users.total)} accounts in all`} href="/admin/users" />
        <StatTile label="New listings" icon="building" tone="neutral" {...listings} trendNote={versus} note={`${compact(o.listings.total)} listings in all`} href="/admin/listings" />
      </div>

      <div className="adm-grid g-1">
        <Card title="Traffic" caption="Listing views, and the browsers or app installs that opened at least one listing, per day">
          <LineChart
            data={shown}
            label="Listing views and viewers per day"
            height={280}
            series={[
              { key: "views", label: "Listing views", color: "var(--c1)" },
              { key: "viewers", label: "Viewers", color: "var(--c2)" },
            ]}
          />
        </Card>
      </div>

      <div className="adm-grid g-2">
        <Card
          title="Inquiries"
          caption="Messages sent to owners, per day"
          actions={<ButtonLink href="/admin/inquiries" size="sm" variant="ghost" iconEnd="arrowRight">Open</ButtonLink>}
        >
          <ColumnChart data={shown} field="inquiries" name="Inquiries" label="Inquiries per day" />
        </Card>
        <Card title="Growth" caption="New accounts and new listings, per day">
          <LineChart
            data={shown}
            label="New accounts and new listings per day"
            height={220}
            series={[
              { key: "signups", label: "New accounts", color: "var(--c1)" },
              { key: "listings", label: "New listings", color: "var(--c2)" },
            ]}
          />
        </Card>
      </div>

      <SectionBar title="Marketplace" caption="Every listing as it stands now" />
      <div className="adm-grid g-3">
        <ListingsCard o={o} />
        <MixCard o={o} />
        <DailyCard o={o} />
      </div>

      <SectionBar title="Top listings" caption="The last 30 days" />
      <div className="adm-grid g-2">
        <Card title="Most viewed" icon="eye">
          <BarList rows={ranked(o.topViewed)} empty="No listing views in the last 30 days." />
        </Card>
        <Card title="Most inquired" icon="inbox">
          <BarList rows={ranked(o.topInquired)} empty="No inquiries in the last 30 days." />
        </Card>
      </div>

      <SectionBar title="AI assistants" caption="Today and the last 30 days" />
      <div className="adm-grid g-2">
        <AssistantCard
          title="Property AI"
          icon="sparkles"
          href="/admin/property-ai"
          use={o.advisor}
          setup={<>Run <code>supabase/migrations/0020_ai_advisor.sql</code> to record the advisor&apos;s use.</>}
        />
        <AssistantCard
          title="Ask a Lawyer"
          icon="scale"
          href="/admin/ask-a-lawyer"
          use={o.legal}
          badge={o.legal ? (o.legal.access === "public" ? <Badge tone="good" dot>Open to everyone</Badge> : <Badge tone="warn" dot>Reviewers only</Badge>) : null}
          setup={<>Run <code>supabase/migrations/0021_legal_ai.sql</code> to record Ask a Lawyer&apos;s use.</>}
        />
      </div>
    </>
  );
}

function SectionBar({ title, caption, children }: { title: string; caption?: string; children?: ReactNode }) {
  return (
    <div className="adm-section-bar">
      <div>
        <h2>{title}</h2>
        {caption && <p>{caption}</p>}
      </div>
      {children}
    </div>
  );
}

function LiveHero({ o }: { o: Overview }) {
  const platforms: Segment[] = [
    { key: "web", label: "Website", n: o.live.web, color: "var(--c1)" },
    { key: "android", label: "Android", n: o.live.android, color: "var(--c2)" },
    { key: "ios", label: "iPhone", n: o.live.ios, color: "var(--c3)" },
  ];
  return (
    <section className="adm-card adm-hero span-8" aria-label="Activity right now">
      <div className="adm-hero-col">
        <div>
          <div className="adm-hero-eyebrow">
            <span className="adm-pulse" aria-hidden="true" /> Live now
          </div>
          <div className="adm-hero-number">{full(o.live.total)}</div>
          <p className="adm-hero-sub">
            {o.live.total === 1 ? "browser or app" : "browsers and apps"} open on Akarat.ai in the last 2 minutes,{" "}
            {full(o.live.signedIn)} signed in
          </p>
        </div>
        <div>
          <div className="adm-hero-label">Today so far</div>
          <div className="adm-hero-figures">
            <Figure label="Listing views" value={compact(o.views.today)} />
            <Figure label="Inquiries" value={compact(o.inquiries.today)} />
            <Figure label="AI questions" value={compact((o.advisor?.today.turns ?? 0) + (o.legal?.today.turns ?? 0))} />
          </div>
        </div>
      </div>
      <div className="adm-hero-col">
        <div>
          <div className="adm-hero-label">Where they are</div>
          <StackedBar segments={platforms} label="Online now, by platform" />
        </div>
        <div>
          <div className="adm-hero-label">Browsers and apps active</div>
          <div className="adm-hero-figures">
            <Figure label="Today" value={compact(o.active.today)} />
            <Figure label="Last 7 days" value={compact(o.active.week)} />
            <Figure label="Last 30 days" value={compact(o.active.month)} />
          </div>
        </div>
      </div>
    </section>
  );
}

type Todo = { key: string; n: number; label: string; href: string; tone: Tone; icon: IconName };

function Attention({ o }: { o: Overview }) {
  const flagged = [...(o.advisor?.flags ?? []), ...(o.legal?.flags ?? [])].reduce((a, f) => a + f.count, 0);
  const todos = (
    [
      { key: "reports", n: o.openReports, label: "Reported listings to decide on", href: "/admin/reports", tone: "bad", icon: "flag" },
      { key: "daily", n: o.dailyRentals?.review.pending ?? 0, label: "Daily rentals waiting for review", href: "/admin/daily-rentals", tone: "warn", icon: "bed" },
      { key: "changed", n: o.dailyRentals?.review.changed ?? 0, label: "Approved rentals edited since", href: "/admin/daily-rentals?review=changed", tone: "warn", icon: "bed" },
      { key: "pending", n: o.listings.byStatus.pending ?? 0, label: "Listings pending review", href: "/admin/listings?status=pending", tone: "warn", icon: "building" },
      { key: "stale", n: o.legal?.library.stale ?? 0, label: "Legal sources due for re-checking", href: "/admin/ask-a-lawyer", tone: "warn", icon: "scale" },
      { key: "flags", n: flagged, label: "AI answers flagged this week", href: o.advisor?.flags.length ? "/admin/property-ai" : "/admin/ask-a-lawyer", tone: "info", icon: "sparkles" },
      { key: "inquiries", n: o.inquiries.new, label: "Inquiries still marked new", href: "/admin/inquiries?status=new", tone: "info", icon: "inbox" },
    ] satisfies Todo[]
  ).filter(t => t.n > 0);

  return (
    <Card title="Needs attention" caption="What is waiting on an admin" className="adm-attention span-4">
      {todos.length === 0 ? (
        <Empty small icon="circleCheck" title="All clear" body="Nothing is waiting on you right now." />
      ) : (
        <ul className="adm-todo">
          {todos.map(t => (
            <li key={t.key}>
              <Link href={t.href} className="adm-todo-row">
                <span className={cx("adm-todo-icon", `is-${t.tone}`)}><Icon name={t.icon} size={16} /></span>
                <span className="adm-todo-label">{t.label}</span>
                <b className="adm-todo-n">{compact(t.n)}</b>
                <Icon name="chevronRight" size={16} className="adm-todo-go" />
              </Link>
            </li>
          ))}
        </ul>
      )}
    </Card>
  );
}

function ListingsCard({ o }: { o: Overview }) {
  const rows: BarRow[] = Object.entries(o.listings.byStatus)
    .sort((a, b) => b[1] - a[1])
    .map(([s, count]) => ({ key: s, label: labelOf(LISTING_STATUS, s).label, n: count, href: `/admin/listings?status=${s}` }));
  return (
    <Card
      title="Listings by status"
      caption={`${full(o.listings.total)} in all · ${full(o.listings.week)} new this week`}
      actions={<ButtonLink href="/admin/listings" size="sm" variant="ghost" iconEnd="arrowRight">All</ButtonLink>}
    >
      <BarList rows={rows} empty="No listings yet." />
    </Card>
  );
}

function MixCard({ o }: { o: Overview }) {
  const deals = o.byDeal;
  const cities = foldTail(o.byCity, 5, count => ({ city: "Other cities", n: count }));
  return (
    <Card title="Listing mix" caption={`${full(o.users.owners)} owners have listed`}>
      {deals && (
        <div className="adm-block">
          <StackedBar
            label="Listings by deal"
            segments={[
              { key: "sale", label: "For sale", n: deals.sale ?? 0, color: "var(--c1)" },
              { key: "rent", label: "For rent", n: deals.rent ?? 0, color: "var(--c2)" },
              { key: "daily", label: "Daily rental", n: deals.daily ?? 0, color: "var(--c3)" },
            ]}
          />
        </div>
      )}
      <div className="adm-sub-title">By city</div>
      <BarList rows={cities.map(c => ({ key: c.city, label: c.city, n: c.n }))} empty="No listings yet." />
    </Card>
  );
}

function DailyCard({ o }: { o: Overview }) {
  const d = o.dailyRentals;
  if (!d) {
    return (
      <Card title="Daily rentals" icon="bed">
        <Empty small icon="bed" title="Not set up yet" body={<>Run <code>supabase/migrations/0019_daily_rentals.sql</code> to turn daily rentals on.</>} />
      </Card>
    );
  }
  const closed = Math.max(0, d.requests.total - d.requests.pending - d.requests.approved - d.requests.confirmed);
  return (
    <Card
      title="Daily rentals"
      caption={`${full(d.requests.total)} booking requests · ${full(d.requests.week)} this week`}
      actions={<ButtonLink href="/admin/daily-rentals" size="sm" variant="ghost" iconEnd="arrowRight">Review</ButtonLink>}
    >
      <div className="adm-figures">
        <Figure label="Live" value={compact(d.review.live)} sub="approved, public" />
        <Figure label="To review" value={compact(d.review.pending)} sub="hidden until approved" />
        <Figure label="Nights booked" value={compact(d.requests.nightsConfirmed)} sub="confirmed stays" />
      </div>
      <div className="adm-sub-title">Booking requests now</div>
      <StackedBar
        label="Booking requests by status"
        segments={[
          { key: "confirmed", label: "Confirmed", n: d.requests.confirmed, color: "var(--c1)" },
          { key: "approved", label: "Approved", n: d.requests.approved, color: "var(--c2)" },
          { key: "pending", label: "Waiting", n: d.requests.pending, color: "var(--c3)" },
          { key: "closed", label: "Closed", n: closed, color: "var(--c-muted)" },
        ]}
      />
    </Card>
  );
}

const ranked = (rows: Ranked[]): BarRow[] =>
  rows.map(r => ({
    key: r.id,
    label: titleOf(r),
    title: titleOf(r),
    n: r.n,
    href: `/admin/listings?q=${r.id}`,
    extra: r.status !== "active" ? <StatusBadge map={LISTING_STATUS} value={r.status} /> : undefined,
  }));

function AssistantCard({ title, icon, href, use, setup, badge }: {
  title: string; icon: IconName; href: string; use: AssistantUse | null; setup: ReactNode; badge?: ReactNode;
}) {
  if (!use) {
    return (
      <Card title={title} icon={icon}>
        <Empty small icon={icon} title="Not set up yet" body={setup} />
      </Card>
    );
  }
  const today = use.measured ? use.measured.today : use.today.cost;
  const month = use.measured ? use.measured.month : use.month.cost;
  return (
    <Card
      title={title}
      icon={icon}
      caption={<>Default model <code>{use.model}</code></>}
      actions={
        <>
          {badge}
          <ButtonLink href={href} size="sm" variant="ghost" iconEnd="arrowRight">Details</ButtonLink>
        </>
      }
    >
      <div className="adm-figures">
        <Figure label="Questions today" value={compact(use.today.turns)} sub={plural(use.today.people, "person", "people")} />
        <Figure label="Last 30 days" value={compact(use.month.turns)} sub="questions" />
        <Figure label={use.measured ? "Cost today" : "Cost today (est.)"} value={usd(today)} sub={`${usd(month)} over 30 days`} />
      </div>
      <ColumnChart data={use.days} field="turns" name="Questions" label={`${title} questions per day`} height={150} />
    </Card>
  );
}
