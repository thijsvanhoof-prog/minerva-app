#!/bin/bash
# Testpush sturen via Edge Function send-push-fcm
# Gebruik: ./test_send_push.sh
# Zet SUPABASE_URL en SUPABASE_ANON_KEY (of SERVICE_ROLE_KEY) in .env of pas onderstaande aan.

SUPABASE_URL="${SUPABASE_URL:-https://JOUW_PROJECT_REF.supabase.co}"
SUPABASE_KEY="${SUPABASE_ANON_KEY:-jouw_anon_of_service_role_key}"

curl -s -X POST "$SUPABASE_URL/functions/v1/send-push-fcm" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $SUPABASE_KEY" \
  -d '{"title":"Test Minerva","body":"Als je dit ziet werkt push!","broadcast":true}' \
  | jq .

# Zonder jq: verwijder "| jq ." of vervang door "| cat"
