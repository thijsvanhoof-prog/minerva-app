-- Home highlights – minimale versie (geen is_global_admin / committee_members nodig)
--
-- Voer dit uit in Supabase → SQL Editor als de app meldt dat je home_highlights moet toevoegen.
-- Daarna verdwijnt de melding en kun je highlights gebruiken (of mockdata als je niets toevoegt).

create table if not exists public.home_highlights (
  highlight_id bigserial primary key,
  title text not null,
  subtitle text not null default '',
  icon_name text not null default '🏐',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- Bestaande tabel met icon maar zonder icon_name? Voeg kolom toe (app gebruikt icon_name).
alter table public.home_highlights
  add column if not exists icon_name text not null default '🏐';
do $$
begin
  if exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = 'home_highlights' and column_name = 'icon') then
    execute 'update public.home_highlights set icon_name = coalesce(icon::text, ''🏐'')';
  end if;
end $$;

create index if not exists idx_home_highlights_created_at
  on public.home_highlights(created_at desc);

create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists trg_home_highlights_updated_at on public.home_highlights;
create trigger trg_home_highlights_updated_at
before update on public.home_highlights
for each row execute function public.set_updated_at();

alter table public.home_highlights enable row level security;

-- Iedereen die is ingelogd mag lezen
drop policy if exists "home_highlights_select_auth" on public.home_highlights;
create policy "home_highlights_select_auth"
on public.home_highlights for select to authenticated using (true);

-- Iedereen die is ingelogd mag beheren (voor nu; vervang later door home_highlights_schema.sql voor rollen)
drop policy if exists "home_highlights_insert_auth" on public.home_highlights;
create policy "home_highlights_insert_auth"
on public.home_highlights for insert to authenticated with check (true);

drop policy if exists "home_highlights_update_auth" on public.home_highlights;
create policy "home_highlights_update_auth"
on public.home_highlights for update to authenticated using (true) with check (true);

drop policy if exists "home_highlights_delete_auth" on public.home_highlights;
create policy "home_highlights_delete_auth"
on public.home_highlights for delete to authenticated using (true);
