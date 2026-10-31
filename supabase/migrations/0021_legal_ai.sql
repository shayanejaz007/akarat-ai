-- 0021_legal_ai.sql
--
-- Ask a Lawyer (POST /api/legal/ask): the legal library it searches, the
-- private conversations and documents of the people who use it, and the
-- records its operators need.
--
--   1. legal_norm(): Arabic spelling folded for search (hamza forms, alef
--      maqsura, taa marbuta, diacritics, tatweel, Arabic-Indic digits).
--   2. legal_sources / legal_passages: the library. Jordanian legislation,
--      judgments and commentary, one row per source with its provenance
--      (official link, publisher, Official Gazette reference, status,
--      amendments, who verified it and when) and one row per article or
--      passage, searchable by Arabic full text and, once embeddings are
--      loaded, by meaning (pgvector). Only sources marked verified are ever
--      returned to the model. Readable and writable by the service role only.
--   3. legal_search() / legal_lookup(): hybrid retrieval (full text and
--      vectors fused by reciprocal rank) and exact citation lookup.
--   4. legal_conversations / legal_messages / legal_documents: what people
--      ask and upload. Owner-only Row Level Security; the content columns
--      hold AES-256-GCM ciphertext written by the server (lib/legal/crypto.ts),
--      so a database dump or a policy mistake shows nothing readable.
--      Conversations expire 90 days after their last message and documents
--      30 days after upload; triggers set both and nobody can extend them.
--   5. Storage bucket legal-documents: private, one folder per user, the same
--      owner-only rule. Files in it are ciphertext too.
--   6. legal_feedback / legal_audit: reports on answers, and which sources
--      each answer stood on (provenance). Service role only.
--   7. legal_usage_daily / legal_flags and their functions: daily allowances
--      and cost, kept apart from the property advisor's (0020).
--   8. legal_sweep(): deletes what has expired and returns the storage paths
--      the server must remove.
--   9. admin_legal_overview(): the admin panel's figures.
--
-- Needs the vector extension (Supabase: Database → Extensions, or the line
-- below). Safe to run more than once.

create extension if not exists vector with schema extensions;

/* ── 1. Folding Arabic for search ────────────────────────────────────── */

-- The character class is built with chr() so no invisible character ever has
-- to sit in this file: U+064B..U+065F (harakat), U+0670 (superscript alef),
-- U+0640 (tatweel).
--
-- It also drops the conjunction و or ف in front of the definite article
-- ("والمستأجر", "فالمالك"): Postgres's Arabic stemmer leaves those whole, so
-- "والمالك" would never meet "المالك". The same folding runs on the text
-- and on every query, so what it changes, it changes on both sides.
create or replace function public.legal_norm(t text)
returns text
language sql
immutable
parallel safe
as $$
  select regexp_replace(
    translate(
      regexp_replace(coalesce(t, ''), '[' || chr(1611) || '-' || chr(1631) || chr(1648) || chr(1600) || ']', '', 'g'),
      'أإآٱىة٠١٢٣٤٥٦٧٨٩',
      'اااايه0123456789'
    ),
    '(^|[^ء-ي])[وف](ال[ء-ي]{2,})', '\1\2', 'g'
  )
$$;

