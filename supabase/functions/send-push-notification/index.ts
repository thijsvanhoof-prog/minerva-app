// Edge Function: send-push-notification
// Roept de OneSignal REST API aan om een pushmelding te versturen.
// Aanroepen vanuit Database Webhooks of vanuit een andere Edge Function.
//
// Secrets (Supabase Dashboard → Edge Functions → Secrets):
//   ONESIGNAL_APP_ID      — je OneSignal App ID
//   ONESIGNAL_REST_API_KEY — OneSignal Dashboard → Settings → Keys & IDs → REST API Key
//
// Deploy: supabase functions deploy send-push-notification

import { serve } from "std/http/server.ts";

declare const Deno: {
  env: { get(key: string): string | undefined };
};

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

type OneSignalBody = {
  headings?: { [locale: string]: string };
  contents: { [locale: string]: string };
  /** OneSignal filter array, e.g. [{"field": "tag", "key": "notify_news", "relation": "=", "value": "true"}] */
  filters?: Array<{ field: string; key?: string; relation?: string; value?: string }>;
  /** Of: included_segments, include_player_ids, etc. */
  included_segments?: string[];
  include_player_ids?: string[];
};

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  if (req.method !== "POST") {
    return new Response(
      JSON.stringify({ error: "Method not allowed" }),
      { status: 405, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  }

  const appId = Deno.env.get("ONESIGNAL_APP_ID");
  const restApiKey = Deno.env.get("ONESIGNAL_REST_API_KEY");
  if (!appId || !restApiKey) {
    return new Response(
      JSON.stringify({
        error: "Missing ONESIGNAL_APP_ID or ONESIGNAL_REST_API_KEY in Edge Function secrets",
      }),
      { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  }

  let body: OneSignalBody;
  try {
    body = (await req.json()) as OneSignalBody;
  } catch {
    return new Response(
      JSON.stringify({ error: "Invalid JSON body" }),
      { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  }

  if (!body.contents || typeof body.contents !== "object") {
    return new Response(
      JSON.stringify({ error: "Body must include contents, e.g. { \"contents\": { \"nl\": \"Bericht\" } }" }),
      { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  }

  // OneSignal vereist "relation" bij tag-filters (bijv. "=" voor equals)
  const filters = body.filters?.map((f) =>
    f.field === "tag" && f.key != null && f.value != null && f.relation == null
      ? { ...f, relation: "=" as const }
      : f
  );

  const payload = {
    app_id: appId,
    contents: body.contents,
    headings: body.headings ?? { nl: "Minerva" },
    ...(filters && filters.length > 0 && { filters }),
    ...(body.included_segments && body.included_segments.length > 0 && { included_segments: body.included_segments }),
    ...(body.include_player_ids && body.include_player_ids.length > 0 && { include_player_ids: body.include_player_ids }),
  };

  // OneSignal App API Key: "key" scheme (documentation.onesignal.com Keys & IDs)
  const res = await fetch("https://api.onesignal.com/notifications", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: "key " + restApiKey,
    },
    body: JSON.stringify(payload),
  });

  const text = await res.text();
  let json: unknown;
  try {
    json = text ? JSON.parse(text) : {};
  } catch {
    json = { raw: text };
  }

  return new Response(JSON.stringify(json), {
    status: res.status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
});
