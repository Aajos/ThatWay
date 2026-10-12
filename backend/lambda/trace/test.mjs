// Run:  /System/Library/Frameworks/JavaScriptCore.framework/Versions/A/Helpers/jsc -m test.mjs     (or: node test.mjs)
import { makeHandler, ACTIVE_IDLE_SECONDS, ACTIVE_MAX_SECONDS, REQUEST_TTL_SECONDS, POSITION_MAX_AGE_SECONDS } from "./core.mjs";

const out = typeof print === "function" ? print : console.log;
if (typeof console === "undefined") globalThis.console = { log: out, error() {} };   // jsc has no console
let failures = 0, passed = 0;
const check = (name, ok) => { if (ok) passed++; else { failures++; out("FAIL: " + name); } };

function fakeDb() {
  const t = { Friends: new Map(), TraceSessions: new Map() };
  const key = (table, k) => table === "Friends" ? `${k.userId}|${k.otherUserId}` : `${k.userId}|${k.peerId}`;
  return {
    t,
    get: async (table, k) => t[table].get(key(table, k)),
    put: async (table, item) => { t[table].set(key(table, item.userId ? { userId: item.userId, peerId: item.peerId, otherUserId: item.otherUserId } : item), item); },
    query: async (table, userId) => [...t[table].values()].filter((r) => r.userId === userId),
    remove: async (table, k) => { t[table].delete(key(table, k)); },
  };
}
const befriend = (db, a, b) => { for (const [x, y] of [[a, b], [b, a]]) db.t.Friends.set(`${x}|${y}`, { userId: x, otherUserId: y, status: "ACCEPTED" }); };
const ev = (routeKey, sub, body, pathParameters) => ({ routeKey, body: body === undefined ? undefined : JSON.stringify(body), pathParameters, requestContext: { authorizer: { jwt: { claims: { sub } } } } });
const J = (r) => (r.body ? JSON.parse(r.body) : undefined);

let clock = 1_800_000_000_000, n = 0;
const db = fakeDb();
const h = makeHandler({ db, now: () => clock, makeId: () => `s${++n}` });
befriend(db, "alice", "bob"); befriend(db, "alice", "carol");
const tick = (s) => { clock += s * 1000; };

// --- requests need friendship and are validated
let r = await h(ev("POST /trace/request", "alice", { friendId: "dave" }));
check("non-friend refused", r.statusCode === 403);
r = await h(ev("POST /trace/request", "alice", { friendId: "alice" }));
check("self refused", r.statusCode === 400);
r = await h(ev("POST /trace/request", "alice", {}));
check("missing friend refused", r.statusCode === 400);
r = await h({ routeKey: "GET /trace", requestContext: {} });
check("unauthenticated refused", r.statusCode === 401);

// --- the consent flow: nothing flows until Bob says yes
r = await h(ev("POST /trace/request", "alice", { friendId: "bob" }));
check("request created", r.statusCode === 201 && J(r).status === "OUTGOING" && J(r).expiresAt === clock / 1000 + REQUEST_TTL_SECONDS);
let a = J(await h(ev("GET /trace", "alice"))), b = J(await h(ev("GET /trace", "bob")));
check("alice sees OUTGOING", a.length === 1 && a[0].status === "OUTGOING" && a[0].friendId === "bob");
check("bob sees INCOMING", b.length === 1 && b[0].status === "INCOMING" && b[0].friendId === "alice");
r = await h(ev("PUT /trace/position", "alice", { friendId: "bob", lat: -37.8, lon: 145.2, acc: 8 }));
check("no position before consent", r.statusCode === 409);
r = await h(ev("POST /trace/request", "alice", { friendId: "bob" }));
check("asking twice is idempotent", r.statusCode === 200);

// --- only the person asked can answer
r = await h(ev("POST /trace/respond", "alice", { friendId: "bob", action: "accept" }));
check("asker cannot accept their own request", r.statusCode === 404);
r = await h(ev("POST /trace/respond", "bob", { friendId: "alice", action: "maybe" }));
check("bad action refused", r.statusCode === 400);
r = await h(ev("POST /trace/respond", "bob", { friendId: "alice", action: "accept" }));
check("accepted", r.statusCode === 200 && J(r).status === "ACTIVE" && J(r).expiresAt === clock / 1000 + ACTIVE_IDLE_SECONDS);

