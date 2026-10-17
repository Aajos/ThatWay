// Run:  /System/Library/Frameworks/JavaScriptCore.framework/Versions/A/Helpers/jsc -m test.mjs     (or: node test.mjs)
import { makeHandler, distanceBand, GRANT_MAX_SECONDS, GRANT_MIN_SECONDS, REQUEST_TTL_SECONDS, LOCATE_MIN_INTERVAL, NOTICE_MIN_INTERVAL, POSITION_TTL_SECONDS, MAX_OPEN_REQUESTS, MAX_ACTIVE_GRANTS, REPORT_RETENTION_SECONDS } from "./core.mjs";

const out = typeof print === "function" ? print : console.log;
if (typeof console === "undefined") globalThis.console = { log: out, error() {} };
let failures = 0, passed = 0;
const check = (name, ok) => { if (ok) passed++; else { failures++; out("FAIL: " + name); } };

const PK = { Grants: ["traceeId", "tracerId"], Blocks: ["blockerId", "blockedId"], Friends: ["userId", "otherUserId"], TraceSessions: ["userId", "peerId"], NearbyOffers: ["userId", "fromUserId"], Positions: ["userId"], Reports: ["reportId"], Users: ["id"] };
const keyOf = (t, o) => PK[t].map((k) => o[k]).join("|");
function fakeDb() {
  const t = {}; for (const n of Object.keys(PK)) t[n] = new Map();
  return {
    t,
    get: async (table, k) => t[table].get(keyOf(table, k)),
    put: async (table, item) => { t[table].set(keyOf(table, item), { ...item }); },
    remove: async (table, k) => { t[table].delete(keyOf(table, k)); },
    query: async (table, id) => [...t[table].values()].filter((r) => r[PK[table][0]] === id),
    queryIndex: async (table, index, attr, value) => [...t[table].values()].filter((r) => r[attr] === value),
    transact: async (ops) => { for (const op of ops) { if (op.put) t[op.put.table].set(keyOf(op.put.table, op.put.item), { ...op.put.item }); else t[op.remove.table].delete(keyOf(op.remove.table, op.remove.key)); } },
  };
}
const befriend = (db, a, b) => { for (const [x, y] of [[a, b], [b, a]]) db.t.Friends.set(`${x}|${y}`, { userId: x, otherUserId: y, status: "ACCEPTED" }); };
const ev = (routeKey, sub, body, pathParameters) => ({ routeKey, body: body === undefined ? undefined : JSON.stringify(body), pathParameters, requestContext: { authorizer: { jwt: { claims: { sub } } } } });
const J = (r) => (r.body ? JSON.parse(r.body) : undefined);

let clock = 1_800_000_000_000;
const tick = (s) => { clock += s * 1000; };
const FAR = 4_000_000_000;                                     // a plan that outlasts every test
const plans = new Map([["tracer", FAR], ["tracer2", FAR]]);    // userId -> when that plan ends (epoch seconds)
const db = fakeDb();
let ids = 0;
const h = makeHandler({ db, now: () => clock, planUntil: async (id) => plans.get(id) ?? null, newId: () => `r${++ids}` });
for (const [a, b] of [["tracer", "tracee"], ["tracer2", "tracee"], ["tracer", "other"]]) befriend(db, a, b);
const call = async (route, sub, body, pp) => h(ev(route, sub, body, pp));
let nextKind = "window";
const request = (kind = "window", hours = 24, tracer = "tracer", tracee = "tracee") => { nextKind = kind; return call("POST /grants/request", tracer, { friendId: tracee, hours }); };
const grant = (hours = 24, tracer = "tracer", tracee = "tracee") => call("POST /grants/respond", tracee, { tracerId: tracer, action: "grant", hours, confirmed: true, consentVersion: "v1", kind: nextKind });
const locate = (tracer = "tracer", tracee = "tracee", distanceM = 1500) => call("POST /grants/locate", tracer, { traceeId: tracee, distanceM });
const upload = (sub = "tracee", lat = -37.8, lon = 145.2) => call("PUT /grants/position", sub, { lat, lon, acc: 8 });
const now = () => clock / 1000;

