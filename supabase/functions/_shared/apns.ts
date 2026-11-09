// APNs (push notifikace) – provider token (JWT ES256) a odeslání jednoho pushe.
// Klíč .p8 může být stejný jako pro Sign in with Apple (v Apple Developer zapnout obě služby).
//
// Secrets (`supabase secrets set …`):
//   APPLE_TEAM_ID                  – Team ID (sdílené s apple.ts)
//   APNS_KEY_ID / APNS_PRIVATE_KEY – klíč s APNs; když chybí, použije se APPLE_KEY_ID / APPLE_PRIVATE_KEY
//   APNS_TOPIC                     – bundle ID; když chybí, APPLE_CLIENT_ID, jinak cz.mikolas.bedrival

type Env = { get(key: string): string | undefined };
type Fetch = typeof fetch;

export type ApnsConfig = { teamId: string; keyId: string; privateKey: string; topic: string };
export type ApnsEnv = "production" | "sandbox";

export function apnsConfig(env: Env = Deno.env): ApnsConfig | null {
  const teamId = env.get("APPLE_TEAM_ID")?.trim();
  const keyId = (env.get("APNS_KEY_ID") ?? env.get("APPLE_KEY_ID"))?.trim();
  const privateKey = (env.get("APNS_PRIVATE_KEY") ?? env.get("APPLE_PRIVATE_KEY"))?.replace(/\\n/g, "\n").trim();
  const topic = (env.get("APNS_TOPIC") ?? env.get("APPLE_CLIENT_ID") ?? "cz.mikolas.bedrival").trim();
  if (!teamId || !keyId || !privateKey) return null;
  return { teamId, keyId, privateKey, topic };
}

const b64url = (bytes: Uint8Array) =>
  btoa(String.fromCharCode(...bytes)).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
const b64urlJson = (obj: unknown) => b64url(new TextEncoder().encode(JSON.stringify(obj)));

function pemToDer(pem: string): Uint8Array<ArrayBuffer> {
  const body = pem.replace(/-----(BEGIN|END) [A-Z ]+-----/g, "").replace(/\s+/g, "");
  return Uint8Array.from(atob(body), (c) => c.charCodeAt(0));
}

/** Provider token: platí max. 1 h, APNs nechce nový častěji než 1× za 20 min. */
export async function providerToken(cfg: ApnsConfig, iat: number): Promise<string> {
  const key = await crypto.subtle.importKey(
    "pkcs8",
    pemToDer(cfg.privateKey),
    { name: "ECDSA", namedCurve: "P-256" },
    false,
    ["sign"],
  );
  const input = `${b64urlJson({ alg: "ES256", kid: cfg.keyId })}.${b64urlJson({ iss: cfg.teamId, iat })}`;
  const sig = await crypto.subtle.sign({ name: "ECDSA", hash: "SHA-256" }, key, new TextEncoder().encode(input));
  return `${input}.${b64url(new Uint8Array(sig))}`;
}

/** Token z cache v DB stačí, dokud je mladší než 40 min (APNs ho bere do 60). */
export const JWT_MAX_AGE_S = 40 * 60;
export function cachedJwtUsable(cached: { token: string; iat: number } | null, nowS: number): boolean {
  return !!cached && nowS - cached.iat < JWT_MAX_AGE_S && nowS >= cached.iat - 60;
}

export type Push = {
  token: string;
  env: ApnsEnv;
  body: string;
  badge: number;
  link: Record<string, unknown>;
  collapseId?: string | null;
};

/** Tělo pushe: text, badge, zvuk a odkaz pro appku (`link`). */
export function payload(p: Pick<Push, "body" | "badge" | "link">): Record<string, unknown> {
  return {
    aps: { alert: { body: p.body }, badge: p.badge, sound: "default" },
    link: p.link,
  };
}

export type SendResult =
  | { ok: true }
  | { ok: false; status: number; reason: string; dropToken: boolean; badJwt: boolean };

// Token už nikdy nebude fungovat → smazat.
const DEAD_TOKEN = new Set(["BadDeviceToken", "Unregistered", "DeviceTokenNotForTopic", "ExpiredToken"]);
const BAD_JWT = new Set(["ExpiredProviderToken", "InvalidProviderToken", "MissingProviderToken"]);

export function classify(status: number, reason: string): SendResult {
  if (status === 200) return { ok: true };
  return {
    ok: false,
    status,
    reason,
    dropToken: status === 410 || DEAD_TOKEN.has(reason),
    badJwt: status === 403 && BAD_JWT.has(reason),
  };
}

export async function send(cfg: ApnsConfig, jwt: string, p: Push, fetchFn: Fetch = fetch): Promise<SendResult> {
  const host = p.env === "sandbox" ? "api.sandbox.push.apple.com" : "api.push.apple.com";
  const headers: Record<string, string> = {
    authorization: `bearer ${jwt}`,
    "apns-topic": cfg.topic,
    "apns-push-type": "alert",
    "apns-priority": "10",
    "content-type": "application/json",
  };
  if (p.collapseId) headers["apns-collapse-id"] = p.collapseId.slice(0, 64);
  try {
    const res = await fetchFn(`https://${host}/3/device/${p.token}`, {
      method: "POST",
      headers,
      body: JSON.stringify(payload(p)),
    });
    if (res.status === 200) {
      await res.body?.cancel();
      return { ok: true };
    }
    const reason = (await res.json().catch(() => ({})))?.reason ?? "";
    return classify(res.status, String(reason));
  } catch (e) {
    return { ok: false, status: 0, reason: String(e), dropToken: false, badJwt: false };
  }
}
