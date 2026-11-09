import { assert, assertEquals } from "jsr:@std/assert@1";
import { apnsConfig, type ApnsConfig, cachedJwtUsable, classify, payload, providerToken, send } from "./apns.ts";

const b64 = (bytes: ArrayBuffer) => btoa(String.fromCharCode(...new Uint8Array(bytes)));
const b64urlDecode = (s: string) => {
  const p = s.replace(/-/g, "+").replace(/_/g, "/");
  return Uint8Array.from(atob(p.padEnd(Math.ceil(p.length / 4) * 4, "=")), (c) => c.charCodeAt(0));
};
const decodeJson = (s: string) => JSON.parse(new TextDecoder().decode(b64urlDecode(s)));

const keyPair = await crypto.subtle.generateKey({ name: "ECDSA", namedCurve: "P-256" }, true, ["sign", "verify"]);
const pem = `-----BEGIN PRIVATE KEY-----\n${
  b64(await crypto.subtle.exportKey("pkcs8", keyPair.privateKey)).match(/.{1,64}/g)!.join("\n")
}\n-----END PRIVATE KEY-----`;
const cfg: ApnsConfig = { teamId: "TEAM123456", keyId: "KEY1234567", privateKey: pem, topic: "cz.mikolas.bedrival" };
const env = (vars: Record<string, string>) => ({ get: (k: string) => vars[k] });

Deno.test("apns: bez klíče null", () => {
  assertEquals(apnsConfig(env({})), null);
  assertEquals(apnsConfig(env({ APPLE_TEAM_ID: "T", APNS_KEY_ID: "K" })), null);
});

Deno.test("apns: klíč ze Sign in with Apple jako záloha, APNS_* má přednost", () => {
  const base = { APPLE_TEAM_ID: "TEAM123456", APPLE_KEY_ID: "SIWA", APPLE_PRIVATE_KEY: pem.replace(/\n/g, "\\n") };
  assertEquals(apnsConfig(env(base)), { ...cfg, keyId: "SIWA" });
  assertEquals(apnsConfig(env({ ...base, APNS_KEY_ID: "KEY1234567", APPLE_CLIENT_ID: "x.y" })), {
    ...cfg,
    topic: "x.y",
  });
});

Deno.test("apns: provider token je ES256 JWT s iss a iat", async () => {
  const jwt = await providerToken(cfg, 1762700000);
  const [h, p, s] = jwt.split(".");
  assertEquals(decodeJson(h), { alg: "ES256", kid: "KEY1234567" });
  assertEquals(decodeJson(p), { iss: "TEAM123456", iat: 1762700000 });
  assert(
    await crypto.subtle.verify(
      { name: "ECDSA", hash: "SHA-256" },
      keyPair.publicKey,
      b64urlDecode(s),
      new TextEncoder().encode(`${h}.${p}`),
    ),
  );
});

Deno.test("apns: cache JWT 40 min", () => {
  assertEquals(cachedJwtUsable(null, 1000), false);
  assertEquals(cachedJwtUsable({ token: "x", iat: 1000 }, 1000 + 39 * 60), true);
  assertEquals(cachedJwtUsable({ token: "x", iat: 1000 }, 1000 + 40 * 60), false);
  assertEquals(cachedJwtUsable({ token: "x", iat: 5000 }, 1000), false); // z budoucnosti
});

Deno.test("apns: payload", () => {
  assertEquals(payload({ body: "Ahoj", badge: 2, link: { t: "post", id: "p" } }), {
    aps: { alert: { body: "Ahoj" }, badge: 2, sound: "default" },
    link: { t: "post", id: "p" },
  });
});

Deno.test("apns: klasifikace odpovědí", () => {
  assertEquals(classify(200, ""), { ok: true });
  assertEquals(classify(410, "Unregistered"), { ok: false, status: 410, reason: "Unregistered", dropToken: true, badJwt: false });
  assertEquals(classify(400, "BadDeviceToken").ok === false && classify(400, "BadDeviceToken"), {
    ok: false,
    status: 400,
    reason: "BadDeviceToken",
    dropToken: true,
    badJwt: false,
  });
  const r = classify(403, "ExpiredProviderToken");
  assert(!r.ok && r.badJwt && !r.dropToken);
  const t = classify(429, "TooManyRequests");
  assert(!t.ok && !t.dropToken && !t.badJwt);
});

Deno.test("apns: požadavek – host podle prostředí, hlavičky, collapse id", async () => {
  const calls: { url: string; init: RequestInit }[] = [];
  const fake = ((url: string, init: RequestInit) => {
    calls.push({ url, init });
    return Promise.resolve(
      calls.length === 1 ? new Response(null, { status: 200 }) : Response.json({ reason: "BadDeviceToken" }, { status: 400 }),
    );
  }) as unknown as typeof fetch;

  const p = { token: "ab", env: "sandbox" as const, body: "B", badge: 1, link: { t: "notifications" }, collapseId: "r-1" };
  assertEquals(await send(cfg, "JWT", p, fake), { ok: true });
  assertEquals(calls[0].url, "https://api.sandbox.push.apple.com/3/device/ab");
  const h = calls[0].init.headers as Record<string, string>;
  assertEquals(h.authorization, "bearer JWT");
  assertEquals(h["apns-topic"], "cz.mikolas.bedrival");
  assertEquals(h["apns-push-type"], "alert");
  assertEquals(h["apns-collapse-id"], "r-1");

  const r = await send(cfg, "JWT", { ...p, env: "production", collapseId: null }, fake);
  assertEquals(calls[1].url, "https://api.push.apple.com/3/device/ab");
  assert(!("apns-collapse-id" in (calls[1].init.headers as Record<string, string>)));
  assert(!r.ok && r.dropToken);
});

Deno.test("apns: síťová chyba token nemaže", async () => {
  const fake = (() => Promise.reject(new Error("boom"))) as unknown as typeof fetch;
  const r = await send(cfg, "J", { token: "a", env: "production", body: "", badge: 0, link: {} }, fake);
  assert(!r.ok && !r.dropToken && r.status === 0);
});