-- A search query from free text: function words out (Arabic, Jordanian
-- colloquial, English, and the words every legal text repeats), the rest
-- joined by `op` ('|' any word, '&' all of them). Postgres ships no Arabic
-- stop list, and without one "في" alone matches nearly every passage.
create or replace function public.legal_tsquery(p text, cfg regconfig, op text)
returns tsquery
language sql
immutable
parallel safe
as $$
  select case when count(*) = 0 then null
              else to_tsquery(cfg, string_agg(quote_literal(w), case when op = '&' then ' & ' else ' | ' end)) end
  from (
    select distinct w
    from regexp_split_to_table(lower(public.legal_norm(p)), '[^ء-يa-z0-9]+') as w
    where char_length(w) >= 2
      and w <> all (array[
        'في','من','علي','الي','عن','مع','ما','ماذا','لماذا','كيف','متي','اين','هل','هي','هو','هم','هن','انا','انت','انتم','نحن',
        'هذا','هذه','ذلك','تلك','هناك','هنا','التي','الذي','الذين','ان','انه','انها','كان','كانت','يكون','تكون','لا','لم','لن',
        'قد','اذا','او','ثم','كل','بعض','اي','غير','بين','عند','عندما','بعد','قبل','لكن','بل','حتي','ايضا','فقط','جدا','يا','بس',
        'شو','ليش','وين','هيك','بدي','بده','بدها','بدنا','عشان','لانه','اللي','هاد','هاي','هدا','مش','كمان','يعني','عليه',
        'عليها','عليهم','له','لها','لهم','به','بها','منه','منها','فيه','فيها','الا','لو','ولا','وما','ومن','وفي','اذ','اذن',
        'فان','حيث','كما','مثل','ماده','مواد','قانون','رقم','لسنه','سنه',
        'a','an','the','of','to','in','on','at','for','from','by','with','is','are','was','were','be','been','being','do','does',
        'did','can','could','would','should','will','shall','may','might','must','i','me','my','we','our','you','your','he','she',
        'it','they','them','their','this','that','these','those','what','which','who','whom','how','why','when','where','if',
        'or','and','not','no','yes','am','about','into','than','then','there','here','as','so','such','law','article','jordan',
        'jordanian'])
  ) x
$$;

/* ── 2. The library ──────────────────────────────────────────────────── */

create table if not exists public.legal_sources (
  id             uuid primary key default gen_random_uuid(),
  slug           text not null unique check (slug ~ '^[a-z0-9][a-z0-9-]{1,80}$'),
  kind           text not null check (kind in ('constitution', 'law', 'temporary_law', 'regulation', 'instructions',
                                               'decision', 'judgment', 'official_guidance', 'commentary')),
  -- Commentary supplements the law; it never stands in for it.
  tier           text generated always as (case when kind = 'commentary' then 'secondary' else 'primary' end) stored,
  title_ar       text not null check (char_length(title_ar) between 2 and 400),
  title_en       text check (char_length(title_en) <= 400),
  number         text check (char_length(number) <= 40),
  year           integer check (year between 1900 and 2100),
  court          text check (char_length(court) <= 160),
  case_number    text check (char_length(case_number) <= 60),
  decision_date  date,
  issue          text check (char_length(issue) <= 2000),
  holding        text check (char_length(holding) <= 4000),
  status         text not null default 'unknown' check (status in ('in_force', 'amended', 'repealed', 'unknown')),
  effective_date date,
  repealed_date  date,
  repealed_by    text check (char_length(repealed_by) <= 400),
  amendments     jsonb not null default '[]'::jsonb check (jsonb_typeof(amendments) = 'array'),
  gazette_ref    text check (char_length(gazette_ref) <= 400),
  url            text not null check (url ~ '^https://' and char_length(url) <= 1000),
  publisher      text not null check (char_length(publisher) between 2 and 200),
  -- false for a licensed database: citable, but not something a reader can open.
  public_access  boolean not null default true,
  -- The basis on which the text was taken in: "official public text", or the
  -- licence or permission that covers it.
  license        text not null check (char_length(license) between 2 and 400),
  verification   text not null default 'unverified' check (verification in ('verified', 'unverified')),
  verified_by    text check (char_length(verified_by) <= 200),
  last_verified  date,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now(),
  constraint legal_sources_verified_has_who check (verification = 'unverified' or (verified_by is not null and last_verified is not null)),
  constraint legal_sources_judgment_identified check (kind <> 'judgment' or (court is not null and case_number is not null and year is not null))
);

