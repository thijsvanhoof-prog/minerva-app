-- Beperk news-images uploads tot de map van de ingelogde gebruiker:
--   {auth.uid()}/news/{bestandsnaam}
--
-- Oude bestanden onder news/... blijven leesbaar via public read; geen migratie nodig.
-- Update/delete blijven via fix_news_images_storage_update_delete_policies.sql (content managers).
--
-- Uitvoeren in Supabase Dashboard → SQL Editor (volledige run).
-- Deploy samen met de Flutter-wijziging in home_tab.dart (_uploadNewsImage).

drop policy if exists "news-images authenticated upload" on storage.objects;

create policy "news-images authenticated upload"
  on storage.objects
  for insert
  to authenticated
  with check (
    bucket_id = 'news-images'
    and (storage.foldername(name))[1] = auth.uid()::text
    and (storage.foldername(name))[2] = 'news'
  );

select pg_notify('pgrst', 'reload schema');
