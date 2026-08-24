-- Content-permissies als enige bron van waarheid (alleen SQL).
-- Voer uit in Supabase → SQL Editor.
-- Vereist: is_global_admin(), is_bestuur(), can_manage_home_news(), can_manage_home_agenda(), can_manage_highlights().
-- Na uitvoeren kan de app get_my_content_permissions() aanroepen en de UI op deze waarden baseren.

-- RPC: retourneert voor de ingelogde gebruiker of hij nieuws/agenda/highlights mag beheren.
-- Sluit aan op de bestaande RLS-helperfuncties (geen dubbele logica in de app).
create or replace function public.get_my_content_permissions()
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select jsonb_build_object(
    'can_manage_news',     coalesce(public.can_manage_home_news(), false),
    'can_manage_agenda',   coalesce(public.can_manage_home_agenda(), false),
    'can_manage_highlights', coalesce(public.can_manage_highlights(), false)
  );
$$;

comment on function public.get_my_content_permissions() is
  'Content-beheerrechten voor de ingelogde gebruiker (news/agenda/highlights). Gebruik voor UI; RLS handhaaft rechten op tabelniveau.';

grant execute on function public.get_my_content_permissions() to authenticated;
