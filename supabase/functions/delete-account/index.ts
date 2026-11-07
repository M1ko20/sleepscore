// POST /functions/v1/delete-account
// Smazání účtu přihlášeného přes Apple: nejdřív zneplatní Apple refresh token
// (App Review 5.1.1(v)), pak zavolá `delete_my_account()` jménem uživatele.
// Soubory ve Storage maže appka předem (stejně jako u e-mailového účtu).
//
// Revokace je best effort: bez Apple konfigurace, bez uloženého tokenu nebo při chybě
// Apple se přeskočí a účet se smaže stejně – smazání dat má přednost.
// Odpověď: { "deleted": true, "revoked": true|false }

import { createClient } from "jsr:@supabase/supabase-js@2";
import { appleConfig, revokeToken } from "../_shared/apple.ts";

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });

Deno.serve(async (req) => {
  if (req.method !== "POST") return json({ error: "method not allowed" }, 405);

  const url = Deno.env.get("SUPABASE_URL")!;
  const admin = createClient(url, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, {
    auth: { persistSession: false },
  });

  const authHeader = req.headers.get("Authorization") ?? "";
  const jwt = authHeader.replace(/^Bearer\s+/i, "");
  const { data: auth } = await admin.auth.getUser(jwt);
  const userId = auth.user?.id;
  if (!userId) return json({ error: "unauthorized" }, 401);

  // --- 1. zneplatnit Apple token ---------------------------------------
  let revoked = false;
  const cfg = appleConfig();
  if (cfg) {
    const { data: row } = await admin.from("apple_tokens").select("refresh_token").eq("user_id", userId)
      .maybeSingle();
    if (row?.refresh_token) {
      try {
        await revokeToken(cfg, row.refresh_token);
        revoked = true;
      } catch (e) {
        console.error("apple revoke failed", { userId, error: String(e) });
      }
    } else {
      console.warn("apple revoke skipped: no stored token", { userId });
    }
  }

  // --- 2. smazat účet (auth.uid() = volající) ---------------------------
  const asUser = createClient(url, Deno.env.get("SUPABASE_ANON_KEY")!, {
    auth: { persistSession: false },
    global: { headers: { Authorization: authHeader } },
  });
  const { error } = await asUser.rpc("delete_my_account");
  if (error) {
    console.error("delete_my_account failed", { userId, error: error.message });
    return json({ error: "delete failed" }, 500);
  }
  return json({ deleted: true, revoked });
});
