-- Home "Uitgelicht" points (highlights)
--
-- Run this in Supabase SQL editor if `home_highlights` does not exist yet.

create table if not exists public.home_highlights (
  highlight_id bigserial primary key,
  title text not null,
  subtitle text not null default '',
  icon text not null default '🏐',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists idx_home_highlights_created_at
  on public.home_highlights(created_at desc);

-- Keep updated_at fresh
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

-- RLS (basic)
alter table public.home_highlights enable row level security;

-- Everyone can read
drop policy if exists "home_highlights_select_auth" on public.home_highlights;
create policy "home_highlights_select_auth"
on public.home_highlights
for select
to authenticated
using (true);

-- Write access (global admins)
drop policy if exists "home_highlights_admin_all" on public.home_highlights;
create policy "home_highlights_admin_all"
on public.home_highlights
for all
to authenticated
using (public.is_global_admin())
with check (public.is_global_admin());

-- Optional: allow bestuur + communicatie to manage highlights too.
-- This matches the app UI which enables highlight editing for those roles.

create or replace function public.is_communicatie()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.committee_members cm
    where cm.profile_id = auth.uid()
      and lower(cm.committee_name) like '%communicatie%'
  );
$$;

create or replace function public.can_manage_highlights()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select public.is_global_admin()
      or exists (
        select 1
        from public.committee_members cm
        where cm.profile_id = auth.uid()
          and lower(cm.committee_name) like '%bestuur%'
      )
      or public.is_communicatie();
$$;

drop policy if exists "home_highlights_manage_roles" on public.home_highlights;
create policy "home_highlights_manage_roles"
on public.home_highlights
for insert
to authenticated
with check (public.can_manage_highlights());

drop policy if exists "home_highlights_update_roles" on public.home_highlights;
create policy "home_highlights_update_roles"
on public.home_highlights
for update
to authenticated
using (public.can_manage_highlights())
with check (public.can_manage_highlights());

drop policy if exists "home_highlights_delete_roles" on public.home_highlights;
create policy "home_highlights_delete_roles"
on public.home_highlights
for delete
to authenticated
using (public.can_manage_highlights());

