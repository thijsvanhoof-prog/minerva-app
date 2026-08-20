-- Bestuur: commissies beheren + contactinstellingen per commissie
-- Run in Supabase SQL Editor.
--
-- NOTE:
-- We store app-specific contact settings in a separate table to avoid
-- conflicts with legacy constraints on public.committees.

create table if not exists public.committee_contact_settings (
  committee_key text primary key,
  display_name text,
  show_in_contact boolean not null default true,
  sort_order integer,
  contact_emails text[] not null default '{}',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.committee_contact_settings
  add column if not exists sort_order integer;

create or replace function public.set_committee_contact_settings_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

drop trigger if exists trg_committee_contact_settings_updated_at
  on public.committee_contact_settings;

create trigger trg_committee_contact_settings_updated_at
before update on public.committee_contact_settings
for each row
execute function public.set_committee_contact_settings_updated_at();

alter table public.committee_contact_settings enable row level security;

drop policy if exists "committee_contact_settings_select_public" on public.committee_contact_settings;
drop policy if exists "committee_contact_settings_manage_bestuur" on public.committee_contact_settings;

create policy "committee_contact_settings_select_public"
  on public.committee_contact_settings
  for select
  to authenticated, anon
  using (true);

create policy "committee_contact_settings_manage_bestuur"
  on public.committee_contact_settings
  for all
  to authenticated
  using (
    coalesce(public.is_global_admin(), false)
    or coalesce(public.is_bestuur(), false)
    or exists (
      select 1
      from public.committee_members cm
      where cm.profile_id = auth.uid()
        and lower(trim(cm.committee_name)) like '%bestuur%'
    )
  )
  with check (
    coalesce(public.is_global_admin(), false)
    or coalesce(public.is_bestuur(), false)
    or exists (
      select 1
      from public.committee_members cm
      where cm.profile_id = auth.uid()
        and lower(trim(cm.committee_name)) like '%bestuur%'
    )
  );

-- Optional migration: copy any existing contact settings from public.committees
-- without touching that table's constraints.
do $$
begin
  if exists (
    select 1
    from information_schema.tables
    where table_schema = 'public'
      and table_name = 'committees'
  ) then
    insert into public.committee_contact_settings (
      committee_key,
      display_name,
      show_in_contact,
      sort_order,
      contact_emails
    )
    select
      lower(trim(coalesce(
        nullif(to_jsonb(c)->>'committee_name', ''),
        nullif(to_jsonb(c)->>'name', ''),
        nullif(to_jsonb(c)->>'naam', '')
      ))) as committee_key,
      coalesce(
        nullif(to_jsonb(c)->>'name', ''),
        nullif(to_jsonb(c)->>'naam', ''),
        nullif(to_jsonb(c)->>'committee_name', '')
      ) as display_name,
      coalesce(nullif(to_jsonb(c)->>'show_in_contact', '')::boolean, true) as show_in_contact,
      null::integer as sort_order,
      case
        when jsonb_typeof(to_jsonb(c)->'contact_emails') = 'array' then
          array(
            select jsonb_array_elements_text(to_jsonb(c)->'contact_emails')
          )
        else '{}'
      end as contact_emails
    from public.committees c
    where coalesce(
      nullif(to_jsonb(c)->>'committee_name', ''),
      nullif(to_jsonb(c)->>'name', ''),
      nullif(to_jsonb(c)->>'naam', '')
    ) is not null
    on conflict (committee_key) do update
      set display_name = excluded.display_name,
          show_in_contact = excluded.show_in_contact,
          contact_emails = case
            when cardinality(excluded.contact_emails) > 0 then excluded.contact_emails
            else public.committee_contact_settings.contact_emails
          end;
  end if;
end $$;

-- Backfill order for rows without explicit sort value.
with ordered as (
  select
    committee_key,
    row_number() over (order by lower(coalesce(display_name, committee_key))) - 1 as rn
  from public.committee_contact_settings
)
update public.committee_contact_settings t
set sort_order = ordered.rn
from ordered
where t.committee_key = ordered.committee_key
  and t.sort_order is null;

-- Ensure PostgREST immediately sees new table/policies.
select pg_notify('pgrst', 'reload schema');
