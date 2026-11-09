// POST /functions/v1/send-push  (#10)
// Volá jen pg_cron přes pg_net (`private.push_tick`, max 1× za minutu a jen s neprázdnou frontou).
// Ověření: hlavička `x-push-secret` = secret PUSH_SECRET (stejná hodnota je v private.app_config).
// Nasazení s --no-verify-jwt (volající nemá uživatelský JWT).
//
// 1. claim_push_batch() – zamkne frontu, vrátí 1 push na uživatele + JWT z cache
// 2. APNs – každý token zvlášť (HTTP/2), max. 10 souběžně
// 3. finish_push_batch() – smaže mrtvé tokeny, uloží nový JWT / smaže odmítnutý
// Bez APNs klíče nic nezamyká a nic neposílá (fronta po dni sama vyprší).

import { createClient } from "jsr:@supabase/supabase-js@2";
import { apnsConfig, type ApnsEnv, cachedJwtUsable, providerToken, send } from "../_shared/apns.ts";

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });

type Batch = {
  jwt: { token: string; iat: number } | null;
  pushes: {
    user_id: string;
    tokens: { token: string; env: ApnsEnv }[] | null;
    body: string;
    badge: number;
    link: Record<string, unknown>;
    collapse_id: string | null;
  }[];
};

/** Porovnání bez úniku délky shody přes čas. */
function safeEqual(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return diff === 0;
}

async function pool<T>(items: T[], limit: number, work: (item: T) => Promise<void>) {
  let next = 0;
  const runners = Array.from({ length: Math.min(limit, items.length) }, async () => {
    while (next < items.length) await work(items[next++]);
  });
  await Promise.all(runners);
}

Deno.serve(async (req) => {
  if (req.method !== "POST") return json({ error: "method not allowed" }, 405);
  const secret = Deno.env.get("PUSH_SECRET") ?? "";
  if (!secret || !safeEqual(req.headers.get("x-push-secret") ?? "", secret)) {
    return json({ error: "unauthorized" }, 401);
  }

  const cfg = apnsConfig();
  if (!cfg) {
    console.warn("send-push: APNs není nastavené, nic neposílám");
    return json({ skipped: "no apns config" });
  }

  const admin = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, {
    auth: { persistSession: false },
  });

  const { data, error } = await admin.rpc("claim_push_batch");
  if (error) {
    console.error("claim_push_batch failed", error.message);
    return json({ error: "claim failed" }, 500);
  }
  const batch = data as Batch;

  const nowS = Math.floor(Date.now() / 1000);
  let jwt = batch.jwt?.token ?? "";
  let newJwt: { token: string; iat: number } | null = null;
  if (!cachedJwtUsable(batch.jwt, nowS)) {
    newJwt = { token: await providerToken(cfg, nowS), iat: nowS };
    jwt = newJwt.token;
  }

  const jobs = batch.pushes.flatMap((p) =>
    (p.tokens ?? []).map((t) => ({
      token: t.token,
      env: t.env,
      body: p.body,
      badge: p.badge,
      link: p.link,
      collapseId: p.collapse_id,
    }))
  );

  const invalid: string[] = [];
  let sent = 0;
  let badJwt = false;
  await pool(jobs, 10, async (job) => {
    const r = await send(cfg, jwt, job);
    if (r.ok) {
      sent++;
      return;
    }
    if (r.dropToken) invalid.push(job.token);
    if (r.badJwt) badJwt = true;
    // Token ani text do logu nepatří (osobní data) – jen důvod.
    console.warn("apns failed", { status: r.status, reason: r.reason });
  });

  if (invalid.length || newJwt || badJwt) {
    const { error: finishError } = await admin.rpc("finish_push_batch", {
      p_invalid_tokens: invalid,
      p_jwt: badJwt ? null : newJwt?.token ?? null,
      p_jwt_iat: badJwt ? null : newJwt?.iat ?? null,
      p_clear_jwt: badJwt,
    });
    if (finishError) console.error("finish_push_batch failed", finishError.message);
  }

  return json({ users: batch.pushes.length, sent, failed: jobs.length - sent, dropped: invalid.length });
});
