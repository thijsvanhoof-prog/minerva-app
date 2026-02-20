// Edge Function: update-onesignal-user-tags
// Zet Data Tags op de ingelogde gebruiker in OneSignal via de REST API (Update User).
// Zo verschijnen de tags in het OneSignal-dashboard onder Audience → Users → User profile → Tags.
//
// Secrets: ONESIGNAL_APP_ID, ONESIGNAL_REST_API_KEY (zelfde als send-push-notification)
// Deploy: supabase functions deploy update-onesignal-user-tags

import { serve } from "std/http/server.ts";
import { createClient } from "@supabase/supabase-js";

declare const Deno: {
  env: { get(key: string): string | undefined };
};

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
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

  const authHeader = req.headers.get("Authorization");
  if (!authHeader) {
    return new Response(
      JSON.stringify({ error: "Unauthorized" }),
      { status: 401, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  }
  const jwt = authHeader.replace(/^Bearer\s+/i, "").trim();
  if (!jwt) {
    return new Response(
      JSON.stringify({ error: "Unauthorized" }),
      { status: 401, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  }

  const appId = Deno.env.get("ONESIGNAL_APP_ID")?.trim();
  const restApiKey = Deno.env.get("ONESIGNAL_REST_API_KEY")?.trim();
  if (!appId || !restApiKey) {
    return new Response(
      JSON.stringify({
        error: "Missing ONESIGNAL_APP_ID or ONESIGNAL_REST_API_KEY in Edge Function secrets",
      }),
      { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  }

  let body: { tags?: Record<string, string> };
  try {
    body = (await req.json()) as { tags?: Record<string, string> };
  } catch {
    return new Response(
      JSON.stringify({ error: "Invalid JSON body" }),
      { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  }

  const tags = body.tags;
  if (!tags || typeof tags !== "object" || Array.isArray(tags)) {
    return new Response(
      JSON.stringify({ error: "Body must include tags object, e.g. { \"tags\": { \"notify_news\": \"true\" } }" }),
      { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
  const serviceRoleKey =
    Deno.env.get("SERVICE_ROLE_KEY") ?? Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!serviceRoleKey) {
    return new Response(
      JSON.stringify({ error: "Missing SERVICE_ROLE_KEY secret" }),
      { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  }

  const supabaseAdmin = createClient(supabaseUrl, serviceRoleKey, {
    auth: { persistSession: false },
  });

  const { data: { user }, error: userError } = await supabaseAdmin.auth.getUser(jwt);
  if (userError || !user) {
    return new Response(
      JSON.stringify({ error: userError?.message ?? "Invalid or expired token" }),
      { status: 401, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  }

  // user.id is de Supabase auth user id; die gebruiken we als external_id in OneSignal (OneSignal.login(profileId))
  const externalId = user.id;

  const res = await fetch(
    `https://api.onesignal.com/apps/${appId}/users/by/external_id/${encodeURIComponent(externalId)}`,
    {
      method: "PATCH",
      headers: {
        "Content-Type": "application/json",
        Authorization: "key " + restApiKey.trim(),
      },
      body: JSON.stringify({
        properties: {
          tags,
        },
      }),
    }
  );

  const text = await res.text();
  let json: unknown;
  try {
    json = text ? JSON.parse(text) : {};
  } catch {
    json = { raw: text };
  }

  if (!res.ok) {
    console.error(
      "[update-onesignal-user-tags] OneSignal PATCH failed:",
      res.status,
      JSON.stringify(json)
    );
    return new Response(
      JSON.stringify({
        error: "OneSignal update failed",
        status: res.status,
        onesignal_response: json,
      }),
      { status: res.status, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  }

  return new Response(JSON.stringify(json), {
    status: res.status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
});
