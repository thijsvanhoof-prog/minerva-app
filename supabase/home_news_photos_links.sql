-- Nieuws: foto's en linkjes bij nieuwsberichten
-- Voer uit in Supabase → SQL Editor na home_news_minimal.sql.
-- image_urls: array van afbeeldings-URL's (Supabase Storage of externe URLs)
-- links: array van objecten { "url": "...", "label": "..." }

alter table public.home_news
  add column if not exists image_urls jsonb not null default '[]';

alter table public.home_news
  add column if not exists links jsonb not null default '[]';

-- Optioneel: Storage bucket voor geüploade nieuwsfoto's (voer uit in SQL Editor)
-- Daarna in Dashboard → Storage: bucket "news-images" aanmaken als public, of onderstaande gebruiken.
-- insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
-- values (
--   'news-images',
--   'news-images',
--   true,
--   5242880,
--   array['image/jpeg','image/png','image/webp','image/gif']
-- )
-- on conflict (id) do nothing;
-- create policy "news-images public read" on storage.objects for select using (bucket_id = 'news-images');
-- create policy "news-images authenticated upload" on storage.objects for insert to authenticated with check (bucket_id = 'news-images');
