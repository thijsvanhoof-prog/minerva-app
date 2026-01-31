-- Home agenda + RSVPs (aanmelden)
--
-- Run this in Supabase SQL editor if these tables do not exist yet.

create table if not exists public.home_agenda (
  agenda_id bigserial primary key,
  title text not null,
  description text null,
  start_datetime timestamptz null,
  end_datetime timestamptz null,
  location text null,
  can_rsvp boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- If the table already existed with a different column name (e.g. starts_at/start_at),
-- make sure `start_datetime` exists so the app can sort and display consistently.
do $$
begin
  if not exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'home_agenda'
      and column_name = 'start_datetime'
  ) then
    alter table public.home_agenda add column start_datetime timestamptz null;

    -- If there is an older column, copy its values.
    if exists (
      select 1
      from information_schema.columns
      where table_schema = 'public'
        and table_name = 'home_agenda'
        and column_name = 'starts_at'
    ) then
      execute 'update public.home_agenda set start_datetime = starts_at where start_datetime is null';
    elsif exists (
      select 1
      from information_schema.columns
      where table_schema = 'public'
        and table_name = 'home_agenda'
        and column_name = 'start_at'
    ) then
      execute 'update public.home_agenda set start_datetime = start_at where start_datetime is null';
    end if;
  end if;

  -- Create the index only if the column exists.
  if exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'home_agenda'
      and column_name = 'start_datetime'
  ) then
    execute 'create index if not exists idx_home_agenda_start_datetime on public.home_agenda(start_datetime)';
  end if;
end
$$;

-- Beschrijving (alleen zichtbaar bij Lees meer) en einddatum/-tijd
alter table public.home_agenda add column if not exists description text null;
alter table public.home_agenda add column if not exists end_datetime timestamptz null;
create index if not exists idx_home_agenda_end_datetime on public.home_agenda(end_datetime);

create table if not exists public.home_agenda_rsvps (
  rsvp_id bigserial primary key,
  agenda_id bigint not null references public.home_agenda(agenda_id) on delete cascade,
  profile_id uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  unique(agenda_id, profile_id)
);

create index if not exists idx_home_agenda_rsvps_agenda_id
  on public.home_agenda_rsvps(agenda_id);
create index if not exists idx_home_agenda_rsvps_profile_id
  on public.home_agenda_rsvps(profile_id);

-- updated_at trigger helper (shared with home_highlights_schema.sql)
create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists trg_home_agenda_updated_at on public.home_agenda;
create trigger trg_home_agenda_updated_at
before update on public.home_agenda
for each row execute function public.set_updated_at();

-- ----------------------------
-- RLS
-- ----------------------------
alter table public.home_agenda enable row level security;
alter table public.home_agenda_rsvps enable row level security;

-- Everyone can read agenda + RSVP rows (for own-state we only need own rows,
-- but allowing read makes it easier to build admin views later).
drop policy if exists "home_agenda_select_auth" on public.home_agenda;
create policy "home_agenda_select_auth"
on public.home_agenda
for select
to authenticated
using (true);

drop policy if exists "home_agenda_rsvps_select_own" on public.home_agenda_rsvps;
create policy "home_agenda_rsvps_select_own"
on public.home_agenda_rsvps
for select
to authenticated
using (profile_id = auth.uid());

-- Users can create/delete their own RSVP row
drop policy if exists "home_agenda_rsvps_insert_own" on public.home_agenda_rsvps;
create policy "home_agenda_rsvps_insert_own"
on public.home_agenda_rsvps
for insert
to authenticated
with check (profile_id = auth.uid());

drop policy if exists "home_agenda_rsvps_delete_own" on public.home_agenda_rsvps;
create policy "home_agenda_rsvps_delete_own"
on public.home_agenda_rsvps
for delete
to authenticated
using (profile_id = auth.uid());

-- Admins (global) can manage agenda + RSVPs (optional)
drop policy if exists "home_agenda_admin_all" on public.home_agenda;
create policy "home_agenda_admin_all"
on public.home_agenda
for all
to authenticated
using (public.is_global_admin())
with check (public.is_global_admin());

drop policy if exists "home_agenda_rsvps_admin_all" on public.home_agenda_rsvps;
create policy "home_agenda_rsvps_admin_all"
on public.home_agenda_rsvps
for all
to authenticated
using (public.is_global_admin())
with check (public.is_global_admin());

