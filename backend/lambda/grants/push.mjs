// Sends a push to a person's phones through Apple's APNs (token-based auth with the team's .p8 key, held in AWS Parameter
// Store, never in the repo). Node only. Best effort: callers ignore failures. What a push says is deliberately small and says
// nothing a lock screen should not show beyond who is asking: no place, no distance, no time.
import http2 from "node:http2";
import { createPrivateKey, sign } from "node:crypto";
import { SSMClient, GetParametersCommand } from "@aws-sdk/client-ssm";

const TOPIC = "com.thatway.app";
const HOSTS = { sandbox: "https://api.sandbox.push.apple.com", production: "https://api.push.apple.com" };
const ssm = new SSMClient({ region: "ap-southeast-2" });
let creds = null, jwt = null, jwtAt = 0;

export const message = (kind, name) => kind === "still"
  ? { title: `${name} is still tracing you`, body: "Open ThatWay to stop it." }
  : kind === "near"
    ? { title: `${name} is nearby, looking for you`, body: "Open ThatWay so they can find you precisely. You can stop it there too." }
    : { title: `${name} wants to trace you`, body: "Open ThatWay to review it. Nothing is shared unless you say yes." };

async function credentials() {
  if (creds) return creds;
  const out = await ssm.send(new GetParametersCommand({ Names: ["/thatway/apns/key", "/thatway/apns/keyId", "/thatway/apns/teamId"], WithDecryption: true }));
  const v = Object.fromEntries(out.Parameters.map((p) => [p.Name.split("/").pop(), p.Value]));
  creds = { key: createPrivateKey(v.key), keyId: v.keyId, teamId: v.teamId };
  return creds;
}

const b64 = (o) => Buffer.from(typeof o === "string" ? o : JSON.stringify(o)).toString("base64url");
async function token() {
  const c = await credentials();
  const now = Math.floor(Date.now() / 1000);
  if (jwt && now - jwtAt < 2400) return jwt;                    // Apple wants a token refreshed between 20 and 60 minutes
  const head = `${b64({ alg: "ES256", kid: c.keyId })}.${b64({ iss: c.teamId, iat: now })}`;
  jwt = `${head}.${sign("sha256", Buffer.from(head), { key: c.key, dsaEncoding: "ieee-p1363" }).toString("base64url")}`;
  jwtAt = now;
  return jwt;
}

/** Returns "ok", "gone" (the token is dead: delete it) or "failed". */
export async function sendPush({ deviceToken, environment, kind, name }) {
  const m = message(kind, name);
  const body = JSON.stringify({ aps: { alert: m, sound: "default", "thread-id": "trace" } });
  const bearer = await token();
  return new Promise((resolve) => {
    const client = http2.connect(HOSTS[environment] ?? HOSTS.production);
    const done = (r) => { try { client.close(); } catch { /* already closed */ } resolve(r); };
    client.on("error", () => done("failed"));
    const req = client.request({ ":method": "POST", ":path": `/3/device/${deviceToken}`, authorization: `bearer ${bearer}`, "apns-topic": TOPIC, "apns-push-type": "alert", "apns-priority": "10", "content-type": "application/json" });
    let status = 0;
    req.on("response", (h) => { status = h[":status"]; });
    req.on("data", () => {});
    req.on("end", () => done(status === 200 ? "ok" : status === 410 || status === 400 ? "gone" : "failed"));
    req.on("error", () => done("failed"));
    req.setTimeout(5000, () => { req.close(); done("failed"); });
    req.end(body);
  });
}
