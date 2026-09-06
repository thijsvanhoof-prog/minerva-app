-- Zorg dat iedere actuele en toekomstige thuiswedstrijd drie losse taken heeft:
--   1. Fluiten
--   2. 2de scheidsrechter
--   3. Tellen
--
-- Dit script is idempotent en kan veilig opnieuw worden uitgevoerd.
-- Run in Supabase -> SQL Editor.

alter table public.nevobo_home_matches
  add column if not exists tweede_scheidsrechter_task_id bigint null
    references public.club_tasks(task_id) on delete set null;

create or replace function public.ensure_nevobo_home_match_tasks()
returns trigger
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  actor_id uuid := coalesce(new.updated_by, new.created_by, auth.uid());
  task_title_suffix text := coalesce(nullif(trim(new.team_code), ''), 'wedstrijd');
  task_notes text;
  existing_match public.nevobo_home_matches%rowtype;
begin
  -- Oude wedstrijden hoeven geen nieuwe open taken meer te krijgen.
  if new.starts_at < now() - interval '4 hours' then
    return new;
  end if;

  -- Nevobo-imports gebruiken upsert. Hergebruik bij een conflict altijd de al
  -- gekoppelde taken, zodat een refresh geen dubbele club_tasks kan aanmaken.
  perform pg_advisory_xact_lock(hashtextextended(new.match_key, 0));
  if tg_op = 'UPDATE' then
    new.fluiten_task_id := coalesce(new.fluiten_task_id, old.fluiten_task_id);
    new.tellen_task_id := coalesce(new.tellen_task_id, old.tellen_task_id);
    new.tweede_scheidsrechter_task_id := coalesce(
      new.tweede_scheidsrechter_task_id,
      old.tweede_scheidsrechter_task_id
    );
  else
    select *
    into existing_match
    from public.nevobo_home_matches
    where match_key = new.match_key;

    if found then
      new.fluiten_task_id := coalesce(
        new.fluiten_task_id,
        existing_match.fluiten_task_id
      );
      new.tellen_task_id := coalesce(
        new.tellen_task_id,
        existing_match.tellen_task_id
      );
      new.tweede_scheidsrechter_task_id := coalesce(
        new.tweede_scheidsrechter_task_id,
        existing_match.tweede_scheidsrechter_task_id
      );
    end if;
  end if;

  task_notes := concat_ws(
    E'\n',
    new.match_key,
    nullif(trim(new.summary), ''),
    case
      when nullif(trim(coalesce(new.location, '')), '') is not null
        then 'Locatie: ' || trim(new.location)
      else null
    end
  );

  if new.fluiten_task_id is null then
    insert into public.club_tasks (
      title, type, required, starts_at, location, notes, created_by
    ) values (
      'Fluiten (' || task_title_suffix || ')',
      'fluiten',
      true,
      new.starts_at,
      new.location,
      task_notes || E'\nkind:fluiten',
      actor_id
    )
    returning task_id into new.fluiten_task_id;
  end if;

  if new.tweede_scheidsrechter_task_id is null then
    insert into public.club_tasks (
      title, type, required, starts_at, location, notes, created_by
    ) values (
      '2de scheidsrechter (' || task_title_suffix || ')',
      'tweede_scheidsrechter',
      true,
      new.starts_at,
      new.location,
      task_notes || E'\nkind:tweede_scheidsrechter',
      actor_id
    )
    returning task_id into new.tweede_scheidsrechter_task_id;
  end if;

  if new.tellen_task_id is null then
    insert into public.club_tasks (
      title, type, required, starts_at, location, notes, created_by
    ) values (
      'Tellen (' || task_title_suffix || ')',
      'tellen',
      true,
      new.starts_at,
      new.location,
      task_notes || E'\nkind:tellen',
      actor_id
    )
    returning task_id into new.tellen_task_id;
  end if;

  return new;
end;
$$;

drop trigger if exists trg_ensure_nevobo_home_match_tasks
  on public.nevobo_home_matches;

create trigger trg_ensure_nevobo_home_match_tasks
before insert or update
on public.nevobo_home_matches
for each row
execute function public.ensure_nevobo_home_match_tasks();

-- Backfill alle huidige/toekomstige wedstrijden. De trigger vult uitsluitend
-- ontbrekende ids aan en laat bestaande taken en inschrijvingen ongemoeid.
update public.nevobo_home_matches
set updated_at = now()
where starts_at >= now() - interval '4 hours'
  and (
    fluiten_task_id is null
    or tellen_task_id is null
    or tweede_scheidsrechter_task_id is null
  );

select pg_notify('pgrst', 'reload schema');

-- Controle: deze query moet na afloop nul rijen teruggeven.
select
  match_key,
  team_code,
  starts_at,
  fluiten_task_id,
  tweede_scheidsrechter_task_id,
  tellen_task_id
from public.nevobo_home_matches
where starts_at >= now() - interval '4 hours'
  and (
    fluiten_task_id is null
    or tellen_task_id is null
    or tweede_scheidsrechter_task_id is null
  )
order by starts_at;
