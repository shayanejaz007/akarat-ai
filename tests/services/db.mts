// A real Postgres (PGlite) with just enough of Supabase around it to run
// migrations 0023 (locations) and 0024 (services): the auth and storage
// schemas, the API roles, and the tables those migrations build on. Each
// test file gets a fresh database.
import { PGlite } from "@electric-sql/pglite";
import { readFileSync } from "node:fs";

const migration = (name: string) => readFileSync(new URL(`../../supabase/migrations/${name}`, import.meta.url), "utf8");

const SUPABASE = `
do $$ begin
  if not exists (select 1 from pg_roles where rolname = 'anon') then create role anon nologin; end if;
  if not exists (select 1 from pg_roles where rolname = 'authenticated') then create role authenticated nologin; end if;
  if not exists (select 1 from pg_roles where rolname = 'service_role') then create role service_role nologin bypassrls; end if;
end $$;

create schema if not exists auth;
create table auth.users (id uuid primary key, email text);
-- Supabase's own definition: the caller's id from the request's JWT.
create function auth.uid() returns uuid language sql stable as $$
  select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid
$$;
grant usage on schema auth to anon, authenticated, service_role;
grant execute on function auth.uid() to anon, authenticated, service_role;

create schema if not exists storage;
create table storage.buckets (id text primary key, name text, public boolean, file_size_limit bigint, allowed_mime_types text[]);
create table storage.objects (id uuid primary key default gen_random_uuid(), bucket_id text, name text, owner uuid);
alter table storage.objects enable row level security;
create function storage.foldername(name text) returns text[] language sql immutable as $$
  select (string_to_array(name, '/'))[1:array_length(string_to_array(name, '/'), 1) - 1]
$$;
grant usage on schema storage to anon, authenticated, service_role;
grant select, insert, delete on storage.objects to authenticated;

grant usage on schema public to anon, authenticated, service_role;

-- 0001: the place tables, as they were before 0023.
create table public.cities (
  id text primary key, name_en text not null, name_ar text not null,
  lat double precision, lng double precision, created_at timestamptz not null default now()
);
create table public.neighborhoods (
  id text primary key, city_id text not null references public.cities (id) on delete cascade,
  name_en text not null, name_ar text not null, lat double precision, lng double precision,
  aliases text[] not null default '{}', created_at timestamptz not null default now()
);
alter table public.cities enable row level security;
alter table public.neighborhoods enable row level security;
create policy "cities readable by anyone" on public.cities for select using (true);
create policy "neighborhoods readable by anyone" on public.neighborhoods for select using (true);
grant select on public.cities, public.neighborhoods to anon, authenticated;
grant all on public.cities, public.neighborhoods to service_role;
-- What 0009 left in place: a core city and area that listings already use.
insert into public.cities (id, name_en, name_ar) values ('amman', 'Amman (old)', 'عمان');
insert into public.neighborhoods (id, city_id, name_en, name_ar) values ('abdoun', 'amman', 'Abdoun (old)', 'عبدون');

-- 0001's profiles, with the role column.
create table public.profiles (id uuid primary key references auth.users (id) on delete cascade, full_name text, role text not null default 'user');
grant all on public.profiles to service_role;

-- 0019's notifications.
create table public.notifications (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  kind text not null, property_id uuid, booking_id uuid,
  data jsonb not null default '{}', read_at timestamptz, created_at timestamptz not null default now()
);
alter table public.notifications enable row level security;
create policy "people read their own notifications" on public.notifications for select using (auth.uid() = user_id);
grant select on public.notifications to authenticated;
grant all on public.notifications to service_role;
`;

export const USERS = {
  lina: "11111111-1111-4111-8111-111111111111",
  omar: "22222222-2222-4222-8222-222222222222",
  admin: "33333333-3333-4333-8333-333333333333",
};

export async function freshDb(): Promise<PGlite> {
  const db = new PGlite();
  await db.exec(SUPABASE);
  await db.exec(migration("0023_locations.sql"));
  await db.exec(migration("0024_services.sql"));
  for (const [name, id] of Object.entries(USERS)) {
    await db.query("insert into auth.users (id, email) values ($1, $2)", [id, `${name}@example.com`]);
    await db.query("insert into public.profiles (id, full_name, role) values ($1, $2, $3)", [id, name, name === "admin" ? "admin" : "user"]);
  }
  return db;
}

/** Runs `sql` as a signed-in user through the API role, as PostgREST would. */
export async function asUser<T = Record<string, unknown>>(db: PGlite, user: string | null, sql: string, params: unknown[] = []) {
  await db.exec("reset role");
  await db.query("select set_config('request.jwt.claim.sub', $1, false)", [user ?? ""]);
  await db.exec(user ? "set role authenticated" : "set role anon");
  try {
    return await db.query<T>(sql, params);
  } finally {
    await db.exec("reset role");
    await db.query("select set_config('request.jwt.claim.sub', '', false)");
  }
}

/** Runs `sql` as the admin panel's server does: the service role. */
export async function asService<T = Record<string, unknown>>(db: PGlite, sql: string, params: unknown[] = []) {
  await db.exec("set role service_role");
  try {
    return await db.query<T>(sql, params);
  } finally {
    await db.exec("reset role");
  }
}

/** The message a raised exception carries, or null when the call succeeded. */
export async function errorOf(p: Promise<unknown>): Promise<string | null> {
  try {
    await p;
    return null;
  } catch (e) {
    return (e as Error).message;
  }
}
