// Edge Function: send-push-fcm
// Verstuurt pushnotificaties via Firebase Cloud Messaging (FCM) v1 API.
// Leest tokens uit Supabase push_tokens (alleen users met notification_preferences.notify_enabled = true).
//
// Secrets (Supabase Dashboard → Edge Functions → Secrets):
//   FIREBASE_PROJECT_ID          — Firebase project ID
//   FIREBASE_SERVICE_ACCOUNT_JSON — Volledige JSON van de service account key (als string)
//   SUPABASE_SERVICE_ROLE_KEY    — Om push_tokens en notification_preferences te lezen
//
// Deploy: supabase functions deploy send-push-fcm
//
// Body: { "title": "Titel", "body": "Bericht", "user_ids": ["uuid"] } of { "title": "...", "body": "...", "broadcast": true }

import { serve } from "std/http/server.ts";
import { createClient } from "@supabase/supabase-js";
import * as jose from "https://deno.land/x/jose@v5.2.0/index.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

type Body = {
  title?: string;
  body?: string;
  /** Stuur naar deze users (moeten notify_enabled hebben) */
  user_ids?: string[];
  /** Stuur naar alle users met notify_enabled = true */
  broadcast?: boolean;
};

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (req.method !== "POST") {
    return new Response(JSON.stringify({ error: "Method not allowed" }), {
      status: 405,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }

  const projectId = Deno.env.get("FIREBASE_PROJECT_ID");
  const saJson = Deno.env.get("FIREBASE_SERVICE_ACCOUNT_JSON");
  const serviceRoleKey =
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ??
    Deno.env.get("SERVICE_ROLE_KEY");
  const supabaseUrl = Deno.env.get("SUPABASE_URL");

  if (!projectId || !saJson || !serviceRoleKey || !supabaseUrl) {
    return new Response(
      JSON.stringify({
        error:
          "Missing FIREBASE_PROJECT_ID, FIREBASE_SERVICE_ACCOUNT_JSON, (SUPABASE_SERVICE_ROLE_KEY or SERVICE_ROLE_KEY) or SUPABASE_URL",
      }),
      { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  }

  let body: Body;
  try {
    body = (await req.json()) as Body;
  } catch {
    return new Response(JSON.stringify({ error: "Invalid JSON body" }), {
      status: 400,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }

  const title = body.title ?? "Minerva";
  const bodyText = body.body ?? "";
  if (!bodyText) {
    return new Response(JSON.stringify({ error: "body is required" }), {
      status: 400,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }

  const supabase = createClient(supabaseUrl, serviceRoleKey);
  let userIds: string[] = [];

  if (body.broadcast) {
    const { data: prefs } = await supabase
      .from("notification_preferences")
      .select("user_id")
      .eq("notify_enabled", true);
    userIds = (prefs ?? []).map((r: { user_id: string }) => r.user_id);
  } else if (body.user_ids?.length) {
    const { data: prefs } = await supabase
      .from("notification_preferences")
      .select("user_id")
      .in("user_id", body.user_ids)
      .eq("notify_enabled", true);
    userIds = (prefs ?? []).map((r: { user_id: string }) => r.user_id);
  }

  if (userIds.length === 0) {
    return new Response(
      JSON.stringify({ success: true, sent: 0, message: "No eligible users" }),
      { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  }

  const { data: tokens } = await supabase
    .from("push_tokens")
    .select("token")
    .in("user_id", userIds);
  const fcmTokens = [...new Set((tokens ?? []).map((r: { token: string }) => r.token))];

  if (fcmTokens.length === 0) {
    return new Response(
      JSON.stringify({ success: true, sent: 0, message: "No FCM tokens" }),
      { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  }

  let accessToken: string;
  try {
    const sa = JSON.parse(saJson) as {
      client_email: string;
      private_key: string;
    };
    const jwt = await new jose.SignJWT({
      scope: "https://www.googleapis.com/auth/firebase.messaging",
    })
      .setProtectedHeader({ alg: "RS256", typ: "JWT" })
      .setIssuer(sa.client_email)
      .setAudience("https://oauth2.googleapis.com/token")
      .setIssuedAt()
      .setExpirationTime("1h")
      .sign(await jose.importPKCS8(sa.private_key.replace(/\\n/g, "\n"), "RS256"));
    const tokenRes = await fetch("https://oauth2.googleapis.com/token", {
      method: "POST",
      headers: { "Content-Type": "application/x-www-form-urlencoded" },
      body: new URLSearchParams({
        grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
        assertion: jwt,
      }),
    });
    const tokenData = (await tokenRes.json()) as { access_token?: string };
    accessToken = tokenData.access_token ?? "";
    if (!accessToken) {
      throw new Error("No access_token in OAuth response");
    }
  } catch (e) {
    return new Response(
      JSON.stringify({ error: "FCM auth failed", detail: String(e) }),
      { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  }

  const url = `https://fcm.googleapis.com/v1/projects/${projectId}/messages:send`;
  let successCount = 0;
  const errors: string[] = [];

  for (const token of fcmTokens) {
    const payload = {
      message: {
        token,
        notification: { title, body: bodyText },
        android: { notification: { title, body: bodyText } },
        apns: {
          payload: { aps: { alert: { title, body: bodyText }, sound: "default" } },
          fcm_options: {},
        },
      },
    };
    const res = await fetch(url, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: `Bearer ${accessToken}`,
      },
      body: JSON.stringify(payload),
    });
    if (res.ok) {
      successCount++;
    } else {
      const errText = await res.text();
      errors.push(`${token.slice(0, 20)}…: ${res.status} ${errText.slice(0, 100)}`);
    }
  }

  return new Response(
    JSON.stringify({
      success: true,
      sent: successCount,
      total: fcmTokens.length,
      errors: errors.length > 0 ? errors : undefined,
    }),
    { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } }
  );
});
