-- Generic profile display names lookup (username) for the app.
--
-- Purpose:
-- - Avoid showing short-id "codes" when a client cannot read other profiles due to RLS.
-- - Prefer the user's chosen username (display_name), otherwise fall back to metadata/email.
--
-- Run this in Supabase SQL Editor.

create or replace function public.get_profile_display_names(profile_ids uuid[])
returns table (
  profile_id uuid,
  display_name text
)
language sql
stable
security definer
set search_path = public, auth
as $$
  select
    au.id as profile_id,
    coalesce(
      nullif(trim(to_jsonb(p)->>'display_name'), ''),
      nullif(trim(to_jsonb(p)->>'full_name'), ''),
      nullif(trim(to_jsonb(p)->>'name'), ''),
      nullif(trim(au.raw_user_meta_data->>'display_name'), ''),
      nullif(trim(au.email), ''),
      -- last resort: stable short id
      (left(au.id::text, 4) || '…' || right(au.id::text, 4))
    )::text as display_name
  from auth.users au
  left join public.profiles p on p.id = au.id
  where au.id = any(profile_ids);
$$;

grant execute on function public.get_profile_display_names(uuid[]) to authenticated;

