-- Controleren of push (FCM) goed is opgezet
-- Uitvoeren in Supabase SQL Editor (als admin / met rechten op de tabellen)
--
-- Daarna testpush: zie supabase/test_send_push.sh of:
-- curl -X POST https://JOUW_REF.supabase.co/functions/v1/send-push-fcm \
--   -H "Content-Type: application/json" -H "Authorization: Bearer JOUW_ANON_KEY" \
--   -d '{"title":"Test","body":"Push test","broadcast":true}'

-- 1) Zijn er tokens geregistreerd?
SELECT
  'push_tokens' AS tabel,
  count(*) AS aantal
FROM public.push_tokens;

-- 2) Hoeveel users hebben "meldingen aan"?
SELECT
  'notification_preferences (meldingen aan)' AS beschrijving,
  count(*) AS aantal
FROM public.notification_preferences
WHERE notify_enabled = true;

-- 3) Overzicht: users met token + meldingen aan (die een broadcast zouden ontvangen)
SELECT
  p.user_id,
  p.platform,
  p.created_at AS token_registered,
  np.notify_enabled
FROM public.push_tokens p
JOIN public.notification_preferences np ON np.user_id = p.user_id
WHERE np.notify_enabled = true
ORDER BY p.created_at DESC;
