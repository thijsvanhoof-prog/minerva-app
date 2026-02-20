-- Admin profile management RPCs (usernames)
--
-- Purpose:
-- - Allow admins, bestuur and TC to list users and update display names (team toevoegen, namen wijzigen).
--
-- Requirements:
-- - public.is_global_admin() exists (used by the app already).
-- - public.committee_members (committee_name, profile_id) for bestuur/TC check.
--
-- Run this in Supabase SQL Editor.

create or replace function public.admin_list_profiles()
returns table (
  profile_id uuid,
  display_name text,
  email text
)
language plpgsql
stable
security definer
set search_path = public, auth
as $$
begin
  if auth.uid() is null then
    raise exception 'Not authenticated';
  end if;

  -- Toegestaan: global admin, bestuur of technische commissie (tc)
  if public.is_global_admin() then
    null; -- fall through to return query
  elsif exists (select 1 from pg_tables where schemaname = 'public' and tablename = 'committee_members')
    and exists (
      select 1 from public.committee_members cm
      where lower(cm.committee_name) = 'bestuur' and cm.profile_id = auth.uid()
    ) then
    null;
  elsif exists (select 1 from pg_tables where schemaname = 'public' and tablename = 'committee_members')
    and exists (
      select 1 from public.committee_members cm
      where lower(cm.committee_name) in ('technische-commissie', 'tc') and cm.profile_id = auth.uid()
    ) then
    null;
  else
    raise exception 'Not allowed';
  end if;

  return query
    select
      au.id as profile_id,
      coalesce(
        nullif(trim(to_jsonb(p)->>'display_name'), ''),
        nullif(trim(to_jsonb(p)->>'full_name'), ''),
        nullif(trim(to_jsonb(p)->>'name'), ''),
        nullif(trim(au.raw_user_meta_data->>'display_name'), ''),
        nullif(trim(au.email), ''),
        (left(au.id::text, 4) || '…' || right(au.id::text, 4))
      )::text as display_name,
      coalesce(au.email, '')::text as email
    from auth.users au
    left join public.profiles p on p.id = au.id
    order by lower(
      coalesce(
        nullif(trim(to_jsonb(p)->>'display_name'), ''),
        nullif(trim(au.raw_user_meta_data->>'display_name'), ''),
        nullif(trim(au.email), ''),
        au.id::text
      )
    );
end;
$$;

create or replace function public.admin_set_profile_display_name(
  target_profile_id uuid,
  new_display_name text
)
returns void
language plpgsql
security definer
set search_path = public, auth
as $$
begin
  if auth.uid() is null then
    raise exception 'Not authenticated';
  end if;

  -- Zelfde toegang als admin_list_profiles: admin, bestuur, TC
  if public.is_global_admin() then
    null;
  elsif exists (select 1 from pg_tables where schemaname = 'public' and tablename = 'committee_members')
    and exists (
      select 1 from public.committee_members cm
      where lower(cm.committee_name) = 'bestuur' and cm.profile_id = auth.uid()
    ) then
    null;
  elsif exists (select 1 from pg_tables where schemaname = 'public' and tablename = 'committee_members')
    and exists (
      select 1 from public.committee_members cm
      where lower(cm.committee_name) in ('technische-commissie', 'tc') and cm.profile_id = auth.uid()
    ) then
    null;
  else
    raise exception 'Not allowed';
  end if;

  if target_profile_id is null then
    raise exception 'Target is required';
  end if;

  update public.profiles
  set display_name = nullif(trim(new_display_name), '')
  where id = target_profile_id;
end;
$$;

grant execute on function public.admin_list_profiles() to authenticated;
grant execute on function public.admin_set_profile_display_name(uuid, text) to authenticated;

