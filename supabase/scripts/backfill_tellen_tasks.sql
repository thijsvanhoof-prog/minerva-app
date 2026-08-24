-- Backfill: voor elke wedstrijd die wel fluiten heeft maar geen tellen,
-- maak een tellen-taak aan en koppel die aan de wedstrijd.
-- Zo kunnen commissieleden Scheidsrechters/Tellers zich overal voor tellen aanmelden.
--
-- Voer uit in Supabase → SQL Editor (eenmalig of bij nieuwe wedstrijden met alleen fluiten).

do $$
declare
  r record;
  fl_task record;
  new_task_id bigint;
  ass record;
begin
  for r in
    select nhm.match_key, nhm.fluiten_task_id, nhm.team_code, nhm.starts_at, nhm.summary, nhm.location
    from public.nevobo_home_matches nhm
    where nhm.fluiten_task_id is not null
      and nhm.tellen_task_id is null
  loop
    select title, starts_at, location, notes, created_by
    into fl_task
    from public.club_tasks
    where task_id = r.fluiten_task_id;

    if not found then
      continue; -- fluiten task verwijderd?
    end if;

    insert into public.club_tasks (title, type, required, starts_at, location, notes, created_by)
    values (
      replace(fl_task.title, 'Fluiten', 'Tellen'),
      'tellen',
      true,
      fl_task.starts_at,
      fl_task.location,
      case
        when fl_task.notes is not null then replace(fl_task.notes, 'kind:fluiten', 'kind:tellen')
        else null
      end,
      fl_task.created_by
    )
    returning task_id into new_task_id;

    -- Zelfde team-toewijzing als bij fluiten (zodat "Toegewezen aan: HS1" klopt)
    for ass in
      select team_id, assigned_by
      from public.club_task_team_assignments
      where task_id = r.fluiten_task_id
    loop
      insert into public.club_task_team_assignments (task_id, team_id, assigned_by)
      values (new_task_id, ass.team_id, ass.assigned_by);
    end loop;

    update public.nevobo_home_matches
    set tellen_task_id = new_task_id, updated_at = now()
    where match_key = r.match_key;
  end loop;
end $$;
