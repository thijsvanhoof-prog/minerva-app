-- Sheet export RPC for "B" (includes signup names).
--
-- Use-case:
-- - Google Sheet should always reflect the latest state:
--   - upcoming home matches
--   - linked team (team_id)
--   - task ids (fluiten/tellen)
--   - signup counts + signup names
--
-- NOTE:
-- - This function uses SECURITY DEFINER so it can read names even if RLS on
--   `profiles` is restrictive for normal clients.
-- - Do NOT expose this directly to the public internet with anon access.
--   Use an Edge Function bridge (recommended) and secure it with a secret.

create or replace function public.get_sheet_home_matches()
returns table (
  match_key text,
  team_code text,
  starts_at timestamptz,
  summary text,
  location text,
  linked_team_id bigint,
  fluiten_task_id bigint,
  tellen_task_id bigint,
  fluiten_count int,
  tellen_count int,
  fluiten_names text[],
  tellen_names text[]
)
language sql
stable
security definer
set search_path = public, auth
as $$
  select
    nhm.match_key::text,
    nhm.team_code::text,
    nhm.starts_at,
    coalesce(nhm.summary, '')::text as summary,
    coalesce(nhm.location, '')::text as location,
    nhm.linked_team_id,
    nhm.fluiten_task_id,
    nhm.tellen_task_id,
    coalesce(f.cnt, 0) as fluiten_count,
    coalesce(t.cnt, 0) as tellen_count,
    coalesce(f.names, '{}'::text[]) as fluiten_names,
    coalesce(t.names, '{}'::text[]) as tellen_names
  from public.nevobo_home_matches nhm

  left join lateral (
    select
      count(*)::int as cnt,
      array_agg(
        distinct coalesce(
          to_jsonb(p)->>'display_name',
          to_jsonb(p)->>'full_name',
          to_jsonb(p)->>'name',
          au.email,
          ''
        )
        order by coalesce(
          to_jsonb(p)->>'display_name',
          to_jsonb(p)->>'full_name',
          to_jsonb(p)->>'name',
          au.email,
          ''
        )
      ) as names
    from public.club_task_signups s
    left join public.profiles p on p.id = s.profile_id
    left join auth.users au on au.id = s.profile_id
    where nhm.fluiten_task_id is not null
      and s.task_id = nhm.fluiten_task_id
  ) f on true

  left join lateral (
    select
      count(*)::int as cnt,
      array_agg(
        distinct coalesce(
          to_jsonb(p)->>'display_name',
          to_jsonb(p)->>'full_name',
          to_jsonb(p)->>'name',
          au.email,
          ''
        )
        order by coalesce(
          to_jsonb(p)->>'display_name',
          to_jsonb(p)->>'full_name',
          to_jsonb(p)->>'name',
          au.email,
          ''
        )
      ) as names
    from public.club_task_signups s
    left join public.profiles p on p.id = s.profile_id
    left join auth.users au on au.id = s.profile_id
    where nhm.tellen_task_id is not null
      and s.task_id = nhm.tellen_task_id
  ) t on true

  where nhm.starts_at >= now() - interval '1 day'
  order by nhm.starts_at asc;
$$;

grant execute on function public.get_sheet_home_matches() to authenticated;

