// Run:  /System/Library/Frameworks/JavaScriptCore.framework/Versions/A/Helpers/jsc -m test.mjs     (or: node test.mjs)
import { makeHandler, OFFER_TTL_SECONDS } from "./core.mjs";

const out = typeof print === "function" ? print : console.log;
if (typeof console === "undefined") globalThis.console = { log: out, error() {} };   // jsc has no console
let failures = 0, passed = 0;
const check = (name, ok) => { if (ok) passed++; else { failures++; out("FAIL: " + name); } };

function fakeDb() {
  const tables = { Friends: new Map(), NearbyOffers: new Map() };
  const key = (t, k) => t === "Friends" ? `${k.userId}|${k.otherUserId}` : `${k.userId}|${k.fromUserId}`;
  return {
    tables,
    get: async (t, k) => tables[t].get(key(t, k)),
    put: async (t, item) => { tables[t].set(key(t, item), item); },
    query: async (t, userId) => [...tables[t].values()].filter((r) => r.userId === userId),
    remove: async (t, k) => { tables[t].delete(key(t, k)); },
  };
}
const befriend = (db, a, b) => { db.tables.Friends.set(`${a}|${b}`, { userId: a, otherUserId: b, status: "ACCEPTED" }); db.tables.Friends.set(`${b}|${a}`, { userId: b, otherUserId: a, status: "ACCEPTED" }); };
const ev = (routeKey, sub, body, pathParameters) => ({ routeKey, body: body === undefined ? undefined : JSON.stringify(body), pathParameters, requestContext: { authorizer: { jwt: { claims: { sub } } } } });
const parse = (r) => (r.body ? JSON.parse(r.body) : undefined);

let clock = 1_000_000_000_000;
const db = fakeDb();
const handler = makeHandler({ db, now: () => clock });
befriend(db, "alice", "bob");

// Offers go only to accepted friends
let r = await handler(ev("PUT /nearby/offers", "alice", { friendId: "carol", token: "QUJD", kind: "uwb" }));
check("non-friend refused", r.statusCode === 403);
r = await handler(ev("PUT /nearby/offers", "alice", { friendId: "alice", token: "QUJD", kind: "uwb" }));
check("self refused", r.statusCode === 400);
r = await handler(ev("PUT /nearby/offers", "alice", { friendId: "bob", token: "not base64!!", kind: "uwb" }));
check("bad token refused", r.statusCode === 400);
r = await handler(ev("PUT /nearby/offers", "alice", { friendId: "bob", token: "QUJD", kind: "wifi" }));
check("unknown kind refused", r.statusCode === 400);
r = await handler(ev("PUT /nearby/offers", "alice", { friendId: "bob", token: "A".repeat(5000), kind: "uwb" }));
check("oversized token refused", r.statusCode === 400);
r = await handler({ routeKey: "PUT /nearby/offers", body: "{", requestContext: { authorizer: { jwt: { claims: { sub: "alice" } } } } });
check("broken JSON refused", r.statusCode === 400);
r = await handler({ routeKey: "GET /nearby/offers", requestContext: {} });
check("unauthenticated refused", r.statusCode === 401);

// Round trip: alice offers, bob sees it, alice does not see her own
r = await handler(ev("PUT /nearby/offers", "alice", { friendId: "bob", token: "QUJDREVG", kind: "uwb" }));
check("offer accepted", r.statusCode === 200 && parse(r).expiresAt === clock / 1000 + OFFER_TTL_SECONDS);
r = await handler(ev("GET /nearby/offers", "bob"));
let offers = parse(r);
check("bob sees alice's offer", r.statusCode === 200 && offers.length === 1 && offers[0].friendId === "alice" && offers[0].token === "QUJDREVG" && offers[0].kind === "uwb");
r = await handler(ev("GET /nearby/offers", "alice"));
check("alice sees nothing", parse(r).length === 0);

// Offers expire even before DynamoDB's TTL sweeper removes them
clock += (OFFER_TTL_SECONDS + 1) * 1000;
r = await handler(ev("GET /nearby/offers", "bob"));
check("expired offer hidden", parse(r).length === 0);

// An offer from someone who has since unfriended is not served
clock += 1000;
await handler(ev("PUT /nearby/offers", "alice", { friendId: "bob", token: "QUJD", kind: "ble" }));
db.tables.Friends.delete("bob|alice");
r = await handler(ev("GET /nearby/offers", "bob"));
check("unfriended offer hidden", parse(r).length === 0);
befriend(db, "alice", "bob");

// Ending a session clears both directions
await handler(ev("PUT /nearby/offers", "bob", { friendId: "alice", token: "QUJD", kind: "uwb" }));
r = await handler(ev("DELETE /nearby/offers/{friendId}", "alice", undefined, { friendId: "bob" }));
check("delete ok", r.statusCode === 204);
check("both directions cleared", db.tables.NearbyOffers.size === 0);

// Failures never echo internals or tokens
const broken = makeHandler({ db: { get: async () => { throw Object.assign(new Error("secret QUJD"), { name: "Boom" }); } }, now: () => clock });
const savedError = console.error; let logged = "";
console.error = (...a) => { logged += a.join(" "); };
r = await broken(ev("PUT /nearby/offers", "alice", { friendId: "bob", token: "QUJD", kind: "uwb" }));
console.error = savedError;
check("500 is generic", r.statusCode === 500 && !r.body.includes("secret"));
check("log has the error name only", logged.includes("Boom") && !logged.includes("QUJD") && !logged.includes("secret"));

out(`${passed} passed, ${failures} failed`);
if (failures) throw new Error("tests failed");
