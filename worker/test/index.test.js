import assert from "node:assert/strict";
import { test } from "node:test";
import worker, { buildPush, signJWT } from "../src/index.js";

const env = { BUNDLE_ID: "com.yetra.nest", NEST_KEY: "secret" };
const token = "ab".repeat(32);

test("start payload carries attributes, content state and alert", () => {
  const push = buildPush(
    {
      type: "liveactivity", event: "start", token,
      attributesType: "NestedTimerAttributes",
      attributes: { entryID: "x", kind: "nursing", babyName: "Maddie" },
      contentState: { side: "left" },
      alert: { title: "Yvette started nursing", body: "Nursing now" },
    },
    env, 1000);
  assert.equal(push.headers["apns-push-type"], "liveactivity");
  assert.equal(push.headers["apns-topic"], "com.yetra.nest.push-type.liveactivity");
  assert.equal(push.payload.aps.event, "start");
  assert.equal(push.payload.aps["attributes-type"], "NestedTimerAttributes");
  assert.deepEqual(push.payload.aps["content-state"], { side: "left" });
  assert.equal(push.payload.aps.timestamp, 1000);
});

test("end payload dismisses shortly after", () => {
  const push = buildPush({ type: "liveactivity", event: "end", token, contentState: {} }, env, 1000);
  assert.equal(push.payload.aps["dismissal-date"], 1005);
});

test("background push wakes the app", () => {
  const push = buildPush({ type: "background", token }, env, 1000);
  assert.equal(push.headers["apns-push-type"], "background");
  assert.equal(push.payload.aps["content-available"], 1);
});

test("activity push is a quiet alert that also wakes the app", () => {
  const push = buildPush({ type: "activity", token, title: "Yvette logged a diaper", body: "Wet" }, env, 1000);
  assert.equal(push.headers["apns-push-type"], "alert");
  assert.equal(push.headers["apns-topic"], "com.yetra.nest");
  assert.equal(push.headers["apns-collapse-id"], "nested-activity");
  assert.equal(push.payload.aps["interruption-level"], "passive");
  assert.equal(push.payload.aps["content-available"], 1);
  assert.equal(push.payload.aps.sound, undefined);
  assert.equal(push.payload.aps.alert.title, "Yvette logged a diaper");
  assert.throws(() => buildPush({ type: "activity", token, body: "x" }, env, 1));
});

test("rejects bad input", () => {
  assert.throws(() => buildPush({ type: "liveactivity", event: "start", token }, env, 1));
  assert.throws(() => buildPush({ type: "liveactivity", event: "start", token: "../x" }, env, 1));
  assert.throws(() => buildPush({ type: "nope", token }, env, 1));
});

test("unauthorized requests are refused", async () => {
  const response = await worker.fetch(
    new Request("https://w/push", { method: "POST", headers: { Authorization: "Bearer wrong" }, body: "{}" }),
    env);
  assert.equal(response.status, 401);
});

test("ES256 JWT verifies with the matching public key", async () => {
  const pair = await crypto.subtle.generateKey({ name: "ECDSA", namedCurve: "P-256" }, true, ["sign", "verify"]);
  const pkcs8 = Buffer.from(await crypto.subtle.exportKey("pkcs8", pair.privateKey)).toString("base64");
  const pem = `-----BEGIN PRIVATE KEY-----\n${pkcs8}\n-----END PRIVATE KEY-----`;
  const jwt = await signJWT(pem, "KEY1234567", "TEAM123456", 1700000000);
  const [header, claims, signature] = jwt.split(".");
  assert.deepEqual(JSON.parse(Buffer.from(header, "base64url")), { alg: "ES256", kid: "KEY1234567" });
  assert.deepEqual(JSON.parse(Buffer.from(claims, "base64url")), { iss: "TEAM123456", iat: 1700000000 });
  const ok = await crypto.subtle.verify(
    { name: "ECDSA", hash: "SHA-256" }, pair.publicKey,
    Buffer.from(signature, "base64url"), new TextEncoder().encode(`${header}.${claims}`));
  assert.ok(ok);
});
