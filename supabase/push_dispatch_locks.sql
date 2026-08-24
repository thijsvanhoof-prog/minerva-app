-- Server-side dedupe/cooldown voor push-notificaties.
-- Uitvoeren in Supabase SQL Editor.

create table if not exists public.push_dispatch_locks (
  dedupe_key text primary key,
  last_sent_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists idx_push_dispatch_locks_last_sent_at
  on public.push_dispatch_locks(last_sent_at desc);

create or replace function public.try_acquire_push_dispatch_lock(
  p_dedupe_key text,
  p_cooldown_seconds integer default 0
)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_key text := btrim(coalesce(p_dedupe_key, ''));
  v_cooldown integer := greatest(coalesce(p_cooldown_seconds, 0), 0);
begin
  if v_key = '' then
    return true;
  end if;

  insert into public.push_dispatch_locks (dedupe_key, last_sent_at, updated_at)
  values (v_key, now(), now())
  on conflict (dedupe_key) do update
    set last_sent_at = excluded.last_sent_at,
        updated_at = excluded.updated_at
    where v_cooldown = 0
       or public.push_dispatch_locks.last_sent_at <= now() - make_interval(secs => v_cooldown);

  return found;
end;
$$;

grant execute on function public.try_acquire_push_dispatch_lock(text, integer)
  to anon, authenticated, service_role;
