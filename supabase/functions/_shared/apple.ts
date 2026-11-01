// Revokes a person's Sign in with Apple token, which Apple requires on account deletion.
// https://developer.apple.com/documentation/sign_in_with_apple/revoke_tokens

const APPLE_ID = "https://appleid.apple.com";

export interface AppleKey {
  teamID: string;
  keyID: string;
  clientID: string; // the app's bundle ID
  privateKey: string; // the .p8 file's contents
}

function base64URL(bytes: Uint8Array): string {
  return btoa(String.fromCharCode(...bytes)).replaceAll("+", "-").replaceAll("/", "_").replaceAll("=", "");
}

function jsonPart(value: unknown): string {
  return base64URL(new TextEncoder().encode(JSON.stringify(value)));
}

// Secrets dashboards often store a .p8 file's line breaks as a literal "\n", so both are read.
function pkcs8(pem: string): Uint8Array {
  const body = pem.replace(/-----[A-Z ]+-----/g, "").replaceAll("\\n", "").replace(/\s/g, "");
  return Uint8Array.from(atob(body), (character) => character.charCodeAt(0));
}

// Apple's client secret is a short-lived ES256 token signed with the Sign in with Apple key.
export async function appleClientSecret(key: AppleKey, nowSeconds = Math.floor(Date.now() / 1000)): Promise<string> {
  const signingKey = await crypto.subtle.importKey(
    "pkcs8",
    pkcs8(key.privateKey),
    { name: "ECDSA", namedCurve: "P-256" },
    false,
    ["sign"],
  );
  const unsigned = `${jsonPart({ alg: "ES256", kid: key.keyID })}.${
    jsonPart({ iss: key.teamID, iat: nowSeconds, exp: nowSeconds + 300, aud: APPLE_ID, sub: key.clientID })
  }`;
  const signature = await crypto.subtle.sign(
    { name: "ECDSA", hash: "SHA-256" },
    signingKey,
    new TextEncoder().encode(unsigned),
  );
  return `${unsigned}.${base64URL(new Uint8Array(signature))}`;
}

async function post(path: string, fields: Record<string, string>): Promise<Response> {
  const response = await fetch(`${APPLE_ID}${path}`, {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams(fields),
  });
  if (!response.ok) {
    throw new Error(`${path} returned ${response.status}: ${await response.text()}`);
  }
  return response;
}

// Exchanges the code from a fresh Apple confirmation for a token, then revokes that token.
export async function revokeWithKey(code: string, key: AppleKey): Promise<void> {
  const client = { client_id: key.clientID, client_secret: await appleClientSecret(key) };
  const exchange = await post("/auth/token", { ...client, code, grant_type: "authorization_code" });
  const { refresh_token: refreshToken, access_token: accessToken } = await exchange.json();
  const token = refreshToken ?? accessToken;
  if (!token) {
    throw new Error("/auth/token returned no token");
  }
  await post("/auth/revoke", {
    ...client,
    token,
    token_type_hint: refreshToken ? "refresh_token" : "access_token",
  });
}

export function revokeAppleToken(code: string): Promise<void> {
  const setting = (name: string) => {
    const value = Deno.env.get(name);
    if (!value) throw new Error(`${name} is not set`);
    return value;
  };
  return revokeWithKey(code, {
    teamID: setting("APPLE_TEAM_ID"),
    keyID: setting("APPLE_KEY_ID"),
    clientID: setting("APPLE_CLIENT_ID"),
    privateKey: setting("APPLE_PRIVATE_KEY"),
  });
}
