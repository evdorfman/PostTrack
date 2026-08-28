// Clears every MFA (TOTP) factor on a target user's account, so they're
// routed back through the mandatory enrollment screen on their next sign-in.
// Used from Admin > Team's "Reset 2FA" button for someone locked out after
// losing their authenticator device — the client can only ever manage its
// own account's factors (sb.auth.mfa.*), so removing someone ELSE's factor
// requires the service role key, which must never reach the browser. This
// function holds that key server-side and gates the action on the caller
// actually being an admin (team_members.is_admin) before acting.
//
// Deploy (once) via the Supabase CLI from the project root:
//   supabase functions deploy admin-reset-mfa
// or paste this file's contents into Dashboard → Edge Functions → New Function
// (name it exactly "admin-reset-mfa" to match the sb.functions.invoke call).
// No extra secrets to set — SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY are
// already provided automatically to every Edge Function in the project.

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const CORS_HEADERS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const json = (body, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
  });

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response(null, { headers: CORS_HEADERS });
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405);

  const SUPABASE_URL = Deno.env.get("SUPABASE_URL");
  const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  const ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY");
  if (!SUPABASE_URL || !SERVICE_ROLE_KEY || !ANON_KEY) {
    return json({ error: "Function is missing required Supabase env vars." }, 500);
  }

  const authHeader = req.headers.get("Authorization") || "";
  if (!authHeader) return json({ error: "Not authenticated" }, 401);

  // Identify the caller from their own JWT (anon-key client — this only
  // reads who they are, it can't act on their behalf beyond that).
  const callerClient = createClient(SUPABASE_URL, ANON_KEY, {
    global: { headers: { Authorization: authHeader } },
  });
  const { data: { user: caller }, error: callerErr } = await callerClient.auth.getUser();
  if (callerErr || !caller) return json({ error: "Not authenticated" }, 401);

  // Service-role client for the admin check and the actual factor removal.
  const admin = createClient(SUPABASE_URL, SERVICE_ROLE_KEY);

  const { data: callerMember, error: memberErr } = await admin
    .from("team_members")
    .select("is_admin")
    .eq("auth_user_id", caller.id)
    .maybeSingle();
  if (memberErr) return json({ error: memberErr.message }, 500);
  if (!callerMember?.is_admin) return json({ error: "Admin access required" }, 403);

  let body;
  try { body = await req.json(); } catch { body = {}; }
  const targetUserId = body?.targetUserId;
  if (!targetUserId || typeof targetUserId !== "string") {
    return json({ error: "targetUserId is required" }, 400);
  }

  const { data: factorsData, error: factorsErr } = await admin.auth.admin.mfa.listFactors({ userId: targetUserId });
  if (factorsErr) return json({ error: factorsErr.message }, 500);

  for (const factor of factorsData?.factors || []) {
    const { error: delErr } = await admin.auth.admin.mfa.deleteFactor({ id: factor.id, userId: targetUserId });
    if (delErr) return json({ error: delErr.message }, 500);
  }

  return json({ ok: true, cleared: factorsData?.factors?.length || 0 });
});
