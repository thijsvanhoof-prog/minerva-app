-- Maak/werk het gastaccount bij voor toeschouwer-modus.
-- Doel:
--   email: gast@mail.com
--   wachtwoord: 1
--
-- Run dit script in Supabase -> SQL Editor met voldoende rechten.
-- LET OP: wachtwoord "1" is onveilig en alleen geschikt voor test/demo.

do $$
declare
  v_email text := 'gast@mail.com';
  v_password text := '1';
  v_user_id uuid;
  has_profile_email boolean;
begin
  -- Zoek bestaand auth-account op e-mail.
  select u.id
    into v_user_id
  from auth.users u
  where lower(u.email) = lower(v_email)
  limit 1;

  -- Maak account aan als het nog niet bestaat.
  if v_user_id is null then
    insert into auth.users (
      instance_id,
      id,
      aud,
      role,
      email,
      encrypted_password,
      email_confirmed_at,
      confirmation_sent_at,
      recovery_sent_at,
      raw_app_meta_data,
      raw_user_meta_data,
      created_at,
      updated_at
    ) values (
      '00000000-0000-0000-0000-000000000000',
      gen_random_uuid(),
      'authenticated',
      'authenticated',
      v_email,
      crypt(v_password, gen_salt('bf')),
      now(),
      now(),
      now(),
      jsonb_build_object('provider', 'email', 'providers', jsonb_build_array('email')),
      jsonb_build_object('display_name', 'Gast'),
      now(),
      now()
    )
    returning id into v_user_id;
  end if;

  -- Zorg dat wachtwoord + metadata + bevestigde mail goed staan.
  update auth.users
     set email = v_email,
         encrypted_password = crypt(v_password, gen_salt('bf')),
         email_confirmed_at = coalesce(email_confirmed_at, now()),
         raw_app_meta_data = coalesce(raw_app_meta_data, '{}'::jsonb)
           || jsonb_build_object('provider', 'email', 'providers', jsonb_build_array('email')),
         raw_user_meta_data = coalesce(raw_user_meta_data, '{}'::jsonb)
           || jsonb_build_object('display_name', 'Gast'),
         updated_at = now()
   where id = v_user_id;

  -- Zorg voor email identity record (voor GoTrue login-flow).
  insert into auth.identities (
    id,
    user_id,
    provider_id,
    identity_data,
    provider,
    last_sign_in_at,
    created_at,
    updated_at
  ) values (
    gen_random_uuid(),
    v_user_id,
    v_email,
    jsonb_build_object(
      'sub', v_user_id::text,
      'email', v_email
    ),
    'email',
    now(),
    now(),
    now()
  )
  on conflict (provider, provider_id) do update
    set user_id = excluded.user_id,
        identity_data = excluded.identity_data,
        updated_at = now();

  -- Best-effort profiel aanmaken/bijwerken (schema kan met/zonder email-kolom zijn).
  select exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'profiles'
      and column_name = 'email'
  ) into has_profile_email;

  if has_profile_email then
    execute
      'insert into public.profiles (id, display_name, email)
       values ($1, $2, $3)
       on conflict (id) do update
         set display_name = excluded.display_name,
             email = excluded.email'
      using v_user_id, 'Gast', v_email;
  else
    execute
      'insert into public.profiles (id, display_name)
       values ($1, $2)
       on conflict (id) do update
         set display_name = excluded.display_name'
      using v_user_id, 'Gast';
  end if;
end
$$;

