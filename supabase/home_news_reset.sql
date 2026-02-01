-- Reset script: home_news volledig opnieuw maken (met backup & restore)
--
-- LET OP: Dit dropt de tabel. Gebruik dit alleen als je dat oké vindt.
-- Dit script maakt eerst een backup in `public.home_news_backup` (JSONB),
-- en probeert daarna de data weer terug te zetten.
--
-- Run in Supabase → SQL Editor.

begin;

-- 1) Backup (idempotent: overschrijft vorige backup)
drop table if exists public.home_news_backup;
create table public.home_news_backup as
select to_jsonb(t) as row
from public.home_news t;

-- 2) Drop de bestaande tabel (policies/triggers gaan mee weg)
drop table if exists public.home_news cascade;

-- 3) Maak tabel opnieuw (met defaults voor NOT NULL kolommen)
create table public.home_news (
  news_id bigserial primary key,
  title text not null,
  description text not null default '',
  author text not null default 'Bestuur',
  category text not null default 'bestuur',
  source text not null default 'app',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists idx_home_news_created_at
  on public.home_news(created_at desc);

-- 4) updated_at trigger (gebruik bestaande set_updated_at() als je die al hebt)
create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists trg_home_news_updated_at on public.home_news;
create trigger trg_home_news_updated_at
before update on public.home_news
for each row execute function public.set_updated_at();

-- 5) RLS + policies
alter table public.home_news enable row level security;

drop policy if exists "home_news_select_auth" on public.home_news;
create policy "home_news_select_auth"
on public.home_news for select to authenticated using (true);

drop policy if exists "home_news_insert_auth" on public.home_news;
create policy "home_news_insert_auth"
on public.home_news for insert to authenticated with check (true);

drop policy if exists "home_news_update_auth" on public.home_news;
create policy "home_news_update_auth"
on public.home_news for update to authenticated using (true) with check (true);

drop policy if exists "home_news_delete_auth" on public.home_news;
create policy "home_news_delete_auth"
on public.home_news for delete to authenticated using (true);

-- 6) Restore (best effort)
--    - pakt description óf body uit de backup
--    - zet author/category/source defaults als ze ontbreken/leeg zijn
insert into public.home_news (title, description, author, category, source, created_at, updated_at)
select
  coalesce(nullif(row->>'title', ''), '') as title,
  coalesce(row->>'description', row->>'body', '') as description,
  coalesce(nullif(row->>'author', ''), 'Bestuur') as author,
  coalesce(nullif(row->>'category', ''), 'bestuur') as category,
  coalesce(nullif(row->>'source', ''), 'app') as source,
  coalesce((row->>'created_at')::timestamptz, now()) as created_at,
  coalesce((row->>'updated_at')::timestamptz, now()) as updated_at
from public.home_news_backup;

commit;