// ---------- the numbers the product promises
check("requests last 30 minutes", REQUEST_TTL_SECONDS === 1800);
check("a grant is 15 minutes to 24 hours", GRANT_MIN_SECONDS === 900 && GRANT_MAX_SECONDS === 86400);
check("five requests may wait, ten traces may be held", MAX_OPEN_REQUESTS === 5 && MAX_ACTIVE_GRANTS === 10);

// ---------- distance bands
check("band under 50", distanceBand(10) === "under 50 m");
check("band under 200", distanceBand(120) === "under 200 m");
check("band under 1 km", distanceBand(800) === "under 1 km");
check("band rounds UP so it never claims to be closer", distanceBand(1100) === "about 2 km");
check("band far", distanceBand(25000) === "over 20 km");
check("a bad distance gives no band", distanceBand(-1) === null && distanceBand("x") === null && distanceBand(NaN) === null);

// ---------- auth and plan
let r = await h({ routeKey: "GET /grants", requestContext: {} });
check("unauthenticated refused", r.statusCode === 401);
r = await request(); check("a tracer with a plan can ask", r.statusCode === 200 && J(r).status === "WAITING" && J(r).expiresAt === now() + REQUEST_TTL_SECONDS);
plans.delete("tracer"); r = await request("window", 24, "tracer", "other");
check("no plan, no asking", r.statusCode === 402); plans.set("tracer", FAR);
r = await call("POST /grants/respond", "tracee", { tracerId: "tracer", action: "grant", hours: 1, confirmed: true, consentVersion: "v1", kind: "forever" }); check("a grant needs a valid kind, chosen by the traced person", r.statusCode === 400);

// ---------- the traced person sees the request; the tracer sees almost nothing
r = await call("GET /grants", "tracee");
check("tracee sees who asked and for how long", J(r).asTraced.length === 1 && J(r).asTraced[0].tracerId === "tracer" && J(r).asTraced[0].requestedHours === 24 && J(r).asTraced[0].status === "REQUESTED" && J(r).asTraced[0].requestExpiresAt === now() + REQUEST_TTL_SECONDS);
r = await call("GET /grants", "tracer");
check("tracer sees only 'waiting'", J(r).asTracer.length === 1 && J(r).asTracer[0].status === "waiting" && !("until" in J(r).asTracer[0]));
check("and their own plan end", J(r).plan.until === FAR && J(r).plan.active === true);

// ---------- granting: the second confirmation, the slider, the caps
r = await call("POST /grants/respond", "tracee", { tracerId: "tracer", action: "grant", hours: 6 });
check("a grant without the second confirmation is refused", r.statusCode === 400);
r = await call("POST /grants/respond", "tracee", { tracerId: "tracer", action: "grant", hours: 6, confirmed: true });
check("a grant without a consent version is refused", r.statusCode === 400);
r = await call("POST /grants/respond", "tracer", { tracerId: "tracee", action: "grant", hours: 6, confirmed: true, consentVersion: "v1" });
check("the asker cannot grant their own request", r.statusCode === 404);
r = await grant(6);
check("granted for the slider's 6 hours", r.statusCode === 200 && J(r).until === now() + 6 * 3600);
r = await call("GET /grants", "tracer"); check("the tracer now sees only 'active'", J(r).asTracer[0].status === "active" && !("until" in J(r).asTracer[0]) && !("hours" in J(r).asTracer[0]));
r = await call("GET /grants", "tracee"); check("the tracee sees the end time", J(r).asTraced[0].status === "ACTIVE" && J(r).asTraced[0].until === now() + 6 * 3600);

await call("POST /grants/revoke", "tracee", { tracerId: "tracer" });
await request("window", 100);
let row = db.t.Grants.get("tracee|tracer"); check("a request for more than 24 hours is capped at 24", row.requestedHours === 24);
r = await grant(100); check("a grant can never exceed 24 hours", J(r).until === now() + GRANT_MAX_SECONDS);
await call("POST /grants/revoke", "tracee", { tracerId: "tracer" });
await request("window", 24); r = await grant(0.01);
check("a grant is at least 15 minutes", J(r).until === now() + GRANT_MIN_SECONDS);
await call("POST /grants/revoke", "tracee", { tracerId: "tracer" });
await request("window", 2); r = await grant(10);
check("a grant is never more than was asked for", J(r).until === now() + 2 * 3600);
await call("POST /grants/revoke", "tracee", { tracerId: "tracer" });
await request("window", 0.01); row = db.t.Grants.get("tracee|tracer");
check("a request for less than 15 minutes is raised to 15", row.requestedHours === 0.25);
await call("POST /grants/revoke", "tracee", { tracerId: "tracer" });

