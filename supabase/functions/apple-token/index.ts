// POST /functions/v1/apple-token
// Po přihlášení přes Apple pošle appka jednorázový authorization code (platí 5 min).
// Vyměníme ho za refresh token a uložíme do `apple_tokens` – při smazání účtu ho
// `delete-account` zneplatní. Bez Apple konfigurace vrací { stored: false } a nic nedělá.
//
// Body: { "authorization_code": "…" }

import { createClient } from "jsr:@supabase/supabase-js@2";
import { appleConfig, exchangeCode } from "../_shared/apple.ts";

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });

Deno.serve(async (req) => {
  if (req.method !== "POST") return json({ error: "method not allowed" }, 405);

  const admin = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, {
    auth: { persistSession: false },
  });

  const jwt = (req.headers.get("Authorization") ?? "").replace(/^Bearer\s+/i, "");
  const { data: auth } = await admin.auth.getUser(jwt);
  const user = auth.user;
  if (!user) return json({ error: "unauthorized" }, 401);

  let body: { authorization_code?: unknown };
  try {
    body = await req.json();
  } catch {
    return json({ error: "invalid json" }, 400);
  }
  const code = body.authorization_code;
  if (typeof code !== "string" || code.length === 0 || code.length > 1000) {
    return json({ error: "authorization_code required" }, 400);
  }

  const cfg = appleConfig();
  if (!cfg) return json({ stored: false, reason: "apple not configured" });

  const appleSub = user.identities?.find((i) => i.provider === "apple")?.id;
  if (!appleSub) return json({ error: "not an apple account" }, 400);

  let refreshToken: string;
  try {
    const res = await exchangeCode(cfg, code);
    // Kód musí patřit stejnému Apple ID jako přihlášený účet.
    if (res.sub !== appleSub) return json({ error: "code does not match account" }, 403);
    refreshToken = res.refreshToken;
  } catch (e) {
    console.error("apple exchange failed", { userId: user.id, error: String(e) });
    return json({ error: "exchange failed" }, 502);
  }

  const { error } = await admin.from("apple_tokens").upsert({
    user_id: user.id,
    refresh_token: refreshToken,
    updated_at: new Date().toISOString(),
  });
  if (error) {
    console.error("apple token store failed", { userId: user.id, error: error.message });
    return json({ error: "store failed" }, 500);
  }
  return json({ stored: true });
});
