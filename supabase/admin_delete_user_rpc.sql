-- Admin-only: delete another user's account.
--
-- Run this in Supabase SQL Editor.
-- App can call: supabase.rpc('admin_delete_user', params: { 'target_user_id': '<uuid>' })
--
-- Security:
-- - Uses SECURITY DEFINER so it can delete from auth.users
-- - Explicitly checks public.is_global_admin() for the caller

create or replace function public.admin_delete_user(target_user_id uuid)
returns void
language plpgsql
security definer
set search_path = public, auth
as $$
begin
  if auth.uid() is null then
    raise exception 'Not authenticated';
  end if;

  if target_user_id is null then
    raise exception 'Missing target_user_id';
  end if;

  if target_user_id = auth.uid() then
    raise exception 'Use delete_my_account for self deletion';
  end if;

  if coalesce(public.is_global_admin(), false) is not true then
    raise exception 'Forbidden';
  end if;

  -- Best-effort cleanup of public profile row (if you have one).
  delete from public.profiles
  where id = target_user_id;

  -- Delete auth user (admin action).
  delete from auth.users
  where id = target_user_id;
end;
$$;

revoke all on function public.admin_delete_user(uuid) from public;
grant execute on function public.admin_delete_user(uuid) to authenticated;