// --- positions go to the partner only, as numbers, with an age
r = await h(ev("PUT /trace/position", "alice", { friendId: "bob", lat: -37.8, lon: 145.2, acc: 8 }));
check("position accepted", r.statusCode === 200);
r = await h(ev("PUT /trace/position", "alice", { friendId: "bob", lat: 999, lon: 0 }));
check("bad latitude refused", r.statusCode === 400);
r = await h(ev("PUT /trace/position", "alice", { friendId: "bob", lat: "x", lon: 0 }));
check("non-numeric refused", r.statusCode === 400);
b = J(await h(ev("GET /trace", "bob")));
check("bob gets alice's position", b[0].status === "ACTIVE" && b[0].peer && b[0].peer.lat === -37.8 && b[0].peer.age === 0);
a = J(await h(ev("GET /trace", "alice")));
check("alice has no position from bob yet", a[0].status === "ACTIVE" && a[0].peer === undefined);
let c = J(await h(ev("GET /trace", "carol")));
check("a third friend sees nothing", c.length === 0);
r = await h(ev("PUT /trace/position", "carol", { friendId: "alice", lat: 1, lon: 1 }));
check("an outsider cannot post a position", r.statusCode === 409);

// --- stale positions are not served
tick(POSITION_MAX_AGE_SECONDS + 1);
b = J(await h(ev("GET /trace", "bob")));
check("stale position withheld", b[0].peer === undefined);
await h(ev("PUT /trace/position", "alice", { friendId: "bob", lat: -37.81, lon: 145.21 }));
b = J(await h(ev("GET /trace", "bob")));
check("fresh position served again", b[0].peer && b[0].peer.lat === -37.81);

// --- either side can end it; both rows go
r = await h(ev("DELETE /trace/{friendId}", "bob", undefined, { friendId: "alice" }));
check("ended", r.statusCode === 204);
check("both rows removed", db.t.TraceSessions.size === 0);
r = await h(ev("PUT /trace/position", "alice", { friendId: "bob", lat: 1, lon: 1 }));
check("no position after ending", r.statusCode === 409);

// --- decline: the asker is told, and cannot spam
await h(ev("POST /trace/request", "alice", { friendId: "bob" }));
r = await h(ev("POST /trace/respond", "bob", { friendId: "alice", action: "decline" }));
check("declined", r.statusCode === 200 && J(r).status === "DECLINED");
a = J(await h(ev("GET /trace", "alice")));
check("asker sees DECLINED", a.length === 1 && a[0].status === "DECLINED");
b = J(await h(ev("GET /trace", "bob")));
check("decliner has no row left", b.length === 0);
r = await h(ev("POST /trace/request", "alice", { friendId: "bob" }));
check("cannot re-ask during the cool-off", r.statusCode === 429);
tick(61);
a = J(await h(ev("GET /trace", "alice")));
check("declined row expires", a.length === 0);
r = await h(ev("POST /trace/request", "alice", { friendId: "bob" }));
check("can ask again after the cool-off", r.statusCode === 201);

// --- both ask at once: treated as yes
db.t.TraceSessions.clear();
await h(ev("POST /trace/request", "alice", { friendId: "bob" }));
r = await h(ev("POST /trace/request", "bob", { friendId: "alice" }));
check("mutual ask activates", r.statusCode === 200 && J(r).status === "ACTIVE");

// --- requests expire; sessions expire
db.t.TraceSessions.clear();
await h(ev("POST /trace/request", "alice", { friendId: "bob" }));
tick(REQUEST_TTL_SECONDS + 1);
b = J(await h(ev("GET /trace", "bob")));
check("old request expires", b.length === 0);
r = await h(ev("POST /trace/respond", "bob", { friendId: "alice", action: "accept" }));
check("cannot accept an expired request", r.statusCode === 404);

