-- Nieuws: foto's en linkjes bij nieuwsberichten
-- Voer uit in Supabase → SQL Editor na home_news_minimal.sql.
-- image_urls: array van afbeeldings-URL's (Supabase Storage of externe URLs)
-- links: array van objecten { "url": "...", "label": "..." }
--
-- Storage news-images: nieuwe uploads horen onder {auth.uid()}/news/{fileName}.
-- Oude objecten onder news/... blijven leesbaar via public read; geen migratie nodig.
-- Na dit script (of storage_news_images.sql) uitvoeren:
--   fix_news_images_storage_upload_ownership.sql — upload beperken tot eigen user-map
--   fix_news_images_storage_update_delete_policies.sql — update/delete alleen contentmanagers

alter table public.home_news
  add column if not exists image_urls jsonb not null default '[]';

alter table public.home_news
  add column if not exists links jsonb not null default '[]';

-- Storage bucket voor geüploade nieuwsfoto's.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'news-images',
  'news-images',
  true,
  5242880,
  array['image/jpeg','image/png','image/webp','image/gif']
)
on conflict (id) do nothing;

-- Iedereen mag afbeeldingen bekijken.
do $$
begin
  if not exists (
    select 1 from pg_policies
    where schemaname = 'storage'
      and tablename = 'objects'
      and policyname = 'news-images public read'
  ) then
    create policy "news-images public read"
      on storage.objects for select
      using (bucket_id = 'news-images');
  end if;
end $$;

-- Brede upload (initiële setup). Beperk via fix_news_images_storage_upload_ownership.sql.
do $$
begin
  if not exists (
    select 1 from pg_policies
    where schemaname = 'storage'
      and tablename = 'objects'
      and policyname = 'news-images authenticated upload'
  ) then
    create policy "news-images authenticated upload"
      on storage.objects for insert
      to authenticated
      with check (bucket_id = 'news-images');
  end if;
end $$;

-- Update/delete: alleen contentmanagers — niet elke ingelogde user.
-- Zie: supabase/fix_news_images_storage_update_delete_policies.sql

select pg_notify('pgrst', 'reload schema');
