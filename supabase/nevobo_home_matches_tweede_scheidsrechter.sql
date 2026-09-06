-- Idempotent live deployment: 2de scheidsrechter per thuiswedstrijd.
-- Voer uit in Supabase SQL Editor vóór app-update 4.4.4+.
-- Daarna optioneel: supabase/scripts/backfill_tweede_scheidsrechter_tasks.sql

alter table public.nevobo_home_matches
  add column if not exists tweede_scheidsrechter_task_id bigint null
    references public.club_tasks(task_id) on delete set null;

-- Returntype wijzigt: veilig droppen en opnieuw aanmaken.
drop function if exists public.get_sheet_home_matches();

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
  tweede_scheidsrechter_task_id bigint,
  fluiten_count int,
  tellen_count int,
  tweede_scheidsrechter_count int,
  fluiten_names text[],
  tellen_names text[],
  tweede_scheidsrechter_names text[]
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
    nhm.tweede_scheidsrechter_task_id,
    coalesce(f.cnt, 0) as fluiten_count,
    coalesce(t.cnt, 0) as tellen_count,
    coalesce(ts.cnt, 0) as tweede_scheidsrechter_count,
    coalesce(f.names, '{}'::text[]) as fluiten_names,
    coalesce(t.names, '{}'::text[]) as tellen_names,
    coalesce(ts.names, '{}'::text[]) as tweede_scheidsrechter_names
  from public.nevobo_home_matches nhm

  left join lateral (
    select
      count(*)::int as cnt,
      array_agg(
        distinct coalesce(
          to_jsonb(p)->>'display_name',
          to_jsonb(p)->>'full_name',
          to_jsonb(p)->>'name',
          au.raw_user_meta_data->>'display_name',
          au.email,
          ''
        )
        order by coalesce(
          to_jsonb(p)->>'display_name',
          to_jsonb(p)->>'full_name',
          to_jsonb(p)->>'name',
          au.raw_user_meta_data->>'display_name',
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
          au.raw_user_meta_data->>'display_name',
          au.email,
          ''
        )
        order by coalesce(
          to_jsonb(p)->>'display_name',
          to_jsonb(p)->>'full_name',
          to_jsonb(p)->>'name',
          au.raw_user_meta_data->>'display_name',
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

  left join lateral (
    select
      count(*)::int as cnt,
      array_agg(
        distinct coalesce(
          to_jsonb(p)->>'display_name',
          to_jsonb(p)->>'full_name',
          to_jsonb(p)->>'name',
          au.raw_user_meta_data->>'display_name',
          au.email,
          ''
        )
        order by coalesce(
          to_jsonb(p)->>'display_name',
          to_jsonb(p)->>'full_name',
          to_jsonb(p)->>'name',
          au.raw_user_meta_data->>'display_name',
          au.email,
          ''
        )
      ) as names
    from public.club_task_signups s
    left join public.profiles p on p.id = s.profile_id
    left join auth.users au on au.id = s.profile_id
    where nhm.tweede_scheidsrechter_task_id is not null
      and s.task_id = nhm.tweede_scheidsrechter_task_id
  ) ts on true

  where nhm.starts_at >= now() - interval '1 day'
  order by nhm.starts_at asc;
$$;

grant execute on function public.get_sheet_home_matches() to authenticated;
