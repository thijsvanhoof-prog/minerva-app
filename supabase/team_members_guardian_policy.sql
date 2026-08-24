-- Ouders/verzorgers: team_members van gekoppelde kinderen mogen lezen.
-- Hierdoor ziet een ouder in de app ook de teams van het kind (naast eigen teams).
--
-- Vereiste: account_links bestaat en is_guardian_of (uit guardian_attendance_policies.sql
-- of guardian_tasks_policies.sql). Zo niet, voer die eerst uit of voeg is_guardian_of hieronder toe.
--
-- Voer uit in Supabase SQL Editor.

-- Zorg dat is_guardian_of bestaat (als guardian_attendance nog niet gedraaid is)
create or replace function public.is_guardian_of(target_profile_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.account_links l
    where l.parent_id = auth.uid()
      and l.child_id = target_profile_id
  );
$$;

grant execute on function public.is_guardian_of(uuid) to authenticated;

-- Extra SELECT-policy: ouder mag team_members rijen zien waar profile_id een gekoppeld kind is
alter table if exists public.team_members enable row level security;

drop policy if exists "team_members_select_guardian" on public.team_members;
create policy "team_members_select_guardian"
on public.team_members
for select
to authenticated
using (public.is_guardian_of(profile_id));
