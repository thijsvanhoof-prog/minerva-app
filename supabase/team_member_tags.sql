-- Zelfgekozen lid-tag per account en team.
-- Voorbeelden: "aanvoerder" of "vader van Jessie".
-- De tag verandert nooit de profielnaam of de persoon op een aanwezigheidsrecord.

create table if not exists public.team_member_tags (
  profile_id uuid not null references public.profiles(id) on delete cascade,
  team_id bigint not null references public.teams(team_id) on delete cascade,
  member_tag text not null,
  updated_at timestamptz not null default now(),
  primary key (profile_id, team_id),
  constraint team_member_tags_length_check check (
    char_length(btrim(member_tag)) between 1 and 60
  )
);

alter table public.team_member_tags enable row level security;

drop policy if exists "team_member_tags_select_own" on public.team_member_tags;
create policy "team_member_tags_select_own"
on public.team_member_tags
for select
to authenticated
using (profile_id = auth.uid());

-- Schrijven gebeurt alleen via set_my_team_member_tag, zodat ook een ouder met
-- een afgeleide kind-teamkoppeling veilig een eigen tag kan instellen.
drop policy if exists "team_member_tags_no_direct_writes" on public.team_member_tags;
create policy "team_member_tags_no_direct_writes"
on public.team_member_tags
for all
to authenticated
using (false)
with check (false);

create or replace function public.get_my_team_member_tags()
returns table (
  team_id bigint,
  member_tag text
)
language sql
stable
security definer
set search_path = public
as $$
  select t.team_id, t.member_tag
  from public.team_member_tags t
  where t.profile_id = auth.uid()
  order by t.team_id;
$$;

create or replace function public.get_visible_team_member_tags(
  p_team_ids bigint[]
)
returns table (
  profile_id uuid,
  team_id bigint,
  member_tag text
)
language sql
stable
security definer
set search_path = public
as $$
  select tag.profile_id, tag.team_id, tag.member_tag
  from public.team_member_tags tag
  where tag.team_id = any(coalesce(p_team_ids, array[]::bigint[]))
    and (
      coalesce(public.is_global_admin(), false)
      or exists (
        select 1
        from public.team_members viewer_tm
        where viewer_tm.profile_id = auth.uid()
          and viewer_tm.team_id = tag.team_id
      )
      or exists (
        select 1
        from public.account_links link
        join public.team_members child_tm
          on child_tm.profile_id = link.child_id
         and child_tm.team_id = tag.team_id
        where link.parent_id = auth.uid()
      )
    )
  order by tag.team_id, tag.profile_id;
$$;

create or replace function public.set_my_team_member_tag(
  p_team_id bigint,
  p_member_tag text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_tag text := btrim(coalesce(p_member_tag, ''));
  v_has_team_access boolean;
begin
  if v_uid is null then
    raise exception 'Niet ingelogd';
  end if;

  if char_length(v_tag) > 60 then
    raise exception 'Een lid-tag mag maximaal 60 tekens bevatten';
  end if;

  select
    exists (
      select 1
      from public.team_members tm
      where tm.profile_id = v_uid
        and tm.team_id = p_team_id
    )
    or exists (
      select 1
      from public.account_links link
      join public.team_members child_tm
        on child_tm.profile_id = link.child_id
       and child_tm.team_id = p_team_id
      where link.parent_id = v_uid
    )
  into v_has_team_access;

  if not coalesce(v_has_team_access, false) then
    raise exception 'Je bent niet gekoppeld aan dit team';
  end if;

  if v_tag = '' then
    delete from public.team_member_tags
    where profile_id = v_uid
      and team_id = p_team_id;
    return;
  end if;

  insert into public.team_member_tags (profile_id, team_id, member_tag, updated_at)
  values (v_uid, p_team_id, v_tag, now())
  on conflict (profile_id, team_id)
  do update set
    member_tag = excluded.member_tag,
    updated_at = excluded.updated_at;
end;
$$;

revoke all on function public.get_my_team_member_tags() from public;
revoke all on function public.get_visible_team_member_tags(bigint[]) from public;
revoke all on function public.set_my_team_member_tag(bigint, text) from public;
grant execute on function public.get_my_team_member_tags() to authenticated;
grant execute on function public.get_visible_team_member_tags(bigint[]) to authenticated;
grant execute on function public.set_my_team_member_tag(bigint, text) to authenticated;

notify pgrst, 'reload schema';
