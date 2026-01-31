-- Nevobo home matches linkage (for "Taken -> Overzicht")
--
-- Purpose:
-- - Persist upcoming Nevobo home matches in Supabase
-- - Allow Wedstrijdzaken/Bestuur to link a match to a team
-- - Store created task ids (fluiten/tellen) so it can be synced to Google Sheets easily
--
-- NOTE: Run this in Supabase SQL editor.

-- ----------------------------
-- Helpers for permissions
-- ----------------------------
create or replace function public.is_bestuur()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists(
    select 1
    from public.committee_members cm
    where cm.profile_id = auth.uid()
      and (
        lower(cm.committee_name) = 'bestuur'
        or lower(cm.committee_name) like '%bestuur%'
      )
  );
$$;

create or replace function public.is_wedstrijdzaken()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists(
    select 1
    from public.committee_members cm
    where cm.profile_id = auth.uid()
      and (
        lower(cm.committee_name) = 'wedstrijdzaken'
        or lower(cm.committee_name) like '%wedstrijd%'
      )
  );
$$;

create or replace function public.can_manage_match_links()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select public.is_global_admin() or public.is_bestuur() or public.is_wedstrijdzaken();
$$;

grant execute on function public.is_bestuur() to authenticated;
grant execute on function public.is_wedstrijdzaken() to authenticated;
grant execute on function public.can_manage_match_links() to authenticated;

-- ----------------------------
-- Table
-- ----------------------------
create table if not exists public.nevobo_home_matches (
  match_key text primary key,
  team_code text not null,
  starts_at timestamptz not null,
  summary text not null default '',
  location text null,

  -- link chosen by wedstrijdzaken/bestuur
  linked_team_id bigint null,
  linked_by uuid null references auth.users(id) on delete set null,
  linked_at timestamptz null,

  -- optional: created tasks for this match
  fluiten_task_id bigint null references public.club_tasks(task_id) on delete set null,
  tellen_task_id bigint null references public.club_tasks(task_id) on delete set null,

  created_by uuid null references auth.users(id) on delete set null,
  updated_by uuid null references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists idx_nevobo_home_matches_starts_at
  on public.nevobo_home_matches(starts_at);
create index if not exists idx_nevobo_home_matches_linked_team_id
  on public.nevobo_home_matches(linked_team_id);

-- Updated-at trigger (re-uses your existing trigger function if present)
do $$
begin
  if exists (select 1 from pg_proc where proname = 'set_updated_at') then
    drop trigger if exists trg_nevobo_home_matches_updated_at on public.nevobo_home_matches;
    create trigger trg_nevobo_home_matches_updated_at
    before update on public.nevobo_home_matches
    for each row
    execute function public.set_updated_at();
  end if;
end $$;

-- ----------------------------
-- RLS
-- ----------------------------
alter table public.nevobo_home_matches enable row level security;

drop policy if exists "nevobo_home_matches_select_auth" on public.nevobo_home_matches;
create policy "nevobo_home_matches_select_auth"
on public.nevobo_home_matches
for select
to authenticated
using (true);

drop policy if exists "nevobo_home_matches_manage" on public.nevobo_home_matches;
create policy "nevobo_home_matches_manage"
on public.nevobo_home_matches
for all
to authenticated
using (public.can_manage_match_links())
with check (public.can_manage_match_links());

