-- Match availability (Speel mee / Speel niet) for Nevobo matches
--
-- Used by: Sport -> Wedstrijden tab
-- match_key format: "nevobo_match:<TEAMCODE>:<START_UTC_ISO>"
--
-- NOTE: Run this in Supabase SQL editor.

create table if not exists public.match_availability (
  availability_id bigserial primary key,
  match_key text not null,
  team_code text null,
  starts_at timestamptz null,
  summary text null,
  location text null,

  profile_id uuid not null references auth.users(id) on delete cascade,
  status text not null check (status in ('playing', 'not_playing', 'coach')),

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  unique(match_key, profile_id)
);

create index if not exists idx_match_availability_match_key
  on public.match_availability(match_key);
create index if not exists idx_match_availability_profile_id
  on public.match_availability(profile_id);

-- Re-use your existing updated_at trigger if present
do $$
begin
  if exists (select 1 from pg_proc where proname = 'set_updated_at') then
    drop trigger if exists trg_match_availability_updated_at on public.match_availability;
    create trigger trg_match_availability_updated_at
    before update on public.match_availability
    for each row
    execute function public.set_updated_at();
  end if;
end $$;

-- RLS
alter table public.match_availability enable row level security;

drop policy if exists "match_availability_select_auth" on public.match_availability;
create policy "match_availability_select_auth"
on public.match_availability
for select
to authenticated
using (true);

drop policy if exists "match_availability_insert_own" on public.match_availability;
create policy "match_availability_insert_own"
on public.match_availability
for insert
to authenticated
with check (profile_id = auth.uid());

drop policy if exists "match_availability_update_own" on public.match_availability;
create policy "match_availability_update_own"
on public.match_availability
for update
to authenticated
using (profile_id = auth.uid())
with check (profile_id = auth.uid());

drop policy if exists "match_availability_delete_own" on public.match_availability;
create policy "match_availability_delete_own"
on public.match_availability
for delete
to authenticated
using (profile_id = auth.uid());

-- Global admins can manage all rows
drop policy if exists "match_availability_admin_all" on public.match_availability;
create policy "match_availability_admin_all"
on public.match_availability
for all
to authenticated
using (public.is_global_admin())
with check (public.is_global_admin());

-- Bestaande tabel met alleen playing/not_playing? Uitbreiden met coach.
alter table public.match_availability drop constraint if exists match_availability_status_check;
alter table public.match_availability add constraint match_availability_status_check
  check (status in ('playing', 'not_playing', 'coach'));