create table if not exists public.legal_passages (
  id          bigint generated always as identity primary key,
  source_id   uuid not null references public.legal_sources(id) on delete cascade,
  ord         integer not null check (ord >= 0),
  article     text check (char_length(article) <= 80),     -- as printed: "المادة 5", "5 مكررة"
  article_no  integer check (article_no between 0 and 100000),
  heading     text check (char_length(heading) <= 400),
  body        text not null check (char_length(body) between 1 and 20000),
  -- An article can be amended or repealed while the law around it is in force.
  status      text check (status in ('in_force', 'amended', 'repealed', 'unknown')),
  note        text check (char_length(note) <= 1000),
  tsv         tsvector generated always as (
                setweight(to_tsvector('simple', public.legal_norm(coalesce(article, '') || ' ' || coalesce(heading, ''))), 'A') ||
                setweight(to_tsvector('arabic', public.legal_norm(body)), 'B') ||
                setweight(to_tsvector('simple', public.legal_norm(body)), 'C')
              ) stored,
  embedding   extensions.vector(1024),
  unique (source_id, ord)
);

create index if not exists legal_passages_tsv on public.legal_passages using gin (tsv);
create index if not exists legal_passages_article on public.legal_passages (source_id, article_no);
create index if not exists legal_passages_embedding on public.legal_passages
  using hnsw (embedding extensions.vector_cosine_ops);
create index if not exists legal_sources_cite on public.legal_sources (number, year);
create index if not exists legal_sources_case on public.legal_sources (case_number, year);

alter table public.legal_sources enable row level security;
alter table public.legal_passages enable row level security;
revoke all on public.legal_sources, public.legal_passages from anon, authenticated;
grant all on public.legal_sources, public.legal_passages to service_role;

/* ── 3. Retrieval ────────────────────────────────────────────────────── */

-- One row per passage, with everything the citation needs about its source.
drop function if exists public.legal_search(text, extensions.vector, text[], integer);
drop function if exists public.legal_lookup(text, integer, integer, text, text, text);

create or replace function public.legal_search(
  p_query text,
  p_embedding extensions.vector(1024) default null,
  p_kinds text[] default null,
  p_limit integer default 8
) returns table (
  passage_id bigint, source_id uuid, slug text, kind text, tier text,
  title_ar text, title_en text, number text, year integer,
  court text, case_number text, decision_date date, issue text, holding text,
  status text, passage_status text, effective_date date, repealed_date date, repealed_by text,
  amendments jsonb, gazette_ref text, url text, publisher text, public_access boolean,
  verified_by text, last_verified date,
  article text, article_no integer, heading text, body text, note text, score double precision
)
language sql
stable
security definer
set search_path = public, extensions, pg_temp
as $$
  with q as (
    -- Stemmed, any of the words: the same rule is worded differently in a
    -- question, a law and a judgment. Exact, all of the words: a passage
    -- that uses the asker's own wording goes first.
    select public.legal_tsquery(p_query, 'arabic', '|') as a,
           public.legal_tsquery(p_query, 'simple', '&') as s
  ),
  pool as (
    select p.id, p.tsv, p.embedding
    from legal_passages p
    join legal_sources s on s.id = p.source_id
    where s.verification = 'verified'
      and (p_kinds is null or s.kind = any (p_kinds))
  ),
  fts as (
    select pool.id,
           row_number() over (
             order by (q.s is not null and pool.tsv @@ q.s) desc, ts_rank_cd(pool.tsv, q.a) desc
           ) as r
    from pool, q
    where q.a is not null and pool.tsv @@ q.a
    order by r
    limit 60
  ),
  vec as (
    select pool.id, row_number() over (order by pool.embedding <=> p_embedding) as r
    from pool
    where p_embedding is not null and pool.embedding is not null
    order by pool.embedding <=> p_embedding
    limit 60
  ),
  fused as (
    select id, sum(1.0 / (60 + r))::double precision as score
    from (select id, r from fts union all select id, r from vec) x
    group by id
  )
  select p.id, s.id, s.slug, s.kind, s.tier,
         s.title_ar, s.title_en, s.number, s.year,
         s.court, s.case_number, s.decision_date, s.issue, s.holding,
         s.status, p.status, s.effective_date, s.repealed_date, s.repealed_by,
         s.amendments, s.gazette_ref, s.url, s.publisher, s.public_access,
         s.verified_by, s.last_verified,
         p.article, p.article_no, p.heading, p.body, p.note, f.score
  from fused f
  join legal_passages p on p.id = f.id
  join legal_sources s on s.id = p.source_id
  order by f.score desc, p.id
  limit least(greatest(coalesce(p_limit, 8), 1), 20);
