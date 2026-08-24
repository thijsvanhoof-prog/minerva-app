-- Voeg de ingelogde gebruiker toe als bestuurslid.
-- Alleen uitvoerbaar als je al global admin bent (anders: laat een admin dit voor je runnen of gebruik Service Role in Dashboard).

insert into public.committee_members (profile_id, committee_name)
select auth.uid(), 'bestuur'
where not exists (
  select 1 from public.committee_members cm
  where cm.profile_id = auth.uid() and lower(trim(cm.committee_name)) = 'bestuur'
);
