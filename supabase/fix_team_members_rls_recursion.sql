-- Fix: infinite recursion in RLS policy op team_members
-- De policy verwees naar team_members in een subquery, waardoor RLS zichzelf opnieuw aanriep.
-- Oplossing: SECURITY DEFINER-functie die als table owner leest (geen RLS in de inner query).
-- Uitvoeren in Supabase SQL Editor.

create or replace function public.is_coach_or_trainer_for_team(p_team_id bigint)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.team_members
    where profile_id = auth.uid()
      and team_id = p_team_id
      and lower(coalesce(role, '')) in ('trainer', 'coach')
  );
$$;

drop policy if exists "team_members_select_own_or_manage" on public.team_members;
create policy "team_members_select_own_or_manage"
  on public.team_members for select to authenticated
  using (
    profile_id = auth.uid()
    or coalesce(public.is_global_admin(), false) is true
    or public.is_coach_or_trainer_for_team(team_id)
  );
