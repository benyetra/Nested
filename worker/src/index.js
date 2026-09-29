// Nest push Worker: the only server piece. The app calls it when a timer starts, changes or
// stops, and when the feed alarm is stopped, so the partner's phone updates within seconds
// even when Nest isn't running there. It holds the APNs .p8 key; nothing is stored.

const encoder = new TextEncoder();
let cachedToken = null; // { jwt, issuedAt }

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    if (request.method !== "POST" || url.pathname !== "/push") {
      return new Response("Not found", { status: 404 });
    }
    if (!env.NEST_KEY || request.headers.get("Authorization") !== `Bearer ${env.NEST_KEY}`) {
      return new Response("Unauthorized", { status: 401 });
    }
    let body;
    try {
      body = await request.json();
    } catch {
      return new Response("Bad JSON", { status: 400 });
    }
    let push;
    try {
      push = buildPush(body, env, Math.floor(Date.now() / 1000));
    } catch (error) {
      return new Response(String(error.message), { status: 400 });
    }
    const jwt = await providerToken(env);
    const host = env.APNS_ENV === "development" ? "api.sandbox.push.apple.com" : "api.push.apple.com";
    const response = await fetch(`https://${host}/3/device/${push.token}`, {
      method: "POST",
      headers: { authorization: `bearer ${jwt}`, ...push.headers },
      body: JSON.stringify(push.payload),
    });
    return new Response(await response.text(), { status: response.status });
  },
};

/** Builds APNs headers and payload for a request from the app. */
export function buildPush(body, env, now) {
  const token = String(body.token || "");
  if (!/^[0-9a-f]{32,200}$/i.test(token)) throw new Error("Bad device token");

  if (body.type === "background") {
    // Wakes the partner's app so it syncs and reschedules (e.g. alarm stopped).
    return {
      token,
      headers: { "apns-push-type": "background", "apns-topic": env.BUNDLE_ID, "apns-priority": "5" },
      payload: { aps: { "content-available": 1 } },
    };
  }

  if (body.type !== "liveactivity") throw new Error("Unknown type");
  const event = body.event;
  if (!["start", "update", "end"].includes(event)) throw new Error("Unknown event");

  const aps = { timestamp: now, event, "content-state": body.contentState || {} };
  if (event === "start") {
    if (!body.attributesType || !body.attributes) throw new Error("Start needs attributes");
    aps["attributes-type"] = body.attributesType;
    aps.attributes = body.attributes;
    if (body.alert) aps.alert = { title: String(body.alert.title || ""), body: String(body.alert.body || "") };
  }
  if (event === "end") aps["dismissal-date"] = now + 5;

  return {
    token,
    headers: {
      "apns-push-type": "liveactivity",
      "apns-topic": `${env.BUNDLE_ID}.push-type.liveactivity`,
      "apns-priority": "10",
    },
    payload: { aps },
  };
}

/** ES256 provider token, reused for 50 minutes (APNs allows up to 60). */
export async function providerToken(env, nowSeconds = Math.floor(Date.now() / 1000)) {
  if (cachedToken && nowSeconds - cachedToken.issuedAt < 50 * 60) return cachedToken.jwt;
  const jwt = await signJWT(env.APNS_KEY, env.APNS_KEY_ID, env.APNS_TEAM_ID, nowSeconds);
  cachedToken = { jwt, issuedAt: nowSeconds };
  return jwt;
}

export async function signJWT(pem, keyID, teamID, issuedAt) {
  const header = base64url(encoder.encode(JSON.stringify({ alg: "ES256", kid: keyID })));
  const claims = base64url(encoder.encode(JSON.stringify({ iss: teamID, iat: issuedAt })));
  const key = await crypto.subtle.importKey(
    "pkcs8",
    pemToDer(pem),
    { name: "ECDSA", namedCurve: "P-256" },
    false,
    ["sign"],
  );
  // WebCrypto returns the raw r||s signature, which is what JWS ES256 expects.
  const signature = await crypto.subtle.sign(
    { name: "ECDSA", hash: "SHA-256" },
    key,
    encoder.encode(`${header}.${claims}`),
  );
  return `${header}.${claims}.${base64url(new Uint8Array(signature))}`;
}

function pemToDer(pem) {
  const b64 = String(pem).replace(/-----[^-]+-----/g, "").replace(/\s+/g, "");
  const binary = atob(b64);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);
  return bytes.buffer;
}

function base64url(bytes) {
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}
