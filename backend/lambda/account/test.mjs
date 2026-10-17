// Run:  /System/Library/Frameworks/JavaScriptCore.framework/Versions/A/Helpers/jsc -m test.mjs     (or: node test.mjs)
import { makeHandler, DEACTIVATION_RETENTION_SECONDS, DELETING_GRACE_SECONDS } from "./core.mjs";

const out = typeof print === "function" ? print : console.log;
if (typeof console === "undefined") globalThis.console = { log: out, error() {} };
let failures = 0, passed = 0;
const check = (name, ok) => { if (ok) passed++; else { failures++; out("FAIL: " + name); } };

const PK = { Users: ["id"], Friends: ["userId", "otherUserId"], Grants: ["traceeId", "tracerId"], Blocks: ["blockerId", "blockedId"], TraceSessions: ["userId", "peerId"], NearbyOffers: ["userId", "fromUserId"], Positions: ["userId"], Entitlements: ["userId"], Reports: ["reportId"] };
const keyOf = (t, o) => PK[t].map((k) => o[k]).join("|");
const INDEX = { "Grants.byTracer": "tracerId", "Blocks.byBlocked": "blockedId" };
function fakeDb() {
  const t = {}; for (const n of Object.keys(PK)) t[n] = new Map();
  const db = {
    t, transactSizes: [],
    get: async (table, k) => t[table].get(keyOf(table, k)),
    put: async (table, item) => { t[table].set(keyOf(table, item), { ...item }); },
    remove: async (table, k) => { t[table].delete(keyOf(table, k)); },
    query: async (table, v) => [...t[table].values()].filter((r) => r[PK[table][0]] === v),
    queryIndex: async (table, index, attr, v) => { if (INDEX[`${table}.${index}`] !== attr) throw new Error("no such index"); return [...t[table].values()].filter((r) => r[attr] === v); },
    scan: async (table) => [...t[table].values()],
    transact: async (ops) => { db.transactSizes.push(ops.length); for (const op of ops) t[op.remove.table].delete(keyOf(op.remove.table, op.remove.key)); },
  };
  return db;
}
const ev = (routeKey, sub, body, username) => ({ routeKey, body: body === undefined ? undefined : JSON.stringify(body), requestContext: { authorizer: { jwt: { claims: { sub, username } } } } });
const J = (r) => JSON.parse(r.body);

let clock = 1_800_000_000_000;
const sec = () => clock / 1000;
const db = fakeDb();
const deleted = [];
let authFails = false;
const h = makeHandler({ db, auth: { deleteUser: async (name) => { if (authFails) throw Object.assign(new Error("x"), { name: "Boom" }); deleted.push(name); } }, now: () => clock });

function populate() {
  for (const t of Object.values(db.t)) t.clear();
  for (const id of ["me", "a", "b", "c"]) db.t.Users.set(id, { id, username: `${id}name`, email: `${id}@x` });
  const friend = (x, y) => { db.t.Friends.set(`${x}|${y}`, { userId: x, otherUserId: y, status: "ACCEPTED" }); db.t.Friends.set(`${y}|${x}`, { userId: y, otherUserId: x, status: "ACCEPTED" }); };
  friend("me", "a"); friend("me", "b"); friend("a", "b");
  db.t.Friends.set("me|c", { userId: "me", otherUserId: "c", status: "PENDING" }); db.t.Friends.set("c|me", { userId: "c", otherUserId: "me", status: "INCOMING" });
  db.t.Grants.set("me|a", { traceeId: "me", tracerId: "a", status: "ACTIVE" });          // a traces me
  db.t.Grants.set("b|me", { traceeId: "b", tracerId: "me", status: "ACTIVE" });          // I trace b
  db.t.Grants.set("a|b", { traceeId: "a", tracerId: "b", status: "ACTIVE" });            // unrelated to me
  db.t.Positions.set("me", { userId: "me", lat: 1, lon: 2 }); db.t.Positions.set("a", { userId: "a", lat: 3, lon: 4 });
  db.t.Blocks.set("me|c", { blockerId: "me", blockedId: "c" }); db.t.Blocks.set("c|me", { blockerId: "c", blockedId: "me" }); db.t.Blocks.set("a|b", { blockerId: "a", blockedId: "b" });
  db.t.TraceSessions.set("me|a", { userId: "me", peerId: "a" }); db.t.TraceSessions.set("a|me", { userId: "a", peerId: "me" });
  db.t.NearbyOffers.set("me|a", { userId: "me", fromUserId: "a" });
  db.t.Entitlements.set("me", { userId: "me", planUntil: 4_100_000_000 }); db.t.Entitlements.set("a", { userId: "a", planUntil: 1 });
  db.t.Reports.set("r1", { reportId: "r1", reporterId: "a", reportedId: "me" });
  deleted.length = 0;
}
const holdsMe = () => [...["Friends", "Grants", "Blocks", "TraceSessions", "NearbyOffers", "Positions", "Entitlements", "Users"].flatMap((n) => [...db.t[n].entries()].filter(([k, v]) => JSON.stringify(v).includes('"me"') || k.includes("me")).map(([k]) => `${n}:${k}`))];

