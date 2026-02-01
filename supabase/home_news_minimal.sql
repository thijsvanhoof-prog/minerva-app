-- Nieuwsberichten – titel + beschrijving (bestuur/communicatie kunnen toevoegen)
--
-- Voer dit uit in Supabase → SQL Editor. Daarna kun je nieuws toevoegen via de + knop.

create table if not exists public.home_news (
  news_id bigserial primary key,
  title text not null,
  description text not null default '',
  author text not null default 'Bestuur',
  category text not null default 'bestuur',
  -- Some deployments use `source` to track where the item came from.
  source text not null default 'app',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- Bestaande tabel zonder description? Voeg kolom toe (fix voor "column home_news.description does not exist").
alter table public.home_news
  add column if not exists description text not null default '';

-- Existing table without author/category/source? Add them (compat with older deployments).
alter table public.home_news
  add column if not exists author text not null default 'Bestuur';
alter table public.home_news
  add column if not exists category text not null default 'bestuur';

-- Existing table without source? Add it (fix for "null value in column 'source' violates not-null constraint").
alter table public.home_news
  add column if not exists source text not null default 'app';

-- If the column already exists but had NO default, inserts that omit `source`
-- will still fail with "null value in column 'source'". Ensure a default exists.
alter table public.home_news
  alter column source set default 'app';

alter table public.home_news
  alter column author set default 'Bestuur';
alter table public.home_news
  alter column category set default 'bestuur';

create index if not exists idx_home_news_created_at
  on public.home_news(created_at desc);

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
