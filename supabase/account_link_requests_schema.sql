-- Account link requests (ouder/verzorger ↔ gekoppeld account)
--
-- Optie B: request + accept.
-- Run this in Supabase Dashboard → SQL Editor.
--
-- What you get:
-- - public.account_links: accepted links (parent_id -> child_id)
-- - public.account_link_requests: pending requests that must be accepted
-- - RPCs:
--   - request_child_link(child_email text)
--   - request_parent_link(parent_email text)
--   - get_my_linked_child_profiles()  (kept for app compatibility)
--   - get_my_pending_account_link_requests()
--   - accept_account_link_request(request_id uuid)
--   - reject_account_link_request(request_id uuid)
--
-- NOTE: This uses public.profiles.email to look up accounts. If your profiles table
-- doesn't have email, you need to adjust the lookup.

create extension if not exists pgcrypto;

-- Accepted links (parent -> child)
create table if not exists public.account_links (
  parent_id uuid not null references public.profiles(id) on delete cascade,
  child_id uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (parent_id, child_id)
);

-- Pending requests
create table if not exists public.account_link_requests (
  request_id uuid primary key default gen_random_uuid(),
  parent_id uuid not null references public.profiles(id) on delete cascade,
  child_id uuid not null references public.profiles(id) on delete cascade,
  requested_by uuid not null references public.profiles(id) on delete cascade,
  recipient_id uuid not null references public.profiles(id) on delete cascade,
  status text not null default 'pending' check (status in ('pending','accepted','rejected','cancelled')),
  created_at timestamptz not null default now(),
  responded_at timestamptz null
);

-- Only allow one pending request per pair.
create unique index if not exists account_link_requests_one_pending
on public.account_link_requests (parent_id, child_id)
where status = 'pending';

-- RLS: keep tables private; access via RPC or narrow policies.
alter table public.account_links enable row level security;
alter table public.account_link_requests enable row level security;

-- The link rows are visible to the two parties.
drop policy if exists "account_links_select_own" on public.account_links;
create policy "account_links_select_own"
on public.account_links
for select
to authenticated
using (parent_id = auth.uid() or child_id = auth.uid());

-- Requests are visible to the parties involved.
drop policy if exists "account_link_requests_select_own" on public.account_link_requests;
create policy "account_link_requests_select_own"
on public.account_link_requests
for select
to authenticated
using (requested_by = auth.uid() or recipient_id = auth.uid() or parent_id = auth.uid() or child_id = auth.uid());

-- Prevent direct writes from client; use security definer functions.
drop policy if exists "account_links_no_direct_writes" on public.account_links;
create policy "account_links_no_direct_writes"
on public.account_links
for all
to authenticated
using (false)
with check (false);

drop policy if exists "account_link_requests_no_direct_writes" on public.account_link_requests;
create policy "account_link_requests_no_direct_writes"
on public.account_link_requests
for all
to authenticated
using (false)
with check (false);

-- RPC: helper to resolve a profile by email.
create or replace function public._profile_id_by_email(target_email text)
returns uuid
language sql
stable
security definer
set search_path = public
as $$
  select p.id
  from public.profiles p
  where lower(p.email) = lower(target_email)
  limit 1;
$$;

-- RPC: parent requests to link a child (recipient is the child).
create or replace function public.request_child_link(child_email text)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  parent_user_id uuid;
  child_user_id uuid;
begin
  parent_user_id := auth.uid();
  if parent_user_id is null then
    raise exception 'Not authenticated';
  end if;

  child_user_id := public._profile_id_by_email(child_email);
  if child_user_id is null then
    raise exception 'Child account not found';
  end if;
  if child_user_id = parent_user_id then
    raise exception 'Cannot link to self';
  end if;

  insert into public.account_link_requests(parent_id, child_id, requested_by, recipient_id)
  values (parent_user_id, child_user_id, parent_user_id, child_user_id)
  on conflict do nothing;
end;
$$;

-- RPC: child requests that the OTHER account becomes the parent (recipient is the parent).
create or replace function public.request_parent_link(parent_email text)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  parent_user_id uuid;
  child_user_id uuid;
