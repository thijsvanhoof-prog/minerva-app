-- RLS-fix: push_tokens upsert vereist UPDATE naast INSERT.
-- Zonder deze policy faalt upsert op bestaande (user_id, token)-rijen stil of met RLS-fout.
-- Run in Supabase → SQL Editor.

drop policy if exists "push_tokens_update_own" on public.push_tokens;

create policy "push_tokens_update_own"
  on public.push_tokens
  for update
  to authenticated
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

select pg_notify('pgrst', 'reload schema');
