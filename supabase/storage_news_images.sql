-- Storage-bucket voor nieuwsfoto's (Foto uit album)
-- Gratis plan: 1 GB opslag voor bestanden; dit bucket gebruikt daarvan een deel.
--
-- Stap 1: Maak de bucket aan in Supabase Dashboard:
--   Storage → New bucket → Name: news-images → Public bucket: AAN → Create.
--
-- Stap 2: Voer onderstaand beleid uit in SQL Editor (zodat ingelogde gebruikers kunnen uploaden).

-- Iedereen mag afbeeldingen bekijken (public bucket).
drop policy if exists "news-images public read" on storage.objects;
create policy "news-images public read"
on storage.objects for select
using (bucket_id = 'news-images');

-- Ingelogde gebruikers mogen uploaden naar news-images.
drop policy if exists "news-images authenticated upload" on storage.objects;
create policy "news-images authenticated upload"
on storage.objects for insert
to authenticated
with check (bucket_id = 'news-images');

-- Optioneel: eigen uploads verwijderen toestaan.
drop policy if exists "news-images authenticated delete own" on storage.objects;
create policy "news-images authenticated delete own"
on storage.objects for delete
to authenticated
using (bucket_id = 'news-images');
