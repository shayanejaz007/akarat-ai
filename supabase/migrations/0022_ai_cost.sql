-- 0022_ai_cost.sql
--
-- What each answer cost, and which model answered it, for both assistants.
--
-- Until now the admin panel estimated cost from token totals at one model's
-- prices. The assistants now route by question (Claude Sonnet 5.5 at low or
-- high effort for property questions, medium or high for legal ones, and an
-- optional stronger model for defined legal cases), and follow-up
-- suggestions run on a small model, so one price no longer fits. Each answer
-- now records its own estimated cost, in millionths of a US dollar, and the
-- model and effort it used.
--
--   1. ai_usage_daily, legal_usage_daily: cost_micros and model_mix
--      ({"claude-sonnet-5-5|low": 41, ...}) per caller per day.
--   2. ai_usage_record(), legal_usage_record(): two more arguments, both with
--      defaults, so code that does not send them keeps working.
--   3. legal_audit: the route and cost of each answer.
--   4. ai_cost_summary(): today's and the month's measured cost and model
--      mix for either table, for the admin panel (service role only).
--
-- Needs 0020 and 0021. Safe to run more than once.

alter table public.ai_usage_daily add column if not exists cost_micros bigint not null default 0;
alter table public.ai_usage_daily add column if not exists model_mix jsonb not null default '{}'::jsonb;
alter table public.legal_usage_daily add column if not exists cost_micros bigint not null default 0;
alter table public.legal_usage_daily add column if not exists model_mix jsonb not null default '{}'::jsonb;
alter table public.legal_audit add column if not exists route text check (char_length(route) <= 80);
alter table public.legal_audit add column if not exists cost_micros bigint;

-- One counter in a {"model|effort": n} object.
create or replace function public.ai_mix_add(p_mix jsonb, p_route text)
returns jsonb
language sql
immutable
as $$
  select case
    when p_route is null or p_route !~ '^[a-z0-9.|_-]{1,80}$' then coalesce(p_mix, '{}'::jsonb)
    else jsonb_set(coalesce(p_mix, '{}'::jsonb), array[p_route], to_jsonb(coalesce((p_mix ->> p_route)::bigint, 0) + 1))
  end
$$;

/* ── Recording, with cost and route ──────────────────────────────────── */

drop function if exists public.ai_usage_record(text, bigint, bigint, bigint, bigint, integer, integer, text[]);
drop function if exists public.legal_usage_record(text, bigint, bigint, bigint, bigint, integer, integer, text[]);

create or replace function public.ai_usage_record(
  p_key text,
  p_input bigint,
  p_output bigint,
  p_cache_read bigint,
  p_cache_write bigint,
  p_searches integer,
  p_fetches integer,
  p_flags text[],
  p_cost_micros bigint default 0,
  p_route text default null
) returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_day   date := (now() at time zone 'Asia/Amman')::date;
  v_flags integer := coalesce((select count(*) from unnest(p_flags[1:10]) as f where f ~ '^[a-z_]{1,40}$'), 0);
  v_key   text;
begin
  if p_key is null or p_key = 'global' or char_length(p_key) > 80 then
    raise exception 'bad key';
  end if;
  foreach v_key in array array[p_key, 'global'] loop
    insert into ai_usage_daily as u
      (day, key, input_tokens, output_tokens, cache_read_tokens, cache_write_tokens, web_searches, web_fetches, flagged, cost_micros, model_mix)
    values
      (v_day, v_key, greatest(p_input, 0), greatest(p_output, 0), greatest(p_cache_read, 0), greatest(p_cache_write, 0),
       greatest(p_searches, 0), greatest(p_fetches, 0), least(v_flags, 1), greatest(coalesce(p_cost_micros, 0), 0), ai_mix_add('{}'::jsonb, p_route))
    on conflict (day, key) do update set
      input_tokens       = u.input_tokens + excluded.input_tokens,
      output_tokens      = u.output_tokens + excluded.output_tokens,
      cache_read_tokens  = u.cache_read_tokens + excluded.cache_read_tokens,
      cache_write_tokens = u.cache_write_tokens + excluded.cache_write_tokens,
      web_searches       = u.web_searches + excluded.web_searches,
      web_fetches        = u.web_fetches + excluded.web_fetches,
      flagged            = u.flagged + excluded.flagged,
      cost_micros        = u.cost_micros + excluded.cost_micros,
      model_mix          = ai_mix_add(u.model_mix, p_route);
  end loop;
  if v_flags > 0 then
    insert into ai_flags (key, kind)
    select p_key, f from unnest(p_flags[1:10]) as f where f ~ '^[a-z_]{1,40}$';
  end if;
