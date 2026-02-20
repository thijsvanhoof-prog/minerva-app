-- Audit: vergelijk huidige teams met de gewenste Minerva-lijst.
-- Run in Supabase SQL Editor.
-- Resultaat:
-- 1) ontbrekende teams in huidig seizoen
-- 2) extra teams in huidig seizoen
-- 3) waar een teamnaam voorkomt in andere seizoenen

with expected(team_name) as (
  values
    ('DS1'), ('DS2'), ('DS3'), ('DS4'),
    ('HS1'), ('HS2'), ('HS3'),
    ('MA1'),
    ('MB1'), ('MB2'),
    ('JB1'),
    ('JC1'),
    ('XR1'),
    ('Volleystars'),
    ('Recreanten (niet competitie)')
),
seasons as (
  select coalesce(
    (select season from public.teams where season is not null limit 1),
    to_char(current_date - interval '8 months', 'YYYY') || '-' || to_char(current_date + interval '4 months', 'YYYY')
  ) as season
),
teams_norm as (
  select
    t.team_id,
    t.team_name::text as team_name,
    t.season
  from public.teams t
),
current_season_teams as (
  select tn.*
  from teams_norm tn
  join seasons s on s.season = tn.season
)
select
  'missing_in_current_season' as kind,
  e.team_name,
  (select season from seasons) as season,
  null::bigint as team_id
from expected e
where not exists (
  select 1
  from current_season_teams c
  where lower(c.team_name) = lower(e.team_name)
)

union all

select
  'extra_in_current_season' as kind,
  c.team_name,
  c.season,
  c.team_id
from current_season_teams c
where not exists (
  select 1
  from expected e
  where lower(e.team_name) = lower(c.team_name)
)

union all

select
  'exists_in_other_season' as kind,
  tn.team_name,
  tn.season,
  tn.team_id
from teams_norm tn
join expected e on lower(e.team_name) = lower(tn.team_name)
where tn.season is distinct from (select season from seasons)
order by kind, team_name;
