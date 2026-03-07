-- Admin profile management RPCs (usernames)
--
-- Purpose:
-- - Alleen globale admins mogen alle gebruikers lijsten en display names wijzigen.
--
-- Requirements:
-- - public.is_global_admin() exists (used by the app already).
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

  if not coalesce(public.is_global_admin(), false) then
    raise exception 'Not allowed: only global admins can list all profiles';
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

  if not coalesce(public.is_global_admin(), false) then
    raise exception 'Not allowed: only global admins can change display names';
  end if;

  if target_profile_id is null then
    raise exception 'Target is required';
  end if;

  update public.profiles
  set display_name = nullif(trim(new_display_name), '')
  where id = target_profile_id;
end;
$$;

-- Details van één account (teams, rollen, commissies) voor admin-accordion.
create or replace function public.admin_get_profile_details(p_profile_id uuid)
returns table (
  display_name text,
  email text,
  teams_text text,
  committees_text text
)
language plpgsql
stable
security definer
set search_path = public, auth
as $$
declare
  v_display_name text;
  v_email text;
  v_teams text;
  v_committees text;
begin
  if auth.uid() is null then
    raise exception 'Not authenticated';
  end if;
  if not coalesce(public.is_global_admin(), false) then
    raise exception 'Not allowed: only global admins';
  end if;
  if p_profile_id is null then
    return;
  end if;

  select
    coalesce(
      nullif(trim(p.display_name::text), ''),
      nullif(trim(au.raw_user_meta_data->>'display_name'), ''),
      nullif(trim(au.email), ''),
      (left(au.id::text, 4) || '…' || right(au.id::text, 4))
    ),
    coalesce(au.email, '')::text
  into v_display_name, v_email
  from auth.users au
  left join public.profiles p on p.id = au.id
  where au.id = p_profile_id;

  select string_agg(
    trim(t.team_name) || ' (' || coalesce(nullif(trim(tm.role), ''), 'lid') || ')',
    ', ' order by lower(trim(t.team_name))
  )
  into v_teams
  from public.team_members tm
  join public.teams t on t.team_id = tm.team_id
  where tm.profile_id = p_profile_id;

  select string_agg(trim(cm.committee_name::text), ', ' order by lower(trim(cm.committee_name::text)))
  into v_committees
  from public.committee_members cm
  where cm.profile_id = p_profile_id;

  display_name := coalesce(v_display_name, '');
  email := coalesce(v_email, '');
  teams_text := coalesce(nullif(trim(v_teams), ''), 'Geen teams');
  committees_text := coalesce(nullif(trim(v_committees), ''), 'Geen commissies');
  return next;
  return;
end;
$$;

grant execute on function public.admin_get_profile_details(uuid) to authenticated;

