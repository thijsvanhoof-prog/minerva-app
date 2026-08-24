-- Maak een gebruiker global admin.
-- Voer uit in Supabase → SQL Editor (met service role of als bestaande admin).
-- Profile ID: ce0826fa-6d7b-4efe-9132-5c320b49ae77

-- Tabel voor globale admins (als die nog niet bestaat)
create table if not exists public.global_admins (
  id uuid not null primary key references auth.users(id) on delete cascade
);

alter table public.global_admins enable row level security;

-- Gebruikers mogen alleen zien of zij zelf in de lijst staan (voor weergave); is_global_admin() leest via security definer.
drop policy if exists "global_admins_select_own" on public.global_admins;
create policy "global_admins_select_own"
  on public.global_admins for select to authenticated
  using (auth.uid() = id);

-- Functie is_global_admin: true als de ingelogde gebruiker in global_admins staat.
-- (Als je een andere definitie hebt, pas dan alleen het INSERT-blok hieronder toe.)
create or replace function public.is_global_admin()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.global_admins where id = auth.uid()
  );
$$;

grant execute on function public.is_global_admin() to authenticated;

-- Voeg deze gebruiker toe als global admin
insert into public.global_admins (id)
values ('ce0826fa-6d7b-4efe-9132-5c320b49ae77'::uuid)
on conflict (id) do nothing;