end;
$$;

create or replace function public.legal_usage_record(
  p_key text,
  p_input bigint,
  p_output bigint,
  p_cache_read bigint,
  p_cache_write bigint,
  p_searches integer,
  p_fetches integer,
  p_flags text[],
  p_cost_micros bigint default 0,
  p_route text default null
) returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_day   date := (now() at time zone 'Asia/Amman')::date;
  v_flags integer := coalesce((select count(*) from unnest(p_flags[1:10]) as f where f ~ '^[a-z_]{1,40}$'), 0);
  v_key   text;
begin
  if p_key is null or p_key = 'global' or char_length(p_key) > 80 then
    raise exception 'bad key';
  end if;
  foreach v_key in array array[p_key, 'global'] loop
    insert into legal_usage_daily as u
      (day, key, input_tokens, output_tokens, cache_read_tokens, cache_write_tokens, web_searches, web_fetches, flagged, cost_micros, model_mix)
    values
      (v_day, v_key, greatest(p_input, 0), greatest(p_output, 0), greatest(p_cache_read, 0), greatest(p_cache_write, 0),
       greatest(p_searches, 0), greatest(p_fetches, 0), least(v_flags, 1), greatest(coalesce(p_cost_micros, 0), 0), ai_mix_add('{}'::jsonb, p_route))
    on conflict (day, key) do update set
      input_tokens       = u.input_tokens + excluded.input_tokens,
      output_tokens      = u.output_tokens + excluded.output_tokens,
      cache_read_tokens  = u.cache_read_tokens + excluded.cache_read_tokens,
      cache_write_tokens = u.cache_write_tokens + excluded.cache_write_tokens,
      web_searches       = u.web_searches + excluded.web_searches,
      web_fetches        = u.web_fetches + excluded.web_fetches,
      flagged            = u.flagged + excluded.flagged,
      cost_micros        = u.cost_micros + excluded.cost_micros,
      model_mix          = ai_mix_add(u.model_mix, p_route);
  end loop;
  if v_flags > 0 then
    insert into legal_flags (key, kind)
    select p_key, f from unnest(p_flags[1:10]) as f where f ~ '^[a-z_]{1,40}$';
  end if;
end;
$$;

revoke all on function public.ai_mix_add(jsonb, text) from public, anon, authenticated;
revoke all on function public.ai_usage_record(text, bigint, bigint, bigint, bigint, integer, integer, text[], bigint, text) from public, anon, authenticated;
revoke all on function public.legal_usage_record(text, bigint, bigint, bigint, bigint, integer, integer, text[], bigint, text) from public, anon, authenticated;
grant execute on function public.ai_mix_add(jsonb, text) to service_role;
grant execute on function public.ai_usage_record(text, bigint, bigint, bigint, bigint, integer, integer, text[], bigint, text) to service_role;
grant execute on function public.legal_usage_record(text, bigint, bigint, bigint, bigint, integer, integer, text[], bigint, text) to service_role;

/* ── For the admin panel: measured cost and the model mix ────────────── */

-- Today's and the last 30 days' cost and model mix, from the global rows.
create or replace function public.ai_cost_summary(p_table text)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_today date := (now() at time zone 'Asia/Amman')::date;
  v_out   jsonb;
begin
  if p_table not in ('ai_usage_daily', 'legal_usage_daily') then
    raise exception 'bad table';
  end if;
  execute format($q$
    select jsonb_build_object(
      'todayMicros', coalesce((select cost_micros from %1$I where day = $1 and key = 'global'), 0),
      'monthMicros', coalesce((select sum(cost_micros) from %1$I where day > $1 - 30 and key = 'global'), 0),
      'days', coalesce((select jsonb_agg(jsonb_build_object('day', day, 'micros', cost_micros) order by day)
                        from %1$I where day > $1 - 30 and key = 'global'), '[]'::jsonb),
      'mix', coalesce((select jsonb_object_agg(k, n) from (
                         select m.key as k, sum(m.value::bigint) as n
                         from %1$I, jsonb_each_text(model_mix) as m
                         where day > $1 - 30 and %1$I.key = 'global'
                         group by m.key) x), '{}'::jsonb))
  $q$, p_table) into v_out using v_today;
  return v_out;
end;
$$;

revoke all on function public.ai_cost_summary(text) from public, anon, authenticated;
grant execute on function public.ai_cost_summary(text) to service_role;

notify pgrst, 'reload schema';