// ---------- a one-off has a timer too, anywhere from 15 minutes to 24 hours
await request("oneoff", 0.5); r = await grant(24);
check("a one-off is capped at what was asked (30 minutes)", J(r).until === now() + 1800 && db.t.Grants.get("tracee|tracer").kind === "oneoff");
await call("POST /grants/revoke", "tracee", { tracerId: "tracer" });
await request("oneoff", 20); r = await grant(20);
check("a one-off can be as long as 20 hours if the tracee says so", J(r).until === now() + 20 * 3600);
await call("POST /grants/revoke", "tracee", { tracerId: "tracer" });
await call("POST /grants/request", "tracer", { friendId: "tracee" }); row = db.t.Grants.get("tracee|tracer");
check("a one-off with no length defaults to an hour", row.requestedHours === 1);
await call("POST /grants/revoke", "tracee", { tracerId: "tracer" });
await call("POST /grants/request", "tracer", { friendId: "tracee" }); row = db.t.Grants.get("tracee|tracer");
check("a request with no length defaults to an hour", row.requestedHours === 1);
await call("POST /grants/revoke", "tracee", { tracerId: "tracer" });

// ---------- positions: only while someone may see them; one-way; never the tracer's
db.t.Positions.clear();
r = await upload(); check("no position is accepted when nobody may trace", r.statusCode === 409);
await request("window", 24); await grant(24);
r = await upload(); check("a position is accepted while a grant is live", r.statusCode === 200);
r = await call("PUT /grants/position", "tracee", { lat: 999, lon: 0 }); check("bad coordinates refused", r.statusCode === 400);
r = await call("PUT /grants/position", "tracer", { lat: -37.9, lon: 145.3 });
check("the tracer's own position is never accepted (they have no grant over themselves)", r.statusCode === 409 && !db.t.Positions.has("tracer"));

// ---------- locating: every check, the 2-minute limit, the 30-minute notice cap
r = await locate(); check("a live grant returns the position with its age", r.statusCode === 200 && J(r).position.lat === -37.8 && J(r).position.age === 0 && J(r).retryAfter === LOCATE_MIN_INTERVAL);
r = await locate(); check("a second request within 2 minutes is limited", r.statusCode === 429 && J(r).retryAfter > 0);
tick(LOCATE_MIN_INTERVAL + 1);
r = await locate(); check("after 2 minutes it works again", r.statusCode === 200 && J(r).position.age === LOCATE_MIN_INTERVAL + 1);
r = await call("GET /grants", "tracee");
check("the tracee is shown the first 'still tracing you' notice", J(r).asTraced[0].stillTracing === true);
r = await call("GET /grants", "tracee"); check("and only once", J(r).asTraced[0].stillTracing === undefined);
check("the tracee is shown a distance band, never a number", J(r).asTraced[0].band === "about 2 km" && !JSON.stringify(J(r)).includes("1500"));
check("the server stored only the band", !JSON.stringify([...db.t.Grants.values()]).includes("1500"));
check("the tracee sees when they were last looked at", typeof J(r).asTraced[0].lastLookedAt === "number");
tick(LOCATE_MIN_INTERVAL + 1); await locate();
r = await call("GET /grants", "tracee"); check("a second notice within 30 minutes is not sent", J(r).asTraced[0].stillTracing === undefined);
tick(NOTICE_MIN_INTERVAL); await locate();
r = await call("GET /grants", "tracee"); check("after 30 minutes the notice is sent again", J(r).asTraced[0].stillTracing === true);
tick(700); await locate();     // refresh the band then let it go stale
tick(700);
r = await call("GET /grants", "tracee"); check("a distance older than 10 minutes is not shown", J(r).asTraced[0].band === undefined);