// ---------- guards
let r = await h({ routeKey: "POST /account/delete", requestContext: {} });
check("unauthenticated refused", r.statusCode === 401);
populate();
r = await h(ev("POST /account/delete", "me", {}));
check("deleting needs an explicit confirmation", r.statusCode === 400 && db.t.Users.has("me") && deleted.length === 0);
r = await h(ev("POST /account/deactivate", "me", { confirmed: false }));
check("so does deactivating", r.statusCode === 400 && !db.t.Users.get("me").deactivated);

// ---------- delete everything
populate();
r = await h(ev("POST /account/delete", "me", { confirmed: true }, "mename"));
check("delete succeeds", r.statusCode === 200 && J(r).status === "DELETED");
check("nothing about the person is left in any table", holdsMe().length === 0);
check("other people's friendships and permissions are untouched", db.t.Friends.has("a|b") && db.t.Grants.has("a|b") && db.t.Blocks.has("a|b") && db.t.Positions.has("a") && db.t.Entitlements.has("a") && db.t.Users.has("a"));
check("the other side of every friendship is gone", !db.t.Friends.has("a|me") && !db.t.Friends.has("b|me") && !db.t.Friends.has("c|me"));
check("permissions in both roles are gone", !db.t.Grants.has("me|a") && !db.t.Grants.has("b|me"));
check("blocks made and received are gone", !db.t.Blocks.has("me|c") && !db.t.Blocks.has("c|me"));
check("the sign-in itself was removed", deleted.length === 1 && deleted[0] === "mename");
check("reports are kept (they protect other people) until they expire", db.t.Reports.has("r1"));

// ---------- repeat after a half-finished delete
populate();
authFails = true;
r = await h(ev("POST /account/delete", "me", { confirmed: true }, "mename"));
check("if the sign-in cannot be removed it says so", r.statusCode === 500);
check("the profile is already hidden and flagged so it can be finished", db.t.Users.get("me").deleting === true && db.t.Users.get("me").deactivated === true);
check("the social data is already gone", !db.t.Friends.has("a|me") && !db.t.Grants.has("me|a"));
authFails = false;
r = await h(ev("POST /account/delete", "me", { confirmed: true }, "mename"));
check("running it again finishes the job", r.statusCode === 200 && deleted.length === 1 && holdsMe().length === 0);
r = await h(ev("POST /account/delete", "me", { confirmed: true }, "mename"));
check("and a third time is harmless", r.statusCode === 200 && deleted.length === 2);

// ---------- a stopped delete is finished by the daily sweep
populate();
authFails = true; await h(ev("POST /account/delete", "me", { confirmed: true }, "mename")); authFails = false;
clock += (DELETING_GRACE_SECONDS - 60) * 1000;
let s = await h({ source: "aws.events" });
check("the sweep leaves a recent delete alone", s.swept === 0 && db.t.Users.has("me"));
clock += 120 * 1000;
s = await h({ source: "aws.events" });
check("and finishes it after a day", s.swept === 1 && !db.t.Users.has("me") && deleted.includes("mename"));

