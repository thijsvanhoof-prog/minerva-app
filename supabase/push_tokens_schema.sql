-- Tabel voor FCM device tokens (Firebase push)
-- Uitvoeren in Supabase SQL Editor wanneer je overstapt op Firebase; zie docs/NOTIFICATIES_FIREBASE.md

create table if not exists public.push_tokens (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  token text not null,
  platform text not null check (platform in ('ios', 'android')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(user_id, token)
);

create index if not exists idx_push_tokens_user_id on public.push_tokens(user_id);

alter table public.push_tokens enable row level security;

drop policy if exists "push_tokens_select_own" on public.push_tokens;
create policy "push_tokens_select_own"
  on public.push_tokens for select to authenticated using (auth.uid() = user_id);

drop policy if exists "push_tokens_insert_own" on public.push_tokens;
create policy "push_tokens_insert_own"
  on public.push_tokens for insert to authenticated with check (auth.uid() = user_id);

drop policy if exists "push_tokens_delete_own" on public.push_tokens;
create policy "push_tokens_delete_own"
  on public.push_tokens for delete to authenticated using (auth.uid() = user_id);

-- Voorkeur "meldingen aan/uit" per gebruiker
create table if not exists public.notification_preferences (
  user_id uuid primary key references auth.users(id) on delete cascade,
  notify_enabled boolean not null default true,
  updated_at timestamptz not null default now()
);

alter table public.notification_preferences enable row level security;

drop policy if exists "notification_preferences_select_own" on public.notification_preferences;
create policy "notification_preferences_select_own"
  on public.notification_preferences for select to authenticated using (auth.uid() = user_id);

drop policy if exists "notification_preferences_insert_own" on public.notification_preferences;
create policy "notification_preferences_insert_own"
  on public.notification_preferences for insert to authenticated with check (auth.uid() = user_id);

drop policy if exists "notification_preferences_update_own" on public.notification_preferences;
create policy "notification_preferences_update_own"
  on public.notification_preferences for update to authenticated using (auth.uid() = user_id) with check (auth.uid() = user_id);

-- Edge Function: gebruik service_role key om push_tokens + notification_preferences te lezen voor versturen.