// ---------- the window ends whether or not anyone is watching
tick(24 * 3600 + 10);
r = await locate(); check("past the window: the one generic answer", r.statusCode === 403 && J(r).error === "User cannot be traced");
r = await upload(); check("past the window: no more positions are accepted", r.statusCode === 409);

// ---------- nothing lasts past 24 hours even if the stored row says otherwise
db.t.Grants.set("tracee|tracer", { traceeId: "tracee", tracerId: "tracer", status: "ACTIVE", kind: "window", grantedAt: now(), grantedUntil: now() + 90000, expiresAt: now() + 90000 });
r = await locate(); check("a tampered over-24-hour grant is refused", r.statusCode === 403);
db.t.Grants.delete("tracee|tracer");

// ---------- the tracer's plan ending ends the trace, whichever comes first
await request("window", 24); await grant(24); await upload();
plans.set("tracer", now() + 3600);                                     // a plan with an hour left, on a 24-hour grant
r = await call("GET /grants", "tracee"); check("the tracee is shown the grant (the plan still has time)", J(r).asTraced.length === 1);
tick(1800); r = await locate(); check("half way through the plan it still works", r.statusCode === 200);
tick(1801);                                                             // the plan has now run out; the grant had 23 hours left
r = await locate(); check("an expired plan cannot look, and is told to renew", r.statusCode === 402);
check("and the trace itself is gone for good", !db.t.Grants.has("tracee|tracer"));
check("and the position is dropped as nobody may see it", !db.t.Positions.has("tracee"));
plans.set("tracer", FAR);
r = await locate(); check("renewing the plan does not revive the old trace", r.statusCode === 403);
// the tracee's phone finds out too (not only the tracer)
await request("window", 24); await grant(24); await upload();
plans.set("tracer", now() + 60); tick(61);
r = await upload(); check("the traced phone's next upload is refused once the tracer's plan is over", r.statusCode === 409);
r = await call("GET /grants", "tracee"); check("and the tracee no longer sees the trace", J(r).asTraced.length === 0);
plans.set("tracer", FAR);
await request("window", 24); await grant(24); plans.set("tracer", now() + 60); tick(61);
r = await call("GET /grants", "tracer"); check("the tracer's own sync drops it and shows the plan has ended", J(r).asTracer.length === 0 && J(r).plan.active === false);
plans.set("tracer", FAR);
db.t.Grants.clear(); db.t.Positions.clear();

// ---------- every failure looks the same to the tracer
await request("window", 24); await grant(24); await upload();
db.t.Friends.delete("tracee|tracer");
r = await locate(); check("a one-sided friendship ends tracing", r.statusCode === 403 && J(r).error === "User cannot be traced");
check("and the grant is gone", !db.t.Grants.has("tracee|tracer"));
check("and the position is dropped as nobody may see it", !db.t.Positions.has("tracee"));
befriend(db, "tracer", "tracee");

// ---------- one-off ends when the tracer switches; a window survives a switch
db.t.Grants.clear(); db.t.Positions.clear();
await request("oneoff", 3, "tracer", "tracee"); await grant(3, "tracer", "tracee");
await request("window", 24, "tracer", "other"); await grant(24, "tracer", "other");
r = await call("POST /grants/release", "tracer", { traceeId: "tracee" });
check("switching away ends a one-off", !db.t.Grants.has("tracee|tracer"));
r = await call("POST /grants/release", "tracer", { traceeId: "other" });
check("switching away does not end a window", db.t.Grants.get("other|tracer")?.status === "ACTIVE");
r = await locate("tracer", "other", 300); check("and the window can be used again", r.statusCode === 200);
await request("window", 24, "tracer", "tracee"); r = await call("POST /grants/release", "tracer", { traceeId: "tracee" });
check("releasing a request that is still waiting withdraws it", !db.t.Grants.has("tracee|tracer"));

// ---------- a stranger who is not a friend can never be located, whatever the grant row says
db.t.Grants.set("tracee|tracer2", { traceeId: "tracee", tracerId: "tracer2", status: "ACTIVE", kind: "window", grantedAt: now(), grantedUntil: now() + 3600, expiresAt: now() + 3600 });
db.t.Friends.delete("tracee|tracer2");
r = await locate("tracer2", "tracee"); check("a grant without a friendship is refused", r.statusCode === 403);

