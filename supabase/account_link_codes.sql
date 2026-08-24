-- Koppelen van accounts volledig in de app (geen e-mail).
-- Eén account genereert een korte code, het andere account voert de code in en bevestigt.
--
-- Run in Supabase SQL Editor. Vereist: account_links (account_link_requests_schema.sql).

create table if not exists public.account_link_codes (
  code text primary key,
  profile_id uuid not null references public.profiles(id) on delete cascade,
  is_parent boolean not null,
  created_at timestamptz not null default now(),
  expires_at timestamptz not null
);

comment on table public.account_link_codes is 'Eenmalige koppelcodes; geldig kort (bijv. 15 min).';

alter table public.account_link_codes enable row level security;

-- Geen directe client-toegang; alleen via RPC.
drop policy if exists "account_link_codes_no_direct" on public.account_link_codes;
create policy "account_link_codes_no_direct"
on public.account_link_codes
for all
to authenticated
using (false)
with check (false);

-- Genereer een koppelcode. Aanroeper kiest of hij/zij ouder is (is_parent) of het kind.
-- Code is 6 tekens (hoofdletters+cijfers), geldig 15 minuten.
create or replace function public.create_link_code(p_is_parent boolean)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  uid uuid;
  code text;
  expires timestamptz;
begin
  uid := auth.uid();
  if uid is null then
    raise exception 'Not authenticated';
  end if;

  -- 6 tekens [0-9A-F] zonder pgcrypto (md5 + random zijn standaard in PostgreSQL)
  code := upper(substring(md5(random()::text || clock_timestamp()::text) from 1 for 6));

  expires := now() + interval '15 minutes';

  insert into public.account_link_codes (code, profile_id, is_parent, expires_at)
  values (code, uid, p_is_parent, expires);

  return jsonb_build_object(
    'code', code,
    'expires_at', expires,
    'is_parent', p_is_parent
  );
end;
$$;

-- Voer een koppelcode in om de koppeling te voltooien. Aanroeper wordt gekoppeld aan de maker van de code.
create or replace function public.consume_link_code(p_code text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  other_id uuid;
  creator_is_parent boolean;
  row record;
  v_parent_id uuid;
  v_child_id uuid;
begin
  if auth.uid() is null then
    raise exception 'Not authenticated';
  end if;

  p_code := nullif(trim(upper(p_code)), '');
  if p_code is null or length(p_code) < 4 then
    raise exception 'Ongeldige code';
  end if;

  select c.profile_id, c.is_parent, c.expires_at
  into row
  from public.account_link_codes c
  where c.code = p_code
  limit 1;

  if row.profile_id is null then
    raise exception 'Code niet gevonden. Controleer de code of vraag een nieuwe aan.';
  end if;

  if row.expires_at < now() then
    delete from public.account_link_codes where code = p_code;
    raise exception 'Deze code is verlopen. Vraag een nieuwe code aan.';
  end if;

  other_id := row.profile_id;
  creator_is_parent := row.is_parent;

  if other_id = auth.uid() then
    delete from public.account_link_codes where code = p_code;
    raise exception 'Je kunt geen account met jezelf koppelen.';
  end if;

  if creator_is_parent then
    v_parent_id := other_id;
    v_child_id := auth.uid();
  else
    v_parent_id := auth.uid();
    v_child_id := other_id;
  end if;

  insert into public.account_links (parent_id, child_id)
  values (v_parent_id, v_child_id)
  on conflict (parent_id, child_id) do nothing;

  delete from public.account_link_codes where code = p_code;

  return jsonb_build_object(
    'success', true,
    'linked_as', case when creator_is_parent then 'child' else 'parent' end
  );
end;
$$;

grant execute on function public.create_link_code(boolean) to authenticated;
grant execute on function public.consume_link_code(text) to authenticated;

-- Opruimen van verlopen codes (optioneel, kan ook bij consume).
create or replace function public.clean_expired_link_codes()
returns void
language sql
security definer
set search_path = public
as $$
  delete from public.account_link_codes where expires_at < now();
$$;
grant execute on function public.clean_expired_link_codes() to authenticated;
