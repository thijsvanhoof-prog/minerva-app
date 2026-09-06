-- Betrouwbare attendance-weergave voor spelers, trainers/coaches en ouders.
--
-- De app gebruikt deze SECURITY DEFINER RPC zodat RLS op attendance,
-- sessions of team_members niet per account een onvolledige lijst oplevert.
-- Alleen trainingen van teams die de ingelogde gebruiker werkelijk mag zien
-- worden teruggegeven.
--
-- Run in Supabase -> SQL Editor.

create or replace function public.get_visible_training_attendance(
  p_session_ids bigint[]
)
returns table (
  session_id bigint,
  person_id uuid,
  status text
)
language sql
stable
security definer
set search_path = public, auth
as $$
  select
    a.session_id::bigint,
    a.person_id,
    a.status::text
  from public.attendance a
  join public.sessions s
    on s.session_id = a.session_id
  where auth.uid() is not null
    and a.session_id::bigint = any(coalesce(p_session_ids, '{}'::bigint[]))
    and s.session_type = 'training'
    and (
      coalesce(public.is_global_admin(), false)
      or exists (
        select 1
        from public.team_members viewer
        where viewer.team_id = s.team_id
          and viewer.profile_id = auth.uid()
      )
      or exists (
        select 1
        from public.account_links link
        join public.team_members child_member
          on child_member.profile_id = link.child_id
         and child_member.team_id = s.team_id
        where link.parent_id = auth.uid()
      )
    )
  order by a.session_id, a.person_id;
$$;

revoke all on function public.get_visible_training_attendance(bigint[])
  from public;
grant execute on function public.get_visible_training_attendance(bigint[])
  to authenticated;

select pg_notify('pgrst', 'reload schema');
