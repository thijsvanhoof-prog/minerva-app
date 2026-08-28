# Supabase SQL Deploy-Overzicht

Gebruik dit document als checklist voor live of een nieuwe Supabase-omgeving.
Voer SQL uit via **Supabase Dashboard -> SQL Editor**.

## Altijd voorzichtig met oude setup-scripts

Sommige scripts zijn basis/setup-scripts en kunnen oude, ruime policies terugzetten.
Draai ze daarom alleen bewust opnieuw en voer daarna de bijbehorende fix-scripts uit.

Belangrijkste voorbeelden:

- `supabase/storage_news_images.sql` maakt brede upload tijdelijk mogelijk.
  Draai daarna altijd `supabase/fix_news_images_storage_upload_ownership.sql`.
- `supabase/match_availability_minimal.sql` en `supabase/match_availability_schema.sql`
  moeten `playing`, `not_playing`, `coach` en `afgemeld` toestaan.
  Dit is nu in de repo gecorrigeerd.
- `supabase/enable_rls_all_tables.sql` heeft brede impact.
  Niet draaien als gewone release-stap; eerst apart reviewen/staging-testen.

## Release 4.4.x: aanbevolen volgorde

### 1. Basis helpers en rollen

Voer uit als deze nog niet live staan:

1. `supabase/scripts/add_global_admin.sql`
2. `supabase/force_content_rls_bestuur.sql`
3. `supabase/profile_display_names_rpc.sql`
4. `supabase/get_my_team_ids.sql`
5. `supabase/get_my_committees.sql`

### 2. Teams, trainingen en aanwezigheid

1. `supabase/teams_schema.sql`
2. `supabase/teams_rls.sql`
3. `supabase/teams_nevobo_sync.sql`
4. `supabase/team_members_fix_role_constraint.sql`
5. `supabase/team_members_tc_manage.sql`
6. `supabase/guardian_attendance_policies.sql`
7. `supabase/team_members_guardian_policy.sql`
8. `supabase/sessions_attendance_global_admin.sql`
9. `supabase/get_visible_team_member_profile_ids.sql`

Waarom stap 9:
gewone spelers/trainingsleden mogen niet altijd rechtstreeks alle `team_members`
lezen via RLS. Deze RPC geeft alleen leden terug van teams die de gebruiker zelf
mag zien en wordt gebruikt voor **Niet gereageerd** bij trainingen en wedstrijden.

### 3. Wedstrijden

1. `supabase/match_availability_minimal.sql`
2. `supabase/match_availability_fix_status_constraint.sql`
3. `supabase/match_cancellations_minimal.sql`
4. `supabase/nevobo_home_matches_schema.sql`

Let op:
`match_availability` moet deze vier statussen toestaan:

- `playing`
- `not_playing`
- `coach`
- `afgemeld`

### 4. Taken en wedstrijdzaken

1. `supabase/club_tasks_schema.sql`
2. `supabase/guardian_tasks_policies.sql`
3. `supabase/sheet_home_matches.sql`
4. `supabase/get_user_ids_for_team_notifications.sql`
5. `supabase/push_dispatch_locks.sql`

### 5. Home, nieuws, highlights en agenda

1. `supabase/home_highlights_minimal.sql`
2. `supabase/home_news_minimal.sql`
3. `supabase/home_news_photos_links.sql`
4. `supabase/home_agenda_schema.sql`
5. `supabase/home_agenda_rsvp_extended.sql`
6. `supabase/home_agenda_signup_options_schema.sql`
7. `supabase/home_agenda_rls_fix.sql`
8. `supabase/fix_can_manage_home_agenda_jeugd_evenementen.sql`
9. `supabase/home_agenda_rsvps_view_committees.sql`
10. `supabase/home_agenda_rsvp_guardian_policies.sql`

### 6. News-images storage

Maak eerst in Supabase Storage een public bucket:

```text
news-images
```

Daarna:

1. `supabase/storage_news_images.sql`
2. `supabase/fix_news_images_storage_upload_ownership.sql`
3. `supabase/fix_news_images_storage_update_delete_policies.sql`

Nieuwe uploads gaan naar:

```text
{auth.uid()}/news/{fileName}
```

Oude objecten onder `news/...` blijven leesbaar via public read.

### 7. Commissies en contact

1. `supabase/committee_members_function_column.sql`
2. `supabase/committee_members_with_names.sql`
3. `supabase/fix_committee_members_with_names_auth_email.sql`
4. `supabase/committee_list_profiles_rpc.sql`
5. `supabase/get_committee_member_profile_ids.sql`
6. `supabase/scripts/committee_contact_settings.sql`
7. `supabase/fix_committee_contact_settings_rls_bestuur.sql`
8. `supabase/fix_profiles_email_sync_on_auth_update.sql`

### 8. Accounts en power admin

Alleen uitvoeren als je de committee power admin gebruikt:

1. `supabase/fix_committee_power_admin_thijs.sql`
2. `supabase/fix_committee_power_admin_limit_team_rights.sql`
3. `supabase/fix_committee_power_admin_account_manage.sql`

Controle na uitvoering:

- power admin heeft commissie- en accountrechten
- power admin ziet niet automatisch alle teams
- power admin verschijnt niet in Contact tenzij hij echt in `committee_members` staat

### 9. Pushmeldingen

1. `supabase/push_tokens_schema.sql`
2. `supabase/fix_push_tokens_update_policy.sql`
3. Deploy Edge Function `send-push-fcm`

Controle:

- `push_tokens` heeft select/insert/update/delete own policies
- broadcast mag alleen door admin/bestuur/communicatie
- gastaccount mag geen push-aanroepen doen

## Niet automatisch meenemen

Deze scripts alleen bewust en apart uitvoeren:

- `supabase/enable_rls_all_tables.sql`
- `supabase/cleanup_orphan_user_references.sql`
- `supabase/cascade_delete_user_data.sql`
- `supabase/home_news_reset.sql`
- `supabase/scripts/add_me_as_player_to_team.sql`
- `supabase/scripts/link_profile_to_bestuur_and_tc.sql`
- `supabase/scripts/add_me_to_bestuur.sql`

## Snelle live-controle

Controleer na wijzigingen in elk geval:

1. Gewone speler ziet statuslijsten en **Niet gereageerd** voor eigen team.
2. Trainingslid kan training-status zetten, maar ziet geen wedstrijdknoppen als niet gekoppeld aan wedstrijdteam.
3. Trainer/coach ziet teams onder de trainerweergave en kan trainingen beheren.
4. Bestuur kan commissies/contact/agenda/wedstrijden beheren volgens rol.
5. TC kan teams en teamleden beheren.
6. Wedstrijdzaken kan taken en wedstrijdkoppelingen beheren.
7. Power admin heeft commissie/accountrechten maar geen automatisch alle-teams-zicht.