$$;

-- An exact citation: an article of a numbered law, or a judgment by its case
-- number. Nothing fuzzy: a lookup that finds the wrong article is worse than
-- one that finds none.
create or replace function public.legal_lookup(
  p_number text,
  p_year integer,
  p_article integer,
  p_court text,
  p_case_number text,
  p_title text
) returns table (
  passage_id bigint, source_id uuid, slug text, kind text, tier text,
  title_ar text, title_en text, number text, year integer,
  court text, case_number text, decision_date date, issue text, holding text,
  status text, passage_status text, effective_date date, repealed_date date, repealed_by text,
  amendments jsonb, gazette_ref text, url text, publisher text, public_access boolean,
  verified_by text, last_verified date,
  article text, article_no integer, heading text, body text, note text, score double precision
)
language sql
stable
security definer
set search_path = public, extensions, pg_temp
as $$
  with src as (
    select s.*
    from legal_sources s
    where s.verification = 'verified'
      and (
        (p_case_number is not null and s.kind = 'judgment'
          and public.legal_norm(s.case_number) = public.legal_norm(p_case_number)
          and (p_year is null or s.year = p_year)
          and (p_court is null or public.legal_norm(s.court) like '%' || public.legal_norm(p_court) || '%'))
        or
        (p_case_number is null and s.kind <> 'judgment'
          and (
            (p_number is not null and public.legal_norm(s.number) = public.legal_norm(p_number) and (p_year is null or s.year = p_year))
            or (p_number is null and p_title is not null and char_length(p_title) >= 4
                and public.legal_norm(s.title_ar) like '%' || public.legal_norm(p_title) || '%'
                and (p_year is null or s.year = p_year))))
      )
    limit 3
  )
  select p.id, s.id, s.slug, s.kind, s.tier,
         s.title_ar, s.title_en, s.number, s.year,
         s.court, s.case_number, s.decision_date, s.issue, s.holding,
         s.status, p.status, s.effective_date, s.repealed_date, s.repealed_by,
         s.amendments, s.gazette_ref, s.url, s.publisher, s.public_access,
         s.verified_by, s.last_verified,
         p.article, p.article_no, p.heading, p.body, p.note, 1.0::double precision
  from src s
  join legal_passages p on p.source_id = s.id
  where (p_article is null and p.ord < 3) or p.article_no = p_article
  order by s.id, p.ord
  limit 6;
$$;

revoke all on function public.legal_search(text, extensions.vector, text[], integer) from public, anon, authenticated;
revoke all on function public.legal_lookup(text, integer, integer, text, text, text) from public, anon, authenticated;
grant execute on function public.legal_search(text, extensions.vector, text[], integer) to service_role;
grant execute on function public.legal_lookup(text, integer, integer, text, text, text) to service_role;

/* ── 4. Conversations, messages, documents ──────────────────────────── */

create table if not exists public.legal_conversations (
  id         uuid primary key default gen_random_uuid(),
  user_id    uuid not null default auth.uid() references auth.users(id) on delete cascade,
  title_enc  text not null check (char_length(title_enc) between 1 and 2000),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  expires_at timestamptz not null default now() + interval '90 days'
);

