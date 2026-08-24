-- Overzicht: welke accounts hebben geen team en/of geen commissie.
-- Run in Supabase SQL Editor.
--
-- Resultset 1: accounts zonder team
-- Resultset 2: accounts zonder commissie
-- Resultset 3: gecombineerd overzicht met beide flags

with base_accounts as (
  select
    au.id as profile_id,
    coalesce(
      nullif(trim(to_jsonb(p)->>'display_name'), ''),
      nullif(trim(to_jsonb(p)->>'full_name'), ''),
      nullif(trim(to_jsonb(p)->>'name'), ''),
      nullif(trim(au.raw_user_meta_data->>'display_name'), ''),
      nullif(trim(au.email), '')
    )::text as display_name,
    coalesce(au.email, '')::text as email
  from auth.users au
  left join public.profiles p on p.id = au.id
),
team_profiles as (
  select distinct tm.profile_id
  from public.team_members tm
  where tm.profile_id is not null
),
committee_profiles as (
  select distinct cm.profile_id
  from public.committee_members cm
  where cm.profile_id is not null
)

-- 1) Accounts zonder team
select
  b.profile_id,
  b.display_name,
  b.email
from base_accounts b
left join team_profiles t on t.profile_id = b.profile_id
where t.profile_id is null
order by lower(coalesce(nullif(b.display_name, ''), b.email, b.profile_id::text));

-- 2) Accounts zonder commissie
with base_accounts as (
  select
    au.id as profile_id,
    coalesce(
      nullif(trim(to_jsonb(p)->>'display_name'), ''),
      nullif(trim(to_jsonb(p)->>'full_name'), ''),
      nullif(trim(to_jsonb(p)->>'name'), ''),
      nullif(trim(au.raw_user_meta_data->>'display_name'), ''),
      nullif(trim(au.email), '')
    )::text as display_name,
    coalesce(au.email, '')::text as email
  from auth.users au
  left join public.profiles p on p.id = au.id
),
committee_profiles as (
  select distinct cm.profile_id
  from public.committee_members cm
  where cm.profile_id is not null
)
select
  b.profile_id,
  b.display_name,
  b.email
from base_accounts b
left join committee_profiles c on c.profile_id = b.profile_id
where c.profile_id is null
order by lower(coalesce(nullif(b.display_name, ''), b.email, b.profile_id::text));

-- 3) Gecombineerd overzicht (handig om te filteren/exporteren)
with base_accounts as (
  select
    au.id as profile_id,
    coalesce(
      nullif(trim(to_jsonb(p)->>'display_name'), ''),
      nullif(trim(to_jsonb(p)->>'full_name'), ''),
      nullif(trim(to_jsonb(p)->>'name'), ''),
      nullif(trim(au.raw_user_meta_data->>'display_name'), ''),
      nullif(trim(au.email), '')
    )::text as display_name,
    coalesce(au.email, '')::text as email
  from auth.users au
  left join public.profiles p on p.id = au.id
),
team_profiles as (
  select distinct tm.profile_id
  from public.team_members tm
  where tm.profile_id is not null
),
committee_profiles as (
  select distinct cm.profile_id
  from public.committee_members cm
  where cm.profile_id is not null
)
select
  b.profile_id,
  b.display_name,
  b.email,
  (t.profile_id is null) as has_no_team,
  (c.profile_id is null) as has_no_committee
from base_accounts b
left join team_profiles t on t.profile_id = b.profile_id
left join committee_profiles c on c.profile_id = b.profile_id
order by lower(coalesce(nullif(b.display_name, ''), b.email, b.profile_id::text));

