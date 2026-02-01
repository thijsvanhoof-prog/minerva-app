-- Deletes the currently authenticated user (self-service account deletion).
--
-- Run this in Supabase SQL Editor.
-- After this, the app can call: supabase.rpc('delete_my_account')
--
-- Notes:
-- - This removes the user from auth.users. If you have a public.profiles row with a FK
--   to auth.users(id) with ON DELETE CASCADE, it will be removed automatically.
-- - If you have additional per-user tables without cascading FKs, add deletes below.

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

  -- Best-effort cleanup of public profile row (if you have one).
  delete from public.profiles
  where id = auth.uid();

  -- Delete auth user (self).
  delete from auth.users
  where id = auth.uid();
end;
$$;

revoke all on function public.delete_my_account() from public;
grant execute on function public.delete_my_account() to authenticated;

