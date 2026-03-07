-- Diagnostiek: zie of jij bestuur bent en of de content-rechten kloppen.
-- Voer uit in Supabase → SQL Editor (ingelogd als de gebruiker die je wilt controleren).
-- 1) Huidige gebruiker en rechten
select
  auth.uid() as profile_id,
  public.is_global_admin() as is_global_admin,
  public.is_bestuur() as is_bestuur,
  public.can_manage_home_news() as can_manage_news,
  public.can_manage_home_agenda() as can_manage_agenda;

-- 2) Jouw commissies (uit committee_members)
select cm.committee_name, cm.profile_id
from public.committee_members cm
where cm.profile_id = auth.uid()
order by cm.committee_name;
