-- Deletes the currently authenticated user (self-service account deletion).
--
-- Run this in Supabase SQL Editor (na cascade_delete_user_data.sql).
-- After this, the app can call: supabase.rpc('delete_my_account')
--
-- Verwijdert je account overal: commissies, teams, aanwezigheid, agenda-RSVPs,
-- taken, account-koppelingen, push-tokens, profiel en auth (via _cascade_delete_user_data).

create or replace function public.delete_my_account()
returns void
language plpgsql
security definer
set search_path = public, auth
as $$
begin
  if auth.uid() is null then
    raise exception 'Not authenticated';
  end if;

  perform public._cascade_delete_user_data(auth.uid());
end;
$$;

revoke all on function public.delete_my_account() from public;
grant execute on function public.delete_my_account() to authenticated;

