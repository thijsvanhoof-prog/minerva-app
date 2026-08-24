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
// Gateway: verify_jwt = false in config.toml; user-JWT wordt in deze function gevalideerd.
//
// Body: { "title": "Titel", "body": "Bericht", "user_ids": ["uuid"] } of { "title": "...", "body": "...", "broadcast": true }

import { serve } from "std/http/server.ts";
import { createClient, type User } from "@supabase/supabase-js";
import * as jose from "https://deno.land/x/jose@v5.2.0/index.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

const userJwtPattern = /^[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+$/;

function unauthorizedResponse(): Response {
  return new Response(JSON.stringify({ error: "Unauthorized" }), {
    status: 401,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

function forbiddenResponse(): Response {
  return new Response(JSON.stringify({ error: "Forbidden" }), {
    status: 403,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

function isGuestAccount(user: User): boolean {
  const email = (user.email ?? "").trim().toLowerCase();
  if (!email) return false;
  if (email === "gast@mail.com") return true;
  const configuredGuest = (Deno.env.get("GUEST_EMAIL") ?? "").trim().toLowerCase();
  return configuredGuest.length > 0 && email === configuredGuest;
}

/** Zelfde rechten als can_manage_home_news(), maar voor expliciete caller user id (service-role). */
async function callerCanManageContentBroadcast(
  supabase: ReturnType<typeof createClient>,
  userId: string,
): Promise<boolean> {
  const { data: adminRow } = await supabase
    .from("global_admins")
    .select("id")
    .eq("id", userId)
    .maybeSingle();
  if (adminRow) return true;

  const { data: committees } = await supabase
    .from("committee_members")
    .select("committee_name")
    .eq("profile_id", userId);

  for (const row of committees ?? []) {
    const name = (row.committee_name ?? "").toString().trim().toLowerCase();
    if (name === "bestuur" || name.includes("bestuur")) return true;
    if (name === "cc" || name.includes("communicatie")) return true;
  }
  return false;
}

/** Valideer ingelogde user via Authorization Bearer (user access token). */
async function authenticateCaller(
  req: Request,
  supabaseUrl: string,
  serviceRoleKey: string,
): Promise<User | null> {
  const authHeader = req.headers.get("Authorization");
  if (!authHeader?.startsWith("Bearer ")) return null;

  const accessToken = authHeader.slice("Bearer ".length).trim();
  if (!accessToken || !userJwtPattern.test(accessToken)) return null;

  const supabase = createClient(supabaseUrl, serviceRoleKey);
  const { data: { user }, error } = await supabase.auth.getUser(accessToken);
  if (error || !user) return null;

  if (user.is_anonymous === true) return null;
  const appMeta = user.app_metadata ?? {};
  const userMeta = user.user_metadata ?? {};
  if (appMeta.is_anonymous === true || userMeta.is_anonymous === true) return null;
  if ((appMeta.provider ?? "").toString().toLowerCase() === "anonymous") return null;

  return user;
}

type Body = {
  title?: string;
  body?: string;
  /** Stuur naar deze users (moeten notify_enabled hebben) */
  user_ids?: string[];
  /** Stuur naar alle users met notify_enabled = true (o.a. Home: nieuws, agenda) */
  broadcast?: boolean;
  /** Stuur alleen naar users gekoppeld aan dit team (team_id in DB) */
  team_id?: number;
  /** Stuur naar users gekoppeld aan elk van deze teams */
  team_ids?: number[];
  /** Stuur naar users gekoppeld aan het team met deze Nevobo-code (bijv. JC1) */
  nevobo_team_code?: string;
  /** Server-side dedupe sleutel (optioneel) */
  dedupe_key?: string;
  /** Cooldown in seconden voor dedupe_key (optioneel) */
  cooldown_seconds?: number;
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

  const caller = await authenticateCaller(req, supabaseUrl, serviceRoleKey);
  if (!caller) {
    return unauthorizedResponse();
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
  const dedupeKey = (body.dedupe_key ?? "").toString().trim();
  const rawCooldown = Number(body.cooldown_seconds ?? 0);
  const cooldownSeconds = Number.isFinite(rawCooldown)
    ? Math.max(0, Math.min(7 * 24 * 3600, Math.floor(rawCooldown)))
    : 0;
  if (!bodyText) {
    return new Response(JSON.stringify({ error: "body is required" }), {
      status: 400,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }

  const supabase = createClient(supabaseUrl, serviceRoleKey);

  if (isGuestAccount(caller)) {
    return forbiddenResponse();
  }

  if (body.broadcast === true) {
    const canBroadcast = await callerCanManageContentBroadcast(supabase, caller.id);
    if (!canBroadcast) {
      return forbiddenResponse();
    }
  }

  // Team-specifiek: resolve team_id / team_ids / nevobo_team_code naar user_ids (leden + ouders van leden).
  let targetUserIds: string[] | undefined = body.user_ids ?? undefined;
  if (!body.broadcast && targetUserIds == null) {
    const collected = new Set<string>();
    const pushUuid = (row: unknown): void => {
      const u = typeof row === "string" ? row : (row as Record<string, unknown>)?.user_id ?? (row as Record<string, unknown>)?.get_user_ids_for_team_notifications ?? (row as Record<string, unknown>)?.get_user_ids_for_team_notifications_by_nevobo_code;
      if (typeof u === "string" && u) collected.add(u);
    };
    if (body.team_id != null && Number.isFinite(body.team_id)) {
      const { data: ids } = await supabase.rpc("get_user_ids_for_team_notifications", {
        p_team_id: body.team_id,
      });
      for (const row of ids ?? []) pushUuid(row);
    }
    if (Array.isArray(body.team_ids) && body.team_ids.length > 0) {
      for (const tid of body.team_ids) {
        if (!Number.isFinite(tid)) continue;
        const { data: ids } = await supabase.rpc("get_user_ids_for_team_notifications", {
          p_team_id: tid,
        });
        for (const row of ids ?? []) pushUuid(row);
      }
    }
    const code = (body.nevobo_team_code ?? "").toString().trim();
    if (code.length > 0) {
      const { data: ids } = await supabase.rpc("get_user_ids_for_team_notifications_by_nevobo_code", {
        p_nevobo_code: code,
      });
      for (const row of ids ?? []) pushUuid(row);
    }
    if (collected.size > 0) targetUserIds = [...collected];
  }

  // Server-side anti-spam: lock op dedupe_key + cooldown.
  if (dedupeKey.length > 0 && cooldownSeconds > 0) {
    try {
      const { data: acquired, error: lockError } = await supabase.rpc(
        "try_acquire_push_dispatch_lock",
        {
          p_dedupe_key: dedupeKey,
          p_cooldown_seconds: cooldownSeconds,
        }
      );
      if (lockError) {
        console.warn("push dedupe lock rpc failed:", lockError.message);
      } else if (acquired === false) {
        return new Response(
          JSON.stringify({
            success: true,
            sent: 0,
            total: 0,
            skipped: true,
            reason: "cooldown_active",
          }),
          { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } }
        );
      }
    } catch (e) {
      console.warn("push dedupe lock failed:", String(e));
    }
  }

  const tokenQuery = supabase.from("push_tokens").select("user_id, token");
  const { data: rawTokens } = body.broadcast
    ? await tokenQuery
    : targetUserIds?.length
    ? await tokenQuery.in("user_id", targetUserIds)
    : { data: [] as Array<{ user_id: string; token: string }> };

  const tokenRows = (rawTokens ?? []) as Array<{ user_id: string; token: string }>;
  if (tokenRows.length === 0) {
    return new Response(
      JSON.stringify({ success: true, sent: 0, message: "No FCM tokens" }),
      { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  }

  // Default = meldingen aan. Alleen expliciet notify_enabled=false wordt uitgesloten.
  const candidateUserIds = [...new Set(tokenRows.map((r) => r.user_id))];
  const { data: disabledPrefs } = await supabase
    .from("notification_preferences")
    .select("user_id")
    .in("user_id", candidateUserIds)
    .eq("notify_enabled", false);
  const disabledUserIds = new Set(
    (disabledPrefs ?? []).map((r: { user_id: string }) => r.user_id)
  );

  const fcmTokens = [
    ...new Set(
      tokenRows
        .filter((r) => !disabledUserIds.has(r.user_id))
        .map((r) => r.token)
        .filter((t) => t.trim().length > 0)
    ),
  ];

  if (fcmTokens.length === 0) {
    return new Response(
      JSON.stringify({ success: true, sent: 0, message: "No eligible users" }),
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
