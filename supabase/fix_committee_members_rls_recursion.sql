-- Fix: infinite recursion in RLS policy on committee_members
--
-- Error example:
--   PostgrestException(... infinite recursion detected in policy for relation "committee_members" ...)
--
-- Cause:
-- - A policy on committee_members references committee_members again in its own USING/WITH CHECK
--   via a normal query, which re-triggers RLS recursively.
--
-- Solution:
-- 1) Use SECURITY DEFINER helper function(s) for role checks.
-- 2) Recreate committee_members policies without self-recursive policy predicates.
--
-- Run in Supabase SQL Editor.

-- Helper: mag commissies beheren (bestuur of global admin)
create or replace function public.is_bestuur_or_admin()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select
    coalesce(public.is_global_admin(), false) is true
    or exists (
      select 1
      from public.committee_members cm
      where cm.profile_id = auth.uid()
        and lower(cm.committee_name) = 'bestuur'
    );
$$;

grant execute on function public.is_bestuur_or_admin() to authenticated;

-- Drop all existing policies on committee_members (safe reset)
do $$
declare
  p record;
begin
  for p in
    select pol.polname
    from pg_policy pol
    join pg_class cls on cls.oid = pol.polrelid
    join pg_namespace ns on ns.oid = cls.relnamespace
    where ns.nspname = 'public'
      and cls.relname = 'committee_members'
  loop
    execute format('drop policy if exists %I on public.committee_members', p.polname);
  end loop;
end
$$;

alter table public.committee_members enable row level security;

-- Everyone logged in may read committee memberships
create policy "committee_members_select_all_authenticated"
on public.committee_members
for select
to authenticated
using (true);

-- Only bestuur/admin may add committee memberships
create policy "committee_members_insert_bestuur_or_admin"
on public.committee_members
for insert
to authenticated
with check (public.is_bestuur_or_admin());

-- Only bestuur/admin may update committee memberships
create policy "committee_members_update_bestuur_or_admin"
on public.committee_members
for update
to authenticated
using (public.is_bestuur_or_admin())
with check (public.is_bestuur_or_admin());

-- Only bestuur/admin may delete committee memberships
create policy "committee_members_delete_bestuur_or_admin"
on public.committee_members
for delete
to authenticated
using (public.is_bestuur_or_admin());

