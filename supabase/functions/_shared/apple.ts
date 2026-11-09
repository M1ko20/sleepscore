// Sign in with Apple – serverová část (Apple REST API).
// Apple vyžaduje při smazání účtu zneplatnit token (App Review 5.1.1(v)):
//   1. po přihlášení appka pošle authorization code → vyměníme ho za refresh token a uložíme,
//   2. při smazání účtu refresh token zneplatníme přes /auth/revoke.
// Bez konfigurace (Adam ještě nemá Apple Developer Program) se všechno tiše přeskočí.
//
// Secrets (`supabase secrets set …`):
//   APPLE_TEAM_ID      – Team ID (10 znaků)
//   APPLE_KEY_ID       – Key ID klíče se zapnutým Sign in with Apple
//   APPLE_CLIENT_ID    – bundle ID appky (cz.mikolas.bedrival)
//   APPLE_PRIVATE_KEY  – obsah .p8 souboru (PEM i s řádky BEGIN/END)

const APPLE = "https://appleid.apple.com";

export type AppleConfig = { teamId: string; keyId: string; clientId: string; privateKey: string };
type Env = { get(key: string): string | undefined };
type Fetch = typeof fetch;

/** Konfigurace z prostředí, nebo null, když něco chybí (→ výměna i revokace se přeskočí). */
export function appleConfig(env: Env = Deno.env): AppleConfig | null {
  const teamId = env.get("APPLE_TEAM_ID")?.trim();
  const keyId = env.get("APPLE_KEY_ID")?.trim();
  const clientId = env.get("APPLE_CLIENT_ID")?.trim();
  // Secret zadaný na jeden řádek může mít místo nových řádků doslovné "\n".
  const privateKey = env.get("APPLE_PRIVATE_KEY")?.replace(/\\n/g, "\n").trim();
  if (!teamId || !keyId || !clientId || !privateKey) return null;
  return { teamId, keyId, clientId, privateKey };
}

const b64url = (bytes: Uint8Array) =>
  btoa(String.fromCharCode(...bytes)).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
const b64urlJson = (obj: unknown) => b64url(new TextEncoder().encode(JSON.stringify(obj)));

function pemToDer(pem: string): Uint8Array<ArrayBuffer> {
  const body = pem.replace(/-----(BEGIN|END) [A-Z ]+-----/g, "").replace(/\s+/g, "");
  return Uint8Array.from(atob(body), (c) => c.charCodeAt(0));
}

/** client_secret pro Apple = JWT podepsaný ES256 klíčem z .p8 (platnost 5 min). */
export async function clientSecret(cfg: AppleConfig, now = Date.now()): Promise<string> {
  const key = await crypto.subtle.importKey(
    "pkcs8",
    pemToDer(cfg.privateKey),
    { name: "ECDSA", namedCurve: "P-256" },
    false,
    ["sign"],
  );
  const iat = Math.floor(now / 1000);
  const header = b64urlJson({ alg: "ES256", kid: cfg.keyId });
  const payload = b64urlJson({ iss: cfg.teamId, iat, exp: iat + 300, aud: APPLE, sub: cfg.clientId });
  const input = `${header}.${payload}`;
  // WebCrypto vrací podpis jako r||s (64 B) – přesně formát, který chce JWS.
  const sig = await crypto.subtle.sign({ name: "ECDSA", hash: "SHA-256" }, key, new TextEncoder().encode(input));
  return `${input}.${b64url(new Uint8Array(sig))}`;
}

async function post(fetchFn: Fetch, path: string, form: Record<string, string>): Promise<Response> {
  return await fetchFn(`${APPLE}${path}`, {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams(form).toString(),
  });
}

/** Vymění jednorázový authorization code (platí 5 min) za refresh token. */
export async function exchangeCode(
  cfg: AppleConfig,
  code: string,
  fetchFn: Fetch = fetch,
): Promise<{ refreshToken: string; sub: string | null }> {
  const res = await post(fetchFn, "/auth/token", {
    client_id: cfg.clientId,
    client_secret: await clientSecret(cfg),
    code,
    grant_type: "authorization_code",
  });
  const body = await res.json().catch(() => ({}));
  if (!res.ok || typeof body.refresh_token !== "string") {
    throw new Error(`apple token exchange failed: ${res.status} ${body.error ?? ""}`);
  }
  return { refreshToken: body.refresh_token, sub: idTokenSub(body.id_token) };
}

/** Zneplatní refresh token (a s ním propojení appky s Apple ID uživatele). */
export async function revokeToken(cfg: AppleConfig, refreshToken: string, fetchFn: Fetch = fetch): Promise<void> {
  const res = await post(fetchFn, "/auth/revoke", {
    client_id: cfg.clientId,
    client_secret: await clientSecret(cfg),
    token: refreshToken,
    token_type_hint: "refresh_token",
  });
  if (!res.ok) throw new Error(`apple revoke failed: ${res.status} ${await res.text().catch(() => "")}`);
}

/** `sub` z id_tokenu (přišel přímo od Apple přes TLS, podpis není potřeba ověřovat). */
export function idTokenSub(idToken: unknown): string | null {
  if (typeof idToken !== "string") return null;
  try {
    const part = idToken.split(".")[1].replace(/-/g, "+").replace(/_/g, "/");
    const sub = JSON.parse(atob(part.padEnd(Math.ceil(part.length / 4) * 4, "="))).sub;
    return typeof sub === "string" ? sub : null;
  } catch {
    return null;
  }
}
