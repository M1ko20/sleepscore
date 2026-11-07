import { assert, assertEquals, assertRejects } from "jsr:@std/assert@1";
import { appleConfig, type AppleConfig, clientSecret, exchangeCode, idTokenSub, revokeToken } from "./apple.ts";

const b64 = (bytes: ArrayBuffer) => btoa(String.fromCharCode(...new Uint8Array(bytes)));
const b64urlDecode = (s: string) => {
  const p = s.replace(/-/g, "+").replace(/_/g, "/");
  return Uint8Array.from(atob(p.padEnd(Math.ceil(p.length / 4) * 4, "=")), (c) => c.charCodeAt(0));
};
const decodeJson = (s: string) => JSON.parse(new TextDecoder().decode(b64urlDecode(s)));

// Testovací klíč ve stejném formátu jako .p8 od Apple (PKCS#8 PEM, P-256).
const keyPair = await crypto.subtle.generateKey({ name: "ECDSA", namedCurve: "P-256" }, true, ["sign", "verify"]);
const pem = `-----BEGIN PRIVATE KEY-----\n${
  b64(await crypto.subtle.exportKey("pkcs8", keyPair.privateKey)).match(/.{1,64}/g)!.join("\n")
}\n-----END PRIVATE KEY-----`;
const cfg: AppleConfig = { teamId: "TEAM123456", keyId: "KEY1234567", clientId: "cz.mikolas.sleepscore", privateKey: pem };

const env = (vars: Record<string, string>) => ({ get: (k: string) => vars[k] });

Deno.test("apple: bez konfigurace null (revokace se přeskočí)", () => {
  assertEquals(appleConfig(env({})), null);
  assertEquals(appleConfig(env({ APPLE_TEAM_ID: "T", APPLE_KEY_ID: "K", APPLE_CLIENT_ID: "C" })), null);
  assertEquals(appleConfig(env({ APPLE_TEAM_ID: "T", APPLE_KEY_ID: "K", APPLE_CLIENT_ID: "C", APPLE_PRIVATE_KEY: " " })), null);
});

Deno.test("apple: konfigurace z env, doslovné \\n v klíči", () => {
  const c = appleConfig(env({
    APPLE_TEAM_ID: "TEAM123456",
    APPLE_KEY_ID: "KEY1234567",
    APPLE_CLIENT_ID: "cz.mikolas.sleepscore",
    APPLE_PRIVATE_KEY: pem.replace(/\n/g, "\\n"),
  }));
  assertEquals(c, cfg);
});

Deno.test("apple: client_secret je platný ES256 JWT se správnými claimy", async () => {
  const now = Date.UTC(2026, 10, 7, 12);
  const jwt = await clientSecret(cfg, now);
  const [h, p, s] = jwt.split(".");
  assertEquals(decodeJson(h), { alg: "ES256", kid: "KEY1234567" });
  assertEquals(decodeJson(p), {
    iss: "TEAM123456",
    iat: now / 1000,
    exp: now / 1000 + 300,
    aud: "https://appleid.apple.com",
    sub: "cz.mikolas.sleepscore",
  });
  const sig = b64urlDecode(s);
  assertEquals(sig.length, 64);
  assert(
    await crypto.subtle.verify(
      { name: "ECDSA", hash: "SHA-256" },
      keyPair.publicKey,
      sig,
      new TextEncoder().encode(`${h}.${p}`),
    ),
  );
});

const fakeIdToken = (claims: Record<string, unknown>) =>
  `x.${btoa(JSON.stringify(claims)).replace(/=+$/, "").replace(/\+/g, "-").replace(/\//g, "_")}.y`;

function recorder(status: number, body: unknown) {
  const calls: { url: string; form: URLSearchParams }[] = [];
  const fetchFn = ((url: string, init: RequestInit) => {
    calls.push({ url, form: new URLSearchParams(init.body as string) });
    return Promise.resolve(new Response(typeof body === "string" ? body : JSON.stringify(body), { status }));
  }) as typeof fetch;
  return { calls, fetchFn };
}

Deno.test("apple: výměna kódu za refresh token", async () => {
  const { calls, fetchFn } = recorder(200, {
    access_token: "a",
    refresh_token: "r.123",
    id_token: fakeIdToken({ sub: "001234.abc.0001" }),
  });
  const res = await exchangeCode(cfg, "code-1", fetchFn);
  assertEquals(res, { refreshToken: "r.123", sub: "001234.abc.0001" });
  assertEquals(calls[0].url, "https://appleid.apple.com/auth/token");
  assertEquals(calls[0].form.get("grant_type"), "authorization_code");
  assertEquals(calls[0].form.get("code"), "code-1");
  assertEquals(calls[0].form.get("client_id"), "cz.mikolas.sleepscore");
  assertEquals(calls[0].form.get("client_secret")!.split(".").length, 3);
});

Deno.test("apple: neplatný kód → chyba", async () => {
  const { fetchFn } = recorder(400, { error: "invalid_grant" });
  await assertRejects(() => exchangeCode(cfg, "old", fetchFn), Error, "invalid_grant");
});

Deno.test("apple: revoke posílá refresh token", async () => {
  const { calls, fetchFn } = recorder(200, "");
  await revokeToken(cfg, "r.123", fetchFn);
  assertEquals(calls[0].url, "https://appleid.apple.com/auth/revoke");
  assertEquals(calls[0].form.get("token"), "r.123");
  assertEquals(calls[0].form.get("token_type_hint"), "refresh_token");
  assertEquals(calls[0].form.get("client_id"), "cz.mikolas.sleepscore");
});

Deno.test("apple: revoke chyba → výjimka", async () => {
  const { fetchFn } = recorder(400, { error: "invalid_client" });
  await assertRejects(() => revokeToken(cfg, "r", fetchFn), Error, "400");
});

Deno.test("apple: sub z id_tokenu", () => {
  assertEquals(idTokenSub(fakeIdToken({ sub: "s1", email: "x@privaterelay.appleid.com" })), "s1");
  assertEquals(idTokenSub("nesmysl"), null);
  assertEquals(idTokenSub(undefined), null);
});
