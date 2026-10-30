// Lists every Supabase Auth user (id, email, created_at) so the Admin >
// Team panel can show accounts that signed in and skipped the onboarding
// modal — they're fully authenticated but have no team_members row, so
// they're otherwise invisible anywhere in the app. Needs the Admin API
// (auth.admin.listUsers), which requires the service-role key — this can
// only run server-side, never in the browser bundle, same reasoning as
// admin-reset-mfa.
//
// Deploy: paste this into Supabase Dashboard -> Edge Functions -> Create
// a new function named "admin-list-auth-users" (or `supabase functions
// deploy admin-list-auth-users` if using the CLI from this directory).
// No extra secrets to configure — SUPABASE_URL, SUPABASE_ANON_KEY and
// SUPABASE_SERVICE_ROLE_KEY are already provided to every Edge Function
// automatically.

import { createClient } from "npm:@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });

  try {
    const authHeader = req.headers.get("Authorization");
    if (!authHeader) return json({ error: "Missing Authorization header" }, 401);

    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const anonKey = Deno.env.get("SUPABASE_ANON_KEY")!;
    const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

    // Identify the caller from their OWN token via a plain anon-key client
    // (never trust a client-supplied user id) — this client has no elevated
    // privileges, it can only read who's making the request.
    const callerClient = createClient(supabaseUrl, anonKey, {
      global: { headers: { Authorization: authHeader } },
    });
    const { data: callerData, error: callerErr } = await callerClient.auth.getUser();
    if (callerErr || !callerData?.user) return json({ error: "Not authenticated" }, 401);

    // Service-role client — used only server-side, from here on, for the
    // admin check and the actual user listing.
    const adminClient = createClient(supabaseUrl, serviceRoleKey);

    // The client-side Admin-tab gate is UX only; this is the real check —
    // only someone whose own team_members row has is_admin can list every
    // auth user's email.
    const { data: callerMember, error: memberErr } = await adminClient
      .from("team_members")
      .select("is_admin")
      .eq("auth_user_id", callerData.user.id)
      .maybeSingle();
    if (memberErr) return json({ error: memberErr.message }, 500);
    if (!callerMember?.is_admin) return json({ error: "Admin access required" }, 403);

    // Paginated — listUsers caps at 1000/page; loop until a short page.
    const users: { id: string; email: string | null; createdAt: string }[] = [];
    let page = 1;
    const perPage = 1000;
    for (;;) {
      const { data, error } = await adminClient.auth.admin.listUsers({ page, perPage });
      if (error) return json({ error: error.message }, 500);
      users.push(...data.users.map((u) => ({ id: u.id, email: u.email ?? null, createdAt: u.created_at })));
      if (data.users.length < perPage) break;
      page++;
    }

    return json({ users });
  } catch (e) {
    return json({ error: e instanceof Error ? e.message : "Unknown error" }, 500);
  }
});
