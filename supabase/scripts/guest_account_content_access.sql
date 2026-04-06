-- Geef het gastaccount toegang tot Nieuws, Agenda en Contacten.
--
-- Doelaccount:
--   gast@mail.com
--
-- Run dit script in Supabase -> SQL Editor.
-- Idempotent: veilig opnieuw uit te voeren.

-- Helper: true als huidige sessie het gastaccount is.
create or replace function public.is_guest_user()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select lower(coalesce(auth.jwt() ->> 'email', '')) = 'gast@mail.com';
$$;

grant execute on function public.is_guest_user() to authenticated, anon;

-- Helper voor leesrechten op publieke app-content.
-- Toegestaan voor:
-- - alle authenticated users (incl. gast@mail.com)
-- - anon sessies (fallback)
create or replace function public.can_read_public_content()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select auth.role() in ('authenticated', 'anon');
$$;

grant execute on function public.can_read_public_content() to authenticated, anon;

-- ----------------------------
-- NIEUWS
-- ----------------------------
grant select on table public.home_news to authenticated, anon;

drop policy if exists "home_news_select_auth" on public.home_news;
drop policy if exists "home_news_select_public" on public.home_news;
create policy "home_news_select_public"
on public.home_news
for select
to authenticated, anon
using (public.can_read_public_content());

-- ----------------------------
-- AGENDA
-- ----------------------------
grant select on table public.home_agenda to authenticated, anon;

drop policy if exists "home_agenda_select_auth" on public.home_agenda;
drop policy if exists "home_agenda_select_public" on public.home_agenda;
create policy "home_agenda_select_public"
on public.home_agenda
for select
to authenticated, anon
using (public.can_read_public_content());

-- ----------------------------
-- CONTACTEN (commissieleden + email)
-- ----------------------------
-- Vervang de RPC zodat die publieke content-read gebruikt.
drop function if exists public.get_committee_members_with_names();

create or replace function public.get_committee_members_with_names()
returns table (
  committee_name text,
  profile_id uuid,
  display_name text,
  function text,
  email text
)
language sql
stable
security definer
set search_path = public
as $$
  select
    cm.committee_name::text,
    cm.profile_id,
    coalesce(
      p.display_name,
      to_jsonb(p)->>'full_name',
      to_jsonb(p)->>'name',
      p.email,
      ''
    )::text as display_name,
    coalesce(
      to_jsonb(cm)->>'function',
      to_jsonb(cm)->>'role',
      to_jsonb(cm)->>'title'
    )::text as function,
    nullif(trim(coalesce(
      p.email,
      to_jsonb(cm)->>'email',
      to_jsonb(cm)->>'contact_email',
      to_jsonb(cm)->>'mail'
    )), '')::text as email
  from public.committee_members cm
  left join public.profiles p on p.id = cm.profile_id
  where public.can_read_public_content();
$$;

grant execute on function public.get_committee_members_with_names() to authenticated, anon;