begin
  child_user_id := auth.uid();
  if child_user_id is null then
    raise exception 'Not authenticated';
  end if;

  parent_user_id := public._profile_id_by_email(parent_email);
  if parent_user_id is null then
    raise exception 'Parent account not found';
  end if;
  if parent_user_id = child_user_id then
    raise exception 'Cannot link to self';
  end if;

  insert into public.account_link_requests(parent_id, child_id, requested_by, recipient_id)
  values (parent_user_id, child_user_id, child_user_id, parent_user_id)
  on conflict do nothing;
end;
$$;

-- RPC: list linked child profiles for the logged-in parent.
-- (Kept for app compatibility; "child" can be any linked account.)
create or replace function public.get_my_linked_child_profiles()
returns table (
  profile_id uuid,
  display_name text
)
language sql
stable
security definer
set search_path = public
as $$
  select
    p.id as profile_id,
    coalesce(p.display_name, p.email, '')::text as display_name
  from public.account_links l
  join public.profiles p on p.id = l.child_id
  where l.parent_id = auth.uid();
$$;

-- RPC: list pending requests the current user must accept/reject.
create or replace function public.get_my_pending_account_link_requests()
returns table (
  request_id uuid,
  role text, -- 'parent' or 'child' from the perspective of the current user
  other_profile_id uuid,
  other_display_name text
)
language sql
stable
security definer
set search_path = public
as $$
  select
    r.request_id,
    case
      when r.recipient_id = auth.uid() and r.parent_id = auth.uid() then 'parent'
      when r.recipient_id = auth.uid() and r.child_id = auth.uid() then 'child'
      else 'unknown'
    end as role,
    case
      when r.recipient_id = auth.uid() and r.parent_id = auth.uid() then r.child_id
      when r.recipient_id = auth.uid() and r.child_id = auth.uid() then r.parent_id
      else null
    end as other_profile_id,
    coalesce(p.display_name, p.email, '')::text as other_display_name
  from public.account_link_requests r
  left join public.profiles p on p.id = (
    case
      when r.recipient_id = auth.uid() and r.parent_id = auth.uid() then r.child_id
      when r.recipient_id = auth.uid() and r.child_id = auth.uid() then r.parent_id
      else null
    end
  )
  where r.recipient_id = auth.uid()
    and r.status = 'pending'
  order by r.created_at desc;
$$;

create or replace function public.accept_account_link_request(request_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  r public.account_link_requests%rowtype;
begin
  select * into r
  from public.account_link_requests
  where account_link_requests.request_id = accept_account_link_request.request_id
  limit 1;

  if r.request_id is null then
    raise exception 'Request not found';
  end if;

  if r.recipient_id <> auth.uid() then
    raise exception 'Not allowed';
  end if;

  if r.status <> 'pending' then
    return;
  end if;

  insert into public.account_links(parent_id, child_id)
  values (r.parent_id, r.child_id)
  on conflict do nothing;

  update public.account_link_requests
  set status = 'accepted',
      responded_at = now()
  where account_link_requests.request_id = r.request_id;
end;
$$;

create or replace function public.reject_account_link_request(request_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  r public.account_link_requests%rowtype;
begin
  select * into r
  from public.account_link_requests
  where account_link_requests.request_id = reject_account_link_request.request_id
  limit 1;

  if r.request_id is null then
    raise exception 'Request not found';
  end if;

  if r.recipient_id <> auth.uid() then
    raise exception 'Not allowed';
  end if;

  if r.status <> 'pending' then
    return;
  end if;

  update public.account_link_requests
  set status = 'rejected',
      responded_at = now()
  where account_link_requests.request_id = r.request_id;
end;
$$;

-- RPC: parent can unlink a linked child.
create or replace function public.unlink_child_account(child_profile_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then
    raise exception 'Not authenticated';
  end if;

  if child_profile_id is null then
    raise exception 'Child profile id is required';
  end if;

  delete from public.account_links
  where parent_id = auth.uid()
    and child_id = child_profile_id;
end;
$$;

grant execute on function public.request_child_link(text) to authenticated;
grant execute on function public.request_parent_link(text) to authenticated;
grant execute on function public.get_my_linked_child_profiles() to authenticated;
grant execute on function public.get_my_pending_account_link_requests() to authenticated;
grant execute on function public.accept_account_link_request(uuid) to authenticated;
grant execute on function public.reject_account_link_request(uuid) to authenticated;
grant execute on function public.unlink_child_account(uuid) to authenticated;

