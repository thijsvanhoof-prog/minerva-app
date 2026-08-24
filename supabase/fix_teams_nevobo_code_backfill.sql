-- Idempotent backfill: vul teams.nevobo_code waar leeg, afgeleid uit team_name.
-- Voer eerst supabase/teams_nevobo_sync.sql uit als kolom nevobo_code nog ontbreekt.

alter table public.teams add column if not exists nevobo_code text;

-- 1) Compacte codes (HS1, JC1, Minerva MA 1 → MA1 na spaties verwijderen)
update public.teams t
set nevobo_code = sub.code
from (
  select
    team_id,
    case
      when compact ~ '^XR\d+$' then 'MR' || substring(compact from 3)
      when compact ~ '^(HS|DS|JA|JB|JC|JD|MA|MB|MC|MD|MR)\d+$' then compact
      else null
    end as code
  from (
    select
      team_id,
      upper(regexp_replace(trim(coalesce(team_name, '')), '\s+', '', 'g')) as compact
    from public.teams
    where coalesce(trim(nevobo_code), '') = ''
  ) raw
) sub
where t.team_id = sub.team_id
  and sub.code is not null
  and coalesce(trim(t.nevobo_code), '') = '';

-- 2) Beschrijvende namen (Heren 2, Meisjes A 1, Jongens C 1, …)
update public.teams t
set nevobo_code = sub.code
from (
  select
    team_id,
    case
      when lower(name) like '%heren%' and num is not null then 'HS' || num
      when lower(name) like '%dames%' and num is not null then 'DS' || num
      when lower(name) like '%jongens%' and youth_letter is not null and num is not null
        then 'J' || upper(youth_letter) || num
      when (lower(name) like '%meiden%' or lower(name) like '%meis%')
        and youth_letter is not null and num is not null
        then 'M' || upper(youth_letter) || num
      when (lower(name) like '%mix%' or lower(name) like '%recre%') and num is not null
        then 'MR' || num
      else null
    end as code
  from (
    select
      team_id,
      trim(coalesce(team_name, '')) as name,
      (regexp_match(trim(coalesce(team_name, '')), '(\d+)'))[1] as num,
      (regexp_match(lower(trim(coalesce(team_name, ''))), '\m([a-d])\m'))[1] as youth_letter
    from public.teams
    where coalesce(trim(nevobo_code), '') = ''
  ) parsed
) sub
where t.team_id = sub.team_id
  and sub.code is not null
  and coalesce(trim(t.nevobo_code), '') = '';
