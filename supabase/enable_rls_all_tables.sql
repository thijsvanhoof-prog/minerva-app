-- Schakel Row Level Security (RLS) in op ALLE tabellen in het public schema.
-- Uitvoeren in Supabase Dashboard → SQL Editor (of via psql).
--
-- Wat dit script doet:
--  1) Voor elke gewone tabel in `public` wordt RLS aangezet (idempotent).
--  2) Tabellen die nog GEEN enkele policy hebben krijgen een minimale
--     "authenticated mag lezen"-policy zodat de app blijft werken.
--     Schrijfrechten worden NIET automatisch toegevoegd — beheer/insert/update
--     blijft via bestaande policies en RPC's lopen.
--  3) Views (incl. materialized views) worden overgeslagen — daar werkt RLS niet op.
--
-- Veilig om meerdere keren te draaien.

-- Optioneel: forceer RLS ook voor de table owner (handig in prod).
-- Zet op `true` als je dat wilt afdwingen. Standaard `false` om huidige
-- service_role / owner-flows niet te breken.
do $$
declare
  v_force_rls boolean := false;
  r record;
  has_policy boolean;
begin
  for r in
    select c.relname as table_name
    from pg_class c
    join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public'
      and c.relkind = 'r' -- alleen 'ordinary' tables
      and c.relname not like 'pg_%'
      and c.relname not like 'sql_%'
    order by c.relname
  loop
    -- 1) RLS aanzetten
    execute format('alter table public.%I enable row level security', r.table_name);

    if v_force_rls then
      execute format('alter table public.%I force row level security', r.table_name);
    end if;

    -- 2) Heeft deze tabel al een policy?
    select exists (
      select 1
      from pg_policies p
      where p.schemaname = 'public'
        and p.tablename  = r.table_name
    ) into has_policy;

    -- 3) Zo niet → minimale read-only policy voor authenticated users
    if not has_policy then
      execute format(
        'create policy %I on public.%I for select to authenticated using (true)',
        r.table_name || '_select_authenticated',
        r.table_name
      );
      raise notice 'RLS aan + default select-policy toegevoegd op public.%', r.table_name;
    else
      raise notice 'RLS aan op public.% (bestaande policies behouden)', r.table_name;
    end if;
  end loop;
end $$;

-- Controle: laat zien welke tabellen nu RLS aan hebben en hoeveel policies erop staan.
select
  c.relname                                            as table_name,
  c.relrowsecurity                                     as rls_enabled,
  c.relforcerowsecurity                                as rls_forced,
  (select count(*) from pg_policies p
    where p.schemaname = 'public' and p.tablename = c.relname) as policy_count
from pg_class c
join pg_namespace n on n.oid = c.relnamespace
where n.nspname = 'public'
  and c.relkind = 'r'
order by c.relname;
