-- Maakt meerdere ouder/verzorger-accounts per kind expliciet mogelijk en
-- verstevigt de eenmalige koppelcode-flow. Veilig om opnieuw uit te voeren.

-- Oudere schema's kunnen nog een unieke constraint of index op alleen parent_id
-- of alleen child_id bevatten. De juiste uniciteit is uitsluitend het paar
-- (parent_id, child_id), zodat de relatie many-to-many is.
do $$
declare
  item record;
begin
  for item in
    select con.conname
    from pg_constraint con
    where con.conrelid = 'public.account_links'::regclass
      and con.contype in ('p', 'u')
      and cardinality(con.conkey) = 1
      and exists (
        select 1
        from pg_attribute att
        where att.attrelid = con.conrelid
          and att.attnum = any(con.conkey)
          and att.attname in ('parent_id', 'child_id')
      )
  loop
    execute format(
      'alter table public.account_links drop constraint %I',
      item.conname
    );
  end loop;

  for item in
    select idx.relname as index_name
    from pg_index ind
    join pg_class tbl on tbl.oid = ind.indrelid
    join pg_namespace ns on ns.oid = tbl.relnamespace
    join pg_class idx on idx.oid = ind.indexrelid
    where ns.nspname = 'public'
      and tbl.relname = 'account_links'
      and ind.indisunique
      and not ind.indisprimary
      and ind.indnkeyatts = 1
      and exists (
        select 1
        from unnest(ind.indkey) with ordinality as key_column(attnum, ordinality)
        join pg_attribute att
          on att.attrelid = ind.indrelid
         and att.attnum = key_column.attnum
        where key_column.ordinality = 1
          and att.attname in ('parent_id', 'child_id')
      )
      and not exists (
        select 1 from pg_constraint con where con.conindid = ind.indexrelid
      )
  loop
    execute format('drop index public.%I', item.index_name);
  end loop;
end $$;

-- Deze index ondersteunt ON CONFLICT (parent_id, child_id) en voorkomt alleen
-- dat exact dezelfde koppeling dubbel wordt opgeslagen.
create unique index if not exists account_links_parent_child_unique
on public.account_links (parent_id, child_id);

create or replace function public.create_link_code(p_is_parent boolean)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  uid uuid := auth.uid();
  code text;
  expires timestamptz := now() + interval '15 minutes';
  attempt integer;
begin
  if uid is null then
    raise exception 'Not authenticated';
  end if;

  delete from public.account_link_codes where profile_id = uid;

  for attempt in 1..10 loop
    code := upper(substring(md5(random()::text || clock_timestamp()::text) from 1 for 6));
    begin
      insert into public.account_link_codes (code, profile_id, is_parent, expires_at)
      values (code, uid, p_is_parent, expires);
      exit;
    exception when unique_violation then
      code := null;
    end;
  end loop;

  if code is null then
    raise exception 'Kon geen unieke koppelcode maken. Probeer het opnieuw.';
  end if;

  return jsonb_build_object(
    'code', code,
    'expires_at', expires,
    'is_parent', p_is_parent
  );
end;
$$;

create or replace function public.consume_link_code(p_code text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  code_row public.account_link_codes%rowtype;
  parent_profile_id uuid;
  child_profile_id uuid;
begin
  if auth.uid() is null then
    raise exception 'Not authenticated';
  end if;

  p_code := nullif(trim(upper(p_code)), '');
  if p_code is null or p_code !~ '^[0-9A-F]{6}$' then
    raise exception 'Ongeldige code';
  end if;

  select * into code_row
  from public.account_link_codes
  where code = p_code
  for update;

  if not found then
    raise exception 'Code niet gevonden. Controleer de code of vraag een nieuwe aan.';
  end if;

  if code_row.expires_at < now() then
    delete from public.account_link_codes where code = p_code;
    raise exception 'Deze code is verlopen. Vraag een nieuwe code aan.';
  end if;

  if code_row.profile_id = auth.uid() then
    delete from public.account_link_codes where code = p_code;
    raise exception 'Je kunt geen account met jezelf koppelen.';
  end if;

  if code_row.is_parent then
    parent_profile_id := code_row.profile_id;
    child_profile_id := auth.uid();
  else
    parent_profile_id := auth.uid();
    child_profile_id := code_row.profile_id;
  end if;

  insert into public.account_links (parent_id, child_id)
  values (parent_profile_id, child_profile_id)
  on conflict (parent_id, child_id) do nothing;

  delete from public.account_link_codes where code = p_code;

  return jsonb_build_object(
    'success', true,
    'linked_as', case when code_row.is_parent then 'child' else 'parent' end
  );
end;
$$;

revoke all on function public.create_link_code(boolean) from public, anon;
revoke all on function public.consume_link_code(text) from public, anon;
grant execute on function public.create_link_code(boolean) to authenticated;
grant execute on function public.consume_link_code(text) to authenticated;