// ---------- deactivate: social data goes, the sign-in and the plan stay
populate();
r = await h(ev("POST /account/deactivate", "me", { confirmed: true }));
check("deactivation succeeds and states when it ends", r.statusCode === 200 && J(r).status === "DEACTIVATED" && J(r).deletesAt === sec() + DEACTIVATION_RETENTION_SECONDS);
check("friends, permissions, blocks and positions are gone", !db.t.Friends.has("a|me") && !db.t.Friends.has("me|a") && !db.t.Grants.has("me|a") && !db.t.Grants.has("b|me") && !db.t.Positions.has("me") && !db.t.Blocks.has("me|c") && !db.t.Blocks.has("c|me"));
check("the purchase record is kept", db.t.Entitlements.get("me").planUntil === 4_100_000_000);
check("the profile is hidden, and the sign-in kept", db.t.Users.get("me").deactivated === true && deleted.length === 0);
r = await h(ev("GET /account", "me"));
check("the account reports its state and its end date", J(r).status === "deactivated" && J(r).deletesAt === db.t.Users.get("me").deactivatedAt + DEACTIVATION_RETENTION_SECONDS);

// ---------- reactivate
r = await h(ev("POST /account/reactivate", "me"));
check("reactivation brings the profile back", r.statusCode === 200 && db.t.Users.get("me").deactivated === undefined && db.t.Users.get("me").deactivatedAt === undefined);
check("but not the friends", !db.t.Friends.has("me|a"));
r = await h(ev("GET /account", "me")); check("active again", J(r).status === "active");

// ---------- the 12-month retention is enforced
await h(ev("POST /account/deactivate", "me", { confirmed: true }));
clock += (DEACTIVATION_RETENTION_SECONDS - 3600) * 1000;
s = await h({ source: "aws.events" }); check("a deactivated account is kept for its 12 months", s.swept === 0 && db.t.Users.has("me"));
clock += 7200 * 1000;
s = await h({ source: "aws.events" });
check("then deleted completely, sign-in and plan included", s.swept === 1 && !db.t.Users.has("me") && !db.t.Entitlements.has("me") && deleted.includes("mename"));

// ---------- big accounts are removed in safe batches
populate();
for (let i = 0; i < 130; i++) { db.t.Friends.set(`me|f${i}`, { userId: "me", otherUserId: `f${i}`, status: "ACCEPTED" }); db.t.Friends.set(`f${i}|me`, { userId: `f${i}`, otherUserId: "me", status: "ACCEPTED" }); }
db.transactSizes.length = 0;
r = await h(ev("POST /account/delete", "me", { confirmed: true }, "mename"));
check("a person with 130 friends is deleted completely", r.statusCode === 200 && holdsMe().length === 0);
check("in transactions of no more than 40 operations", db.transactSizes.every((n) => n <= 40) && db.transactSizes.length > 5);

// ---------- a missing account
populate(); db.t.Users.delete("me");
r = await h(ev("GET /account", "me")); check("no account says so", r.statusCode === 404);
r = await h(ev("POST /account/deactivate", "me", { confirmed: true })); check("cannot deactivate what does not exist", r.statusCode === 404);

// ---------- failures never leak
const broken = makeHandler({ db: { ...db, get: async () => { throw Object.assign(new Error("arn:aws mename@x"), { name: "Boom" }); } }, auth: { deleteUser: async () => {} }, now: () => clock });
const saved = console.error; let logged = ""; console.error = (...x) => { logged += x.join(" "); };
r = await broken(ev("POST /account/delete", "me", { confirmed: true }, "mename")); console.error = saved;
check("a failure is a generic 500", r.statusCode === 500 && !r.body.includes("arn"));
check("the log holds the error name only", logged.includes("Boom") && !logged.includes("mename") && !logged.includes("@x"));

out(`${passed} passed, ${failures} failed`);
if (failures) throw new Error("tests failed");