create table if not exists public.legal_messages (
  id              bigint generated always as identity primary key,
  conversation_id uuid not null references public.legal_conversations(id) on delete cascade,
  user_id         uuid not null default auth.uid() references auth.users(id) on delete cascade,
  role            text not null check (role in ('user', 'assistant')),
  content_enc     text not null check (char_length(content_enc) between 1 and 400000),
  created_at      timestamptz not null default now()
);

create table if not exists public.legal_documents (
  id              uuid primary key default gen_random_uuid(),
  conversation_id uuid not null references public.legal_conversations(id) on delete cascade,
  user_id         uuid not null default auth.uid() references auth.users(id) on delete cascade,
  name_enc        text not null check (char_length(name_enc) between 1 and 2000),
  kind            text not null check (kind in ('pdf', 'docx', 'txt', 'image')),
  media_type      text not null check (media_type in ('application/pdf', 'text/plain', 'image/jpeg', 'image/png', 'image/webp')),
  bytes           integer not null check (bytes between 1 and 6000000),
  pages           integer check (pages between 0 and 1000),
  tokens          integer check (tokens >= 0),
  scanned         boolean not null default false,
  object_path     text not null check (char_length(object_path) <= 200),
  created_at      timestamptz not null default now(),
  expires_at      timestamptz not null default now() + interval '30 days'
);

create index if not exists legal_conversations_user on public.legal_conversations (user_id, updated_at desc);
create index if not exists legal_conversations_expiry on public.legal_conversations (expires_at);
create index if not exists legal_messages_conversation on public.legal_messages (conversation_id, id);
create index if not exists legal_documents_conversation on public.legal_documents (conversation_id, created_at);
create index if not exists legal_documents_expiry on public.legal_documents (expires_at);

-- Retention is set here, not by whoever writes the row: a conversation lives
-- 90 days past its last message, a document 30 days past its upload, and an
-- update cannot move either date.
create or replace function public.legal_conversation_stamp()
returns trigger
language plpgsql
set search_path = public, pg_temp
as $$
begin
  if tg_op = 'INSERT' then
    new.created_at := now();
  else
    new.created_at := old.created_at;
    new.user_id := old.user_id;
  end if;
  new.updated_at := now();
  new.expires_at := now() + interval '90 days';
  return new;
end;
$$;

create or replace function public.legal_document_stamp()
returns trigger
language plpgsql
set search_path = public, pg_temp
as $$
begin
  new.created_at := now();
  new.expires_at := now() + interval '30 days';
  return new;
end;
$$;

create or replace function public.legal_message_stamp()
returns trigger
language plpgsql
set search_path = public, pg_temp
as $$
begin
  new.created_at := now();
  return new;
end;
$$;

drop trigger if exists legal_conversation_stamp on public.legal_conversations;
create trigger legal_conversation_stamp before insert or update on public.legal_conversations
  for each row execute function public.legal_conversation_stamp();
drop trigger if exists legal_document_stamp on public.legal_documents;
create trigger legal_document_stamp before insert on public.legal_documents
  for each row execute function public.legal_document_stamp();
drop trigger if exists legal_message_stamp on public.legal_messages;
create trigger legal_message_stamp before insert on public.legal_messages
  for each row execute function public.legal_message_stamp();

alter table public.legal_conversations enable row level security;
alter table public.legal_messages enable row level security;
alter table public.legal_documents enable row level security;

revoke all on public.legal_conversations, public.legal_messages, public.legal_documents from anon, authenticated;
grant select, insert, delete on public.legal_conversations, public.legal_messages, public.legal_documents to authenticated;
-- A conversation's title and its last-used time are all that ever change.
grant update (title_enc, updated_at) on public.legal_conversations to authenticated;
grant all on public.legal_conversations, public.legal_messages, public.legal_documents to service_role;

drop policy if exists legal_conversations_owner on public.legal_conversations;
create policy legal_conversations_owner on public.legal_conversations
  for all to authenticated
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

