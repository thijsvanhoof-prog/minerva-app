-- Add "function" column to committee_members so InfoTab can store roles.
--
-- Run this in Supabase SQL Editor.

alter table public.committee_members
  add column if not exists function text null;

-- Optional: index for quick lookups (usually not needed, but cheap)
create index if not exists idx_committee_members_function
  on public.committee_members(function);

-- RLS note:
-- If your committee_members table has RLS enabled and updates are blocked,
-- either add a policy for bestuur/global admins, or update via an RPC.
-- This repo already includes a robust UI-side fallback and an RPC to read names:
-- `get_committee_members_with_names()`.

