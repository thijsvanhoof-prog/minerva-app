-- Committee members + profile display names + email (voor klikbare mailto in Contact-tab).
--
-- Run this in Supabase SQL editor.
-- Returntype wijzigen vereist eerst droppen.

drop function if exists public.get_committee_members_with_names();

create or replace function public.get_committee_members_with_names()
returns table (
  committee_name text,
  profile_id uuid,
  display_name text,
  function text,
  email text
)
language sql
stable
security definer
set search_path = public
as $$
  select
    cm.committee_name::text,
    cm.profile_id,
    coalesce(
      p.display_name,
      to_jsonb(p)->>'full_name',
      to_jsonb(p)->>'name',
      p.email,
      ''
    )::text as display_name,
    coalesce(
      to_jsonb(cm)->>'function',
      to_jsonb(cm)->>'role',
      to_jsonb(cm)->>'title'
    )::text as function,
    nullif(trim(p.email), '')::text as email
  from public.committee_members cm
  left join public.profiles p on p.id = cm.profile_id
  where auth.role() = 'authenticated';
$$;

grant execute on function public.get_committee_members_with_names() to authenticated;