-- A message or document belongs to its writer and must sit in one of their
-- own conversations.
drop policy if exists legal_messages_owner on public.legal_messages;
create policy legal_messages_owner on public.legal_messages
  for all to authenticated
  using (user_id = auth.uid())
  with check (
    user_id = auth.uid()
    and exists (select 1 from public.legal_conversations c where c.id = conversation_id and c.user_id = auth.uid())
  );

drop policy if exists legal_documents_owner on public.legal_documents;
create policy legal_documents_owner on public.legal_documents
  for all to authenticated
  using (user_id = auth.uid())
  with check (
    user_id = auth.uid()
    and object_path like auth.uid()::text || '/%'
    and exists (select 1 from public.legal_conversations c where c.id = conversation_id and c.user_id = auth.uid())
  );

/* ── 5. The private bucket ───────────────────────────────────────────── */

-- Skipped where there is no storage schema (a plain Postgres used for tests).
do $$
begin
  if to_regclass('storage.buckets') is null then
    return;
  end if;

  insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
  values ('legal-documents', 'legal-documents', false, 6291456, array['application/octet-stream'])
  on conflict (id) do update
    set public = false, file_size_limit = 6291456, allowed_mime_types = array['application/octet-stream'];

  execute 'drop policy if exists "legal documents: owner reads" on storage.objects';
  execute $p$create policy "legal documents: owner reads" on storage.objects for select to authenticated
    using (bucket_id = 'legal-documents' and (storage.foldername(name))[1] = auth.uid()::text)$p$;
  execute 'drop policy if exists "legal documents: owner writes" on storage.objects';
  execute $p$create policy "legal documents: owner writes" on storage.objects for insert to authenticated
    with check (bucket_id = 'legal-documents' and (storage.foldername(name))[1] = auth.uid()::text)$p$;
  execute 'drop policy if exists "legal documents: owner deletes" on storage.objects';
  execute $p$create policy "legal documents: owner deletes" on storage.objects for delete to authenticated
    using (bucket_id = 'legal-documents' and (storage.foldername(name))[1] = auth.uid()::text)$p$;
end;
$$;

/* ── 6. Feedback and provenance ──────────────────────────────────────── */

create table if not exists public.legal_feedback (
  id           bigint generated always as identity primary key,
  at           timestamptz not null default now(),
  user_id      uuid references auth.users(id) on delete set null,
  message_id   bigint references public.legal_messages(id) on delete set null,
  -- The message's id as it was, kept when the conversation is deleted: the
  -- sealed note and snapshot are bound to it.
  message_ref  bigint not null,
  kind         text not null check (kind in ('good', 'wrong_law', 'wrong_citation', 'outdated', 'fabricated', 'missing', 'unclear', 'other')),
  note_enc     text check (char_length(note_enc) <= 8000),
  reviewer     boolean not null default false,
  -- Reviewers only: the question and answer they reported, kept for the
  -- launch review even after the conversation is deleted.
  snapshot_enc text check (char_length(snapshot_enc) <= 300000)
);

create table if not exists public.legal_audit (
  id              bigint generated always as identity primary key,
  at              timestamptz not null default now(),
  conversation_id uuid references public.legal_conversations(id) on delete set null,
  message_id      bigint references public.legal_messages(id) on delete set null,
  model           text check (char_length(model) <= 80),
  status          text check (char_length(status) <= 20),
  -- [{ "tier": "library"|"official"|"secondary"|"document", "ref": slug or URL, "cited": bool }]
  sources         jsonb not null default '[]'::jsonb check (jsonb_typeof(sources) = 'array'),
  cited           integer not null default 0,
  unverified      integer not null default 0,
  flags           text[] not null default '{}'
);

create index if not exists legal_feedback_at on public.legal_feedback (at desc);
create index if not exists legal_audit_at on public.legal_audit (at desc);

alter table public.legal_feedback enable row level security;
alter table public.legal_audit enable row level security;
revoke all on public.legal_feedback, public.legal_audit from anon, authenticated;
grant all on public.legal_feedback, public.legal_audit to service_role;