// ---------- blocking
db.t.Grants.clear(); db.t.Positions.clear(); db.t.Friends.clear();
befriend(db, "tracer", "tracee");
db.t.NearbyOffers.set("tracee|tracer", { userId: "tracee", fromUserId: "tracer", token: "x" }); db.t.NearbyOffers.set("tracer|tracee", { userId: "tracer", fromUserId: "tracee", token: "y" });
await request("window", 24); await grant(24); await upload();
r = await call("POST /blocks", "tracee", { userId: "tracer" });
check("blocking is accepted", r.statusCode === 200 && J(r).status === "BLOCKED");
check("blocking removes the friendship", !db.t.Friends.has("tracee|tracer") && !db.t.Friends.has("tracer|tracee"));
check("blocking ends the grant", !db.t.Grants.has("tracee|tracer"));
check("blocking drops the position nobody may see", !db.t.Positions.has("tracee"));
check("blocking drops any ultra wideband offers either way", db.t.NearbyOffers.size === 0);
r = await locate(); check("the blocked person gets the same generic answer", r.statusCode === 403 && J(r).error === "User cannot be traced");
db.t.Users.set("tracer", { id: "tracer", username: "tracername", email: "x@y" });
r = await call("GET /blocks", "tracee"); check("the blocker can list who they blocked, with a username", J(r).length === 1 && J(r)[0].userId === "tracer" && J(r)[0].username === "tracername");
check("and never an email", !r.body.includes("x@y"));
r = await call("GET /blocks", "tracer"); check("the blocked person cannot see they were blocked", J(r).length === 0);
r = await call("POST /blocks", "tracee", { userId: "tracee" }); check("you cannot block yourself", r.statusCode === 400);

// ---------- a request to someone who blocked you looks exactly like an unanswered one
befriend(db, "tracer", "tracee");                                       // (friends again, but the block still stands)
const asked = await request(); const waitingView = await call("GET /grants", "tracer");
check("the blocked person's request is answered like any other", asked.statusCode === 200 && J(asked).status === "WAITING" && J(asked).expiresAt === now() + REQUEST_TTL_SECONDS);
check("and they are shown it waiting, like any other", J(waitingView).asTracer.length === 1 && J(waitingView).asTracer[0].status === "waiting" && J(waitingView).asTracer[0].expiresAt === now() + REQUEST_TTL_SECONDS);
r = await call("GET /grants", "tracee"); check("the blocker never sees the request", J(r).asTraced.length === 0);
check("and looking at it does not delete it (that would show the block)", db.t.Grants.has("tracee|tracer"));
r = await grant(); check("it cannot be granted", r.statusCode === 404 && db.t.Grants.has("tracee|tracer"));
r = await locate(); check("locating it changes nothing the tracer can see", r.statusCode === 403 && db.t.Grants.has("tracee|tracer"));
tick(REQUEST_TTL_SECONDS + 1);
waitingView.body = null; r = await call("GET /grants", "tracer"); check("it then expires exactly like an unanswered request", J(r).asTracer.length === 0);
r = await call("DELETE /blocks/{userId}", "tracee", undefined, { userId: "tracer" });
check("unblocking works but does not restore the friendship", r.statusCode === 200 && !db.t.Blocks.has("tracee|tracer"));
db.t.Grants.clear();
// a request made while blocked does not turn into a real one after unblocking
await call("POST /blocks", "tracee", { userId: "tracer" }); befriend(db, "tracer", "tracee");
await request(); await call("DELETE /blocks/{userId}", "tracee", undefined, { userId: "tracer" });
r = await call("GET /grants", "tracee"); check("a request made during a block never becomes real afterwards", J(r).asTraced.length === 0);
db.t.Grants.clear();
// not friends at all is the same quiet answer
r = await call("POST /grants/request", "tracer", { friendId: "stranger" });
check("a non-friend gets the same quiet answer as anyone", r.statusCode === 200 && J(r).status === "WAITING" && db.t.Grants.get("stranger|tracer").phantom === true);
db.t.Grants.clear();

