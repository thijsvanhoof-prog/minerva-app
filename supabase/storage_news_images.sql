-- Storage-bucket voor nieuwsfoto's (Foto uit album)
-- Gratis plan: 1 GB opslag voor bestanden; dit bucket gebruikt daarvan een deel.
--
-- LEGACY / INITIELE SETUP — niet op een live project her-runnen zonder de fix-scripts.
-- Dit script maakt een brede upload-policy aan (alleen bucket_id-check). Dat is niet het
-- gewenste eindbeeld. Voer na dit script altijd uit:
--   1. fix_news_images_storage_upload_ownership.sql  — upload alleen naar {auth.uid()}/news/...
--   2. fix_news_images_storage_update_delete_policies.sql — update/delete alleen contentmanagers
--
-- Padconventie (app + upload-policy): {auth.uid()}/news/{fileName}
-- Oude objecten onder news/... blijven leesbaar via public read; geen migratie nodig.
--
-- Stap 1: Maak de bucket aan in Supabase Dashboard:
--   Storage → New bucket → Name: news-images → Public bucket: AAN → Create.
--
-- Stap 2: Voer onderstaand beleid uit in SQL Editor (basis: public read + brede upload).

-- Iedereen mag afbeeldingen bekijken (public bucket).
drop policy if exists "news-images public read" on storage.objects;
create policy "news-images public read"
on storage.objects for select
using (bucket_id = 'news-images');

-- Brede upload (legacy setup). Vervang via fix_news_images_storage_upload_ownership.sql.
drop policy if exists "news-images authenticated upload" on storage.objects;
create policy "news-images authenticated upload"
on storage.objects for insert
to authenticated
with check (bucket_id = 'news-images');

-- Update/delete: niet hier (te breed). Voer uit:
--   supabase/fix_news_images_storage_update_delete_policies.sql
