-- Ouder/verzorger: teamtaken inzien + gekoppeld account aan/afmelden
--
-- Extends club_task_signups policies so a parent may create/delete signup rows
-- for their linked child (account_links.parent_id -> child_id).
--
-- Run this in Supabase SQL Editor.

-- Ensure helper exists (safe to run multiple times)
create or replace function public.is_guardian_of(target_profile_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.account_links l
    where l.parent_id = auth.uid()
      and l.child_id = target_profile_id
  );
$$;

grant execute on function public.is_guardian_of(uuid) to authenticated;

-- Allow signup insert/delete for self OR linked child.
drop policy if exists "club_task_signups_insert_own" on public.club_task_signups;
create policy "club_task_signups_insert_own"
on public.club_task_signups
for insert
to authenticated
with check (
  profile_id = auth.uid()
  or public.is_guardian_of(profile_id)
);

drop policy if exists "club_task_signups_delete_own" on public.club_task_signups;
create policy "club_task_signups_delete_own"
on public.club_task_signups
for delete
to authenticated
using (
  profile_id = auth.uid()
  or public.is_guardian_of(profile_id)
);