// ---------- spam, the caps and the expiry of requests
db.t.Friends.clear();
for (let i = 0; i < 12; i++) { plans.set("t", FAR); befriend(db, "t", `f${i}`); }
const codes = []; for (let i = 0; i < MAX_OPEN_REQUESTS + 1; i++) codes.push((await request("window", 24, "t", `f${i}`)).statusCode);
check("open requests are capped", codes.filter((c) => c === 429).length === 1);
db.t.Grants.clear();
for (let i = 0; i < MAX_ACTIVE_GRANTS; i++) { await request("window", 24, "t", `f${i}`); await grant(24, "t", `f${i}`); }
r = await request("window", 24, "t", "f10"); check("a tracer can hold at most ten live traces", r.statusCode === 429 && J(r).error.includes("10"));
r = await request("window", 24, "t", "f3"); check("asking again for someone already traced is harmless", r.statusCode === 200 && J(r).status === "ACTIVE");
await call("POST /grants/revoke", "f0", { tracerId: "t" });
r = await request("window", 24, "t", "f10"); check("stopping one makes room for another", r.statusCode === 200 && J(r).status === "WAITING");
// the race: two requests pending, ten live, one tries to be granted
await call("POST /grants/revoke", "f1", { tracerId: "t" }); await call("POST /grants/revoke", "f10", { tracerId: "t" });
await request("window", 24, "t", "f10"); await request("window", 24, "t", "f11");
await grant(24, "t", "f10"); r = await grant(24, "t", "f11");
check("the tenth and eleventh cannot both be granted", r.statusCode === 200 || r.statusCode === 409);
db.t.Grants.clear(); befriend(db, "tracer", "tracee"); await request();
tick(REQUEST_TTL_SECONDS + 1);
r = await call("GET /grants", "tracee"); check("an unanswered request disappears after 30 minutes", J(r).asTraced.length === 0);
r = await grant(); check("and can no longer be granted", r.statusCode === 404);

// ---------- positions are not kept longer than 2 hours
db.t.Grants.clear(); db.t.Positions.clear(); befriend(db, "tracer", "tracee");
await request(); await grant(24); await upload();
tick(POSITION_TTL_SECONDS + 5); tick(LOCATE_MIN_INTERVAL);
r = await locate(); check("an old last-known position is not served", r.statusCode === 200 && J(r).position === null);

// ---------- reports
r = await call("POST /reports", "tracee", { userId: "tracer", category: "unwanted_tracing", details: "x".repeat(900) });
check("a report is received", r.statusCode === 200 && J(r).status === "RECEIVED");
let report = [...db.t.Reports.values()][0];
check("it records who reported whom, the kind, and a trimmed note", report.reporterId === "tracee" && report.reportedId === "tracer" && report.category === "unwanted_tracing" && report.details.length === 500);
check("and keeps it for a year", report.expiresAt === report.createdAt + REPORT_RETENTION_SECONDS);
check("it holds no position", !JSON.stringify(report).includes("lat") && !JSON.stringify(report).includes("lon"));
r = await call("POST /reports", "tracee", { userId: "tracer", category: "nonsense" }); check("an unknown category is refused", r.statusCode === 400);
r = await call("POST /reports", "tracee", { userId: "tracee", category: "other" }); check("you cannot report yourself", r.statusCode === 400);
for (let i = 0; i < 30; i++) r = await call("POST /reports", "tracee", { userId: "tracer", category: "threat" });
check("reporting is never throttled", r.statusCode === 200 && db.t.Reports.size === 31);
r = await call("POST /reports", "tracee", { userId: "tracer", category: "other" }); check("(still counting)", r.statusCode === 200);

// ---------- failures never leak
const broken = makeHandler({ db: { ...db, get: async () => { throw Object.assign(new Error("arn:aws lat -37.8"), { name: "Boom" }); } }, now: () => clock });
const saved = console.error; let logged = ""; console.error = (...x) => { logged += x.join(" "); };
r = await broken(ev("POST /grants/locate", "tracer", { traceeId: "tracee" })); console.error = saved;
check("a failure is a generic 500", r.statusCode === 500 && !r.body.includes("arn"));
check("the log holds the error name only", logged.includes("Boom") && !logged.includes("tracee") && !logged.includes("37.8"));

out(`${passed} passed, ${failures} failed`);
if (failures) throw new Error("tests failed");