await h(ev("POST /trace/request", "alice", { friendId: "bob" }));
await h(ev("POST /trace/respond", "bob", { friendId: "alice", action: "accept" }));
tick(ACTIVE_IDLE_SECONDS + 1);
a = J(await h(ev("GET /trace", "alice")));
check("a session nobody uses expires on its own", a.length === 0);

// --- a long trip: as long as positions keep flowing, the trace outlives the idle window
db.t.TraceSessions.clear();
await h(ev("POST /trace/request", "alice", { friendId: "bob" }));
await h(ev("POST /trace/respond", "bob", { friendId: "alice", action: "accept" }));
for (let i = 0; i < 10; i++) {                                   // ten hours, uploading every 20 minutes
  tick(20 * 60);
  await h(ev("PUT /trace/position", "alice", { friendId: "bob", lat: -37.8, lon: 145.2 }));
  await h(ev("PUT /trace/position", "bob", { friendId: "alice", lat: -37.9, lon: 145.3 }));
}
a = J(await h(ev("GET /trace", "alice")));
check("a long trip does not drop the trace partway", a.length === 1 && a[0].status === "ACTIVE" && a[0].peer && a[0].peer.lat === -37.9);

// --- a tunnel: 40 minutes without an upload is fine
tick(40 * 60);
a = J(await h(ev("GET /trace", "alice")));
check("a 40 minute dead zone does not end it", a.length === 1);

// --- the hard cap: even a healthy trace ends after 24 hours
db.t.TraceSessions.clear();
await h(ev("POST /trace/request", "alice", { friendId: "bob" }));
await h(ev("POST /trace/respond", "bob", { friendId: "alice", action: "accept" }));
let capped = false, hours = 0;
for (let i = 0; i < 60 && !capped; i++) {
  tick(30 * 60); hours += 0.5;
  r = await h(ev("PUT /trace/position", "alice", { friendId: "bob", lat: -37.8, lon: 145.2 }));
  if (r.statusCode === 409) capped = true; else await h(ev("PUT /trace/position", "bob", { friendId: "alice", lat: -37.9, lon: 145.3 }));
}
check("the 24 hour cap ends an otherwise healthy trace", capped && hours >= 24 && hours <= 24.5);
a = J(await h(ev("GET /trace", "alice"))); b = J(await h(ev("GET /trace", "bob")));
check("and neither side sees a session afterwards", a.length === 0 && b.length === 0);

// --- unfriending ends the session
db.t.TraceSessions.clear();
await h(ev("POST /trace/request", "alice", { friendId: "bob" }));
await h(ev("POST /trace/respond", "bob", { friendId: "alice", action: "accept" }));
db.t.Friends.delete("bob|alice");
a = J(await h(ev("GET /trace", "alice")));
check("unfriended session hidden", a.length === 0);
check("unfriended rows cleaned up", db.t.TraceSessions.size === 0);
befriend(db, "alice", "bob");

// --- request spam is capped
db.t.TraceSessions.clear();
for (const f of ["f1", "f2", "f3", "f4"]) befriend(db, "alice", f);
const codes = [];
for (const f of ["f1", "f2", "f3", "f4"]) codes.push((await h(ev("POST /trace/request", "alice", { friendId: f }))).statusCode);
check("open requests are capped", codes.join() === "201,201,201,429");

// --- failures never leak a position, id or body
const broken = makeHandler({ db: { get: async () => { throw Object.assign(new Error("lat -37.81 lon 145.21"), { name: "Boom" }); } }, now: () => clock });
const savedError = console.error; let logged = "";
console.error = (...x) => { logged += x.join(" "); };
r = await broken(ev("POST /trace/request", "alice", { friendId: "bob" }));
console.error = savedError;
check("500 is generic", r.statusCode === 500 && !r.body.includes("37.81"));
check("log has the error name only", logged.includes("Boom") && !logged.includes("37.81") && !logged.includes("145.21") && !logged.includes("bob"));

out(`${passed} passed, ${failures} failed`);
if (failures) throw new Error("tests failed");
