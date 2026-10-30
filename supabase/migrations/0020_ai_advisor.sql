-- 0020_ai_advisor.sql
--
-- The AI property advisor (POST /api/ai/advisor): daily allowances, what each
-- day cost, and what was flagged.
--
--   1. ai_usage_daily: one row per caller per day (Amman time), plus a row
--      keyed 'global' for everyone together. Turns, tokens, web searches and
--      page reads. Callers are 'u:<user id>' or 'ip:<salted hash>': no raw IP
--      address is ever stored.
--   2. ai_flags: events worth a look (a reply withdrawn for reciting its
--      instructions, a link the advisor could not back up, a refusal). The
--      kind and the caller key only; never what anyone wrote.
--   3. ai_usage_take(): counts a turn against the caller's and the global
--      daily allowance, atomically, and says which one is spent.
--   4. ai_usage_record(): adds a finished turn's usage and flags.
--   5. admin_ai_overview(): the admin panel's figures.
--
-- Only the service role (the website's server) can touch any of it: RLS is on
-- and no policy grants anything to anon or authenticated.
--
-- Optional. Without it the advisor works, and its daily limits are counted in
-- each server instance instead, which is weaker. Safe to run more than once.

/* ── 1. Usage by day ─────────────────────────────────────────────────── */

create table if not exists public.ai_usage_daily (
  day           date    not null,
  key           text    not null check (char_length(key) between 1 and 80),
  turns         integer not null default 0,
  input_tokens  bigint  not null default 0,
  output_tokens bigint  not null default 0,
  cache_read_tokens  bigint not null default 0,
  cache_write_tokens bigint not null default 0,
  web_searches  integer not null default 0,
  web_fetches   integer not null default 0,
  flagged       integer not null default 0,
  primary key (day, key)
);

alter table public.ai_usage_daily enable row level security;
revoke all on public.ai_usage_daily from anon, authenticated;
grant all on public.ai_usage_daily to service_role;

/* ── 2. Flags ────────────────────────────────────────────────────────── */

create table if not exists public.ai_flags (
  id   bigint generated always as identity primary key,
  at   timestamptz not null default now(),
  key  text not null check (char_length(key) between 1 and 80),
  kind text not null check (kind ~ '^[a-z_]{1,40}$')
);

create index if not exists ai_flags_at on public.ai_flags (at desc);

alter table public.ai_flags enable row level security;
revoke all on public.ai_flags from anon, authenticated;
grant all on public.ai_flags to service_role;

/* ── 3. Taking a turn ────────────────────────────────────────────────── */

create or replace function public.ai_usage_take(p_key text, p_limit integer, p_global_limit integer)
returns text
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_day    date := (now() at time zone 'Asia/Amman')::date;
  v_global integer;
  v_mine   integer;
begin
  if p_key is null or p_key = 'global' or char_length(p_key) > 80 then
    raise exception 'bad key';
  end if;

  -- Everyone's allowance first: when the day's budget is spent, nobody's own
  -- counter moves.
  insert into ai_usage_daily (day, key, turns) values (v_day, 'global', 1)
  on conflict (day, key) do update set turns = ai_usage_daily.turns + 1
  returning turns into v_global;
  if v_global > p_global_limit then
    update ai_usage_daily set turns = turns - 1 where day = v_day and key = 'global';
    return 'global';
  end if;

  insert into ai_usage_daily (day, key, turns) values (v_day, p_key, 1)
  on conflict (day, key) do update set turns = ai_usage_daily.turns + 1
  returning turns into v_mine;
  if v_mine > p_limit then
    update ai_usage_daily set turns = turns - 1 where day = v_day and key in (p_key, 'global');
    return 'user';
  end if;

  -- Old days are kept for the admin panel's chart, then cleared.
  if random() < 0.01 then
    delete from ai_usage_daily where day < v_day - 120;
    delete from ai_flags where at < now() - interval '120 days';
  end if;

  return 'ok';
end;
$$;

revoke all on function public.ai_usage_take(text, integer, integer) from public, anon, authenticated;
grant execute on function public.ai_usage_take(text, integer, integer) to service_role;

/* ── 4. Recording a turn ─────────────────────────────────────────────── */

create or replace function public.ai_usage_record(
  p_key text,
  p_input bigint,
  p_output bigint,
  p_cache_read bigint,
  p_cache_write bigint,
  p_searches integer,
  p_fetches integer,
  p_flags text[]
) returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_day   date := (now() at time zone 'Asia/Amman')::date;
  -- Only well-formed kinds count, the same ones that are stored below.
  v_flags integer := coalesce((select count(*) from unnest(p_flags[1:10]) as f where f ~ '^[a-z_]{1,40}$'), 0);
begin
  if p_key is null or p_key = 'global' or char_length(p_key) > 80 then
    raise exception 'bad key';
  end if;

  insert into ai_usage_daily as u
    (day, key, input_tokens, output_tokens, cache_read_tokens, cache_write_tokens, web_searches, web_fetches, flagged)
  values
    (v_day, p_key, greatest(p_input, 0), greatest(p_output, 0), greatest(p_cache_read, 0), greatest(p_cache_write, 0),
     greatest(p_searches, 0), greatest(p_fetches, 0), least(v_flags, 1))
  on conflict (day, key) do update set
    input_tokens       = u.input_tokens + excluded.input_tokens,
    output_tokens      = u.output_tokens + excluded.output_tokens,
    cache_read_tokens  = u.cache_read_tokens + excluded.cache_read_tokens,
    cache_write_tokens = u.cache_write_tokens + excluded.cache_write_tokens,
    web_searches       = u.web_searches + excluded.web_searches,
    web_fetches        = u.web_fetches + excluded.web_fetches,
    flagged            = u.flagged + excluded.flagged;

  insert into ai_usage_daily as u
    (day, key, input_tokens, output_tokens, cache_read_tokens, cache_write_tokens, web_searches, web_fetches, flagged)
  values
    (v_day, 'global', greatest(p_input, 0), greatest(p_output, 0), greatest(p_cache_read, 0), greatest(p_cache_write, 0),
     greatest(p_searches, 0), greatest(p_fetches, 0), least(v_flags, 1))
  on conflict (day, key) do update set
    input_tokens       = u.input_tokens + excluded.input_tokens,
    output_tokens      = u.output_tokens + excluded.output_tokens,
    cache_read_tokens  = u.cache_read_tokens + excluded.cache_read_tokens,
    cache_write_tokens = u.cache_write_tokens + excluded.cache_write_tokens,
    web_searches       = u.web_searches + excluded.web_searches,
    web_fetches        = u.web_fetches + excluded.web_fetches,
    flagged            = u.flagged + excluded.flagged;

  if v_flags > 0 then
    insert into ai_flags (key, kind)
    select p_key, f from unnest(p_flags[1:10]) as f where f ~ '^[a-z_]{1,40}$';
  end if;
end;
$$;

revoke all on function public.ai_usage_record(text, bigint, bigint, bigint, bigint, integer, integer, text[]) from public, anon, authenticated;
grant execute on function public.ai_usage_record(text, bigint, bigint, bigint, bigint, integer, integer, text[]) to service_role;

/* ── 5. For the admin panel ──────────────────────────────────────────── */

create or replace function public.admin_ai_overview()
returns jsonb
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  with today as (select (now() at time zone 'Asia/Amman')::date as d)
  select jsonb_build_object(
    'today', (
      select jsonb_build_object(
        'turns',      coalesce(sum(turns) filter (where key = 'global'), 0),
        'people',     count(*) filter (where key <> 'global' and turns > 0),
        'input',      coalesce(sum(input_tokens) filter (where key = 'global'), 0),
        'output',     coalesce(sum(output_tokens) filter (where key = 'global'), 0),
        'cacheRead',  coalesce(sum(cache_read_tokens) filter (where key = 'global'), 0),
        'cacheWrite', coalesce(sum(cache_write_tokens) filter (where key = 'global'), 0),
        'searches',   coalesce(sum(web_searches) filter (where key = 'global'), 0),
        'fetches',    coalesce(sum(web_fetches) filter (where key = 'global'), 0),
        'flagged',    coalesce(sum(flagged) filter (where key = 'global'), 0))
      from ai_usage_daily, today where day = today.d),
    'days', coalesce((
      select jsonb_agg(jsonb_build_object(
        'day', day, 'turns', turns, 'input', input_tokens, 'output', output_tokens,
        'cacheRead', cache_read_tokens, 'cacheWrite', cache_write_tokens,
        'searches', web_searches, 'fetches', web_fetches, 'flagged', flagged) order by day)
      from ai_usage_daily, today
      where key = 'global' and day > today.d - 30), '[]'::jsonb),
    'flags', coalesce((
      select jsonb_agg(jsonb_build_object('kind', kind, 'count', n) order by n desc)
      from (select kind, count(*) as n from ai_flags where at > now() - interval '7 days' group by kind) f), '[]'::jsonb)
  );
$$;

revoke all on function public.admin_ai_overview() from public, anon, authenticated;
grant execute on function public.admin_ai_overview() to service_role;

notify pgrst, 'reload schema';
