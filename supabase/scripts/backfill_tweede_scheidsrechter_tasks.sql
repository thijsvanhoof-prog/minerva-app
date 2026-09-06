-- Backfill: voor elke toekomstige wedstrijd met fluiten/tellen maar zonder 2de scheidsrechter,
-- maak een tweede-scheidsrechtertaak aan en koppel die aan de wedstrijd.
--
-- Voer uit NA supabase/nevobo_home_matches_tweede_scheidsrechter.sql

do $$
declare
  r record;
  src_task record;
  src_task_id bigint;
  new_task_id bigint;
  ass record;
begin
  for r in
    select
      nhm.match_key,
      nhm.fluiten_task_id,
      nhm.tellen_task_id,
      nhm.team_code,
      nhm.starts_at,
      nhm.summary,
      nhm.location
    from public.nevobo_home_matches nhm
    where nhm.tweede_scheidsrechter_task_id is null
      and nhm.starts_at >= now() - interval '1 day'
      and (nhm.fluiten_task_id is not null or nhm.tellen_task_id is not null)
  loop
    src_task_id := coalesce(r.fluiten_task_id, r.tellen_task_id);

    select title, starts_at, location, notes, created_by
    into src_task
    from public.club_tasks
    where task_id = src_task_id;

    if not found then
      continue;
    end if;

    insert into public.club_tasks (title, type, required, starts_at, location, notes, created_by)
    values (
      '2de scheidsrechter (' || r.team_code || ')',
      'tweede_scheidsrechter',
      true,
      coalesce(src_task.starts_at, r.starts_at),
      coalesce(src_task.location, r.location),
      coalesce(
        regexp_replace(src_task.notes, 'kind:(fluiten|tellen)', 'kind:tweede_scheidsrechter'),
        r.match_key || E'\n' || 'kind:tweede_scheidsrechter'
      ),
      src_task.created_by
    )
    returning task_id into new_task_id;

    for ass in
      select distinct team_id, assigned_by
      from public.club_task_team_assignments
      where task_id in (
        select unnest(array_remove(array[r.fluiten_task_id, r.tellen_task_id], null))
      )
    loop
      insert into public.club_task_team_assignments (task_id, team_id, assigned_by)
      values (new_task_id, ass.team_id, ass.assigned_by)
      on conflict do nothing;
    end loop;

    update public.nevobo_home_matches
    set tweede_scheidsrechter_task_id = new_task_id, updated_at = now()
    where match_key = r.match_key;
  end loop;
end $$;