/* ── 7. Allowances and cost ──────────────────────────────────────────── */

create table if not exists public.legal_usage_daily (
  day                date    not null,
  key                text    not null check (char_length(key) between 1 and 80),
  turns              integer not null default 0,
  input_tokens       bigint  not null default 0,
  output_tokens      bigint  not null default 0,
  cache_read_tokens  bigint  not null default 0,
  cache_write_tokens bigint  not null default 0,
  web_searches       integer not null default 0,
  web_fetches        integer not null default 0,
  flagged            integer not null default 0,
  primary key (day, key)
);

create table if not exists public.legal_flags (
  id   bigint generated always as identity primary key,
  at   timestamptz not null default now(),
  key  text not null check (char_length(key) between 1 and 80),
  kind text not null check (kind ~ '^[a-z_]{1,40}$')
);

create index if not exists legal_flags_at on public.legal_flags (at desc);

alter table public.legal_usage_daily enable row level security;
alter table public.legal_flags enable row level security;
revoke all on public.legal_usage_daily, public.legal_flags from anon, authenticated;
grant all on public.legal_usage_daily, public.legal_flags to service_role;

create or replace function public.legal_usage_take(p_key text, p_limit integer, p_global_limit integer)
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

  insert into legal_usage_daily (day, key, turns) values (v_day, 'global', 1)
  on conflict (day, key) do update set turns = legal_usage_daily.turns + 1
  returning turns into v_global;
  if v_global > p_global_limit then
    update legal_usage_daily set turns = turns - 1 where day = v_day and key = 'global';
    return 'global';
  end if;

  insert into legal_usage_daily (day, key, turns) values (v_day, p_key, 1)
  on conflict (day, key) do update set turns = legal_usage_daily.turns + 1
  returning turns into v_mine;
  if v_mine > p_limit then
    update legal_usage_daily set turns = turns - 1 where day = v_day and key in (p_key, 'global');
    return 'user';
  end if;

  if random() < 0.01 then
    delete from legal_usage_daily where day < v_day - 120;
    delete from legal_flags where at < now() - interval '120 days';
    delete from legal_audit where at < now() - interval '400 days';
  end if;

  return 'ok';
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
  p_flags text[]
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
      (day, key, input_tokens, output_tokens, cache_read_tokens, cache_write_tokens, web_searches, web_fetches, flagged)
    values
      (v_day, v_key, greatest(p_input, 0), greatest(p_output, 0), greatest(p_cache_read, 0), greatest(p_cache_write, 0),
       greatest(p_searches, 0), greatest(p_fetches, 0), least(v_flags, 1))
    on conflict (day, key) do update set
      input_tokens       = u.input_tokens + excluded.input_tokens,
      output_tokens      = u.output_tokens + excluded.output_tokens,
      cache_read_tokens  = u.cache_read_tokens + excluded.cache_read_tokens,
      cache_write_tokens = u.cache_write_tokens + excluded.cache_write_tokens,
      web_searches       = u.web_searches + excluded.web_searches,
      web_fetches        = u.web_fetches + excluded.web_fetches,
      flagged            = u.flagged + excluded.flagged;
  end loop;

  if v_flags > 0 then
    insert into legal_flags (key, kind)
    select p_key, f from unnest(p_flags[1:10]) as f where f ~ '^[a-z_]{1,40}$';
  end if;
end;
$$;

revoke all on function public.legal_usage_take(text, integer, integer) from public, anon, authenticated;
revoke all on function public.legal_usage_record(text, bigint, bigint, bigint, bigint, integer, integer, text[]) from public, anon, authenticated;
grant execute on function public.legal_usage_take(text, integer, integer) to service_role;
grant execute on function public.legal_usage_record(text, bigint, bigint, bigint, bigint, integer, integer, text[]) to service_role;

/* ── 8. Expiry ───────────────────────────────────────────────────────── */

