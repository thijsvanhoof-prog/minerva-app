-- Committee members + profile display names
--
-- Run this in Supabase SQL editor.
-- This RPC returns committee members with names, without requiring broad SELECT
-- permissions on `profiles` from the client.

create or replace function public.get_committee_members_with_names()
returns table (
  committee_name text,
  profile_id uuid,
  display_name text,
  function text
)
language sql
stable
security definer
set search_path = public
as $$
  select
    cm.committee_name::text,
    cm.profile_id,
    -- Use JSON access for optional columns (some schemas don't have full_name).
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
    )::text as function
  from public.committee_members cm
  left join public.profiles p on p.id = cm.profile_id
  where auth.role() = 'authenticated';
$$;

grant execute on function public.get_committee_members_with_names() to authenticated;

