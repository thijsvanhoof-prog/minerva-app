-- Fix voor oudere home_agenda schema's met verplichte event_date/event_time.
-- Doel: compatibel met nieuwe app die primair start_datetime/end_datetime gebruikt.
--
-- Run in Supabase SQL Editor.

do $$
begin
  -- Zorg dat moderne kolommen bestaan.
  if not exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'home_agenda' and column_name = 'start_datetime'
  ) then
    alter table public.home_agenda add column start_datetime timestamptz null;
  end if;

  if not exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'home_agenda' and column_name = 'end_datetime'
  ) then
    alter table public.home_agenda add column end_datetime timestamptz null;
  end if;

  -- Als legacy event_date bestaat: maak hem veilig (geen NOT NULL blokkade meer).
  if exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'home_agenda' and column_name = 'event_date'
  ) then
    -- Backfill waar mogelijk vanuit start_datetime; anders vandaag.
    update public.home_agenda
       set event_date = coalesce(
         event_date,
         (start_datetime at time zone 'UTC')::date,
         current_date
       )
     where event_date is null;

    alter table public.home_agenda
      alter column event_date set default current_date;
    alter table public.home_agenda
      alter column event_date drop not null;
  end if;

  -- Als legacy event_time bestaat: idem.
  if exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'home_agenda' and column_name = 'event_time'
  ) then
    update public.home_agenda
       set event_time = coalesce(
         event_time,
         ((start_datetime at time zone 'UTC')::time),
         time '00:00:00'
       )
     where event_time is null;

    alter table public.home_agenda
      alter column event_time set default time '00:00:00';
    alter table public.home_agenda
      alter column event_time drop not null;
  end if;

  -- Oude schema's kunnen location als NOT NULL hebben.
  if exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'home_agenda' and column_name = 'location'
  ) then
    update public.home_agenda
       set location = coalesce(location, '')
     where location is null;

    alter table public.home_agenda
      alter column location set default '';
    alter table public.home_agenda
      alter column location drop not null;
  end if;
end
$$;