-- Deletes expired conversations (their messages and documents go with them)
-- and expired documents, and returns the storage paths whose files the
-- server must now remove. A file whose removal fails is ciphertext under a
-- key the database never sees.
create or replace function public.legal_sweep(p_limit integer default 200)
returns setof text
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_convs uuid[];
  v_paths text[];
begin
  -- The conversations first, then every document in them: a document that
  -- went with its conversation but not into the list would leave its file.
  select coalesce(array_agg(id), '{}') into v_convs
  from (select id from legal_conversations where expires_at < now() limit greatest(p_limit, 1)) x;

  select coalesce(array_agg(object_path), '{}') into v_paths
  from (
    select object_path from legal_documents where conversation_id = any (v_convs)
    union
    (select object_path from legal_documents where expires_at < now() limit greatest(p_limit, 1))
  ) x;

  delete from legal_documents where object_path = any (v_paths);
  delete from legal_conversations where id = any (v_convs);

  return query select unnest(v_paths);
end;
$$;

revoke all on function public.legal_sweep(integer) from public, anon, authenticated;
grant execute on function public.legal_sweep(integer) to service_role;

/* ── 9. For the admin panel ──────────────────────────────────────────── */

create or replace function public.admin_legal_overview()
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
      from legal_usage_daily, today where day = today.d),
    'days', coalesce((
      select jsonb_agg(jsonb_build_object(
        'day', day, 'turns', turns, 'input', input_tokens, 'output', output_tokens,
        'cacheRead', cache_read_tokens, 'cacheWrite', cache_write_tokens,
        'searches', web_searches, 'fetches', web_fetches, 'flagged', flagged) order by day)
      from legal_usage_daily, today
      where key = 'global' and day > today.d - 30), '[]'::jsonb),
    'flags', coalesce((
      select jsonb_agg(jsonb_build_object('kind', kind, 'count', n) order by n desc)
      from (select kind, count(*) as n from legal_flags where at > now() - interval '7 days' group by kind) f), '[]'::jsonb),
    'answers', (
      select jsonb_build_object(
        'total',          count(*),
        'withCitations',  count(*) filter (where cited > 0),
        'withUnverified', count(*) filter (where unverified > 0),
        'cited',          coalesce(sum(cited), 0),
        'unverified',     coalesce(sum(unverified), 0))
      from legal_audit where at > now() - interval '30 days'),
    'library', (
      select jsonb_build_object(
        'sources',     count(*),
        'verified',    count(*) filter (where verification = 'verified'),
        'judgments',   count(*) filter (where kind = 'judgment' and verification = 'verified'),
        'legislation', count(*) filter (where kind <> 'judgment' and kind <> 'commentary' and verification = 'verified'),
        'commentary',  count(*) filter (where kind = 'commentary' and verification = 'verified'),
        'repealed',    count(*) filter (where status = 'repealed'),
        'stale',       count(*) filter (where verification = 'verified' and last_verified < (now() - interval '180 days')::date),
        'oldestCheck', min(last_verified) filter (where verification = 'verified'),
        'passages',    (select count(*) from legal_passages),
        'embedded',    (select count(*) from legal_passages where embedding is not null))
      from legal_sources),
    'feedback', (
      select jsonb_build_object(
        'counts', coalesce((
          select jsonb_agg(jsonb_build_object('kind', kind, 'count', n) order by n desc)
          from (select kind, count(*) as n from legal_feedback where at > now() - interval '30 days' group by kind) k), '[]'::jsonb),
        'recent', coalesce((
          select jsonb_agg(jsonb_build_object(
            'id', id, 'at', at, 'kind', kind, 'reviewer', reviewer, 'ref', message_ref,
            'note', note_enc, 'snapshot', snapshot_enc) order by at desc)
          from (select * from legal_feedback order by at desc limit 20) r), '[]'::jsonb)))
  );
$$;

revoke all on function public.admin_legal_overview() from public, anon, authenticated;
grant execute on function public.admin_legal_overview() to service_role;

notify pgrst, 'reload schema';
