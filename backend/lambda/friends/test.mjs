// Run:  /System/Library/Frameworks/JavaScriptCore.framework/Versions/A/Helpers/jsc -m test.mjs     (or: node test.mjs)
import { makeHandler, MAX_OPEN_REQUESTS, REQUEST_TTL_SECONDS } from "./core.mjs";

const out = typeof print === "function" ? print : console.log;
if (typeof console === "undefined") globalThis.console = { log: out, error() {} };
let failures = 0, passed = 0;
const check = (name, ok) => { if (ok) passed++; else { failures++; out("FAIL: " + name); } };

function fakeDb() {
  const t = { Users: new Map(), Friends: new Map(), Blocks: new Map() };
  const fk = (k) => `${k.userId}|${k.otherUserId}`;
  const key = (table, k) => table === "Users" ? k.id : table === "Blocks" ? `${k.blockerId}|${k.blockedId}` : fk(k);
  const db = {
    t, failNextTransact: null, transactCalls: 0,
    get: async (table, k) => t[table].get(key(table, k)),
    query: async (table, userId) => [...t[table].values()].filter((r) => r.userId === userId),
    queryIndex: async (table, index, attr, value) => [...t[table].values()].filter((r) => r[attr] === value),
    transact: async (ops) => {
      db.transactCalls++;
      if (db.failNextTransact) { const e = db.failNextTransact; db.failNextTransact = null; throw e; }
      // all-or-nothing, with the absent-key condition
      for (const op of ops) if (op.put?.absentKey && t[op.put.table].has(key(op.put.table, op.put.item)))
        throw Object.assign(new Error("cancelled"), { name: "TransactionCanceledException" });
      for (const op of ops) {
        if (op.put) t[op.put.table].set(key(op.put.table, op.put.item), op.put.item);
        else t[op.remove.table].delete(key(op.remove.table, op.remove.key));
      }
    },
  };
  return db;
}
const ev = (routeKey, sub, body, extra = {}) => ({ routeKey, body: body === undefined ? undefined : JSON.stringify(body), requestContext: { authorizer: { jwt: { claims: { sub } } } }, ...extra });
const J = (r) => JSON.parse(r.body);

const db = fakeDb();
let clock = 1_800_000_000_000;
const h = makeHandler({ db, now: () => clock });
db.t.Users.set("alice", { id: "alice", username: "Alice", email: "alice@secret.example" });
db.t.Users.set("bob", { id: "bob", username: "bob", email: "bob@secret.example" });
db.t.Users.set("carol", { id: "carol", username: "carol", email: "carol@secret.example" });

let r = await h({ routeKey: "GET /friends", requestContext: {} });
check("unauthenticated refused", r.statusCode === 401);

// ---- search: id and username only, never an email, never myself
r = await h(ev("GET /friends/search", "alice", undefined, { queryStringParameters: { username: "bob" } }));
check("search finds bob", r.statusCode === 200 && J(r).length === 1 && J(r)[0].id === "bob" && J(r)[0].username === "bob");
check("search never returns an email", !r.body.includes("secret.example") && !("email" in J(r)[0]));
r = await h(ev("GET /friends/search", "alice", undefined, { queryStringParameters: { username: "Alice" } }));
check("search excludes the caller", J(r).length === 0);
r = await h(ev("GET /friends/search", "alice", undefined, { queryStringParameters: {} }));
check("search needs a username", r.statusCode === 400);
r = await h(ev("GET /friends/search", "alice", undefined, { queryStringParameters: { username: "nobody" } }));
check("unknown username is an empty list", r.statusCode === 200 && J(r).length === 0);

// ---- request
r = await h(ev("POST /friends/request", "alice", { friendId: "alice" }));
check("cannot add yourself", r.statusCode === 400);
r = await h(ev("POST /friends/request", "alice", { friendId: "ghost" }));
check("unknown user", r.statusCode === 404);
r = await h(ev("POST /friends/request", "alice", { friendId: "bob" }));
check("request created", r.statusCode === 201 && J(r).status === "PENDING");
check("both rows written", db.t.Friends.get("alice|bob").status === "PENDING" && db.t.Friends.get("bob|alice").status === "INCOMING");
r = await h(ev("POST /friends/request", "alice", { friendId: "bob" }));
check("asking twice", r.statusCode === 409 && J(r).status === "PENDING");
r = await h(ev("POST /friends/request", "bob", { friendId: "alice" }));
check("they already asked you", r.statusCode === 409 && J(r).status === "INCOMING");

// ---- list
r = await h(ev("GET /friends", "bob", undefined, { queryStringParameters: { status: "INCOMING" } }));
check("bob sees the incoming request with a username", J(r).length === 1 && J(r)[0].username === "Alice" && J(r)[0].id === "alice");
r = await h(ev("GET /friends", "alice", undefined, { queryStringParameters: { status: "PENDING" } }));
check("alice sees it pending", J(r).length === 1 && J(r)[0].id === "bob");
r = await h(ev("GET /friends", "alice", undefined, { queryStringParameters: { status: "ACCEPTED" } }));
check("nobody is accepted yet", J(r).length === 0);
r = await h(ev("GET /friends", "alice", undefined, { queryStringParameters: { status: "BOGUS" } }));
check("bad status refused", r.statusCode === 400);

// ---- respond: only the recipient
r = await h(ev("POST /friends/respond", "alice", { requesterId: "bob", action: "accept" }));
check("the asker cannot accept their own request", r.statusCode === 404);
r = await h(ev("POST /friends/respond", "bob", { requesterId: "alice", action: "perhaps" }));
check("bad action refused", r.statusCode === 400);
r = await h(ev("POST /friends/respond", "bob", { requesterId: "alice", action: "accept" }));
check("accepted", r.statusCode === 200 && J(r).status === "ACCEPTED");
check("both rows ACCEPTED with the same timestamps",
  db.t.Friends.get("alice|bob").status === "ACCEPTED" && db.t.Friends.get("bob|alice").status === "ACCEPTED" &&
  db.t.Friends.get("alice|bob").acceptedAt === db.t.Friends.get("bob|alice").acceptedAt);
r = await h(ev("POST /friends/request", "alice", { friendId: "bob" }));
check("cannot ask a friend", r.statusCode === 409 && J(r).status === "ACCEPTED");

// ---- reject
await h(ev("POST /friends/request", "carol", { friendId: "alice" }));
r = await h(ev("POST /friends/respond", "alice", { requesterId: "carol", action: "reject" }));
check("rejected", r.statusCode === 200 && J(r).status === "REJECTED");
check("rejection removes both rows", !db.t.Friends.has("alice|carol") && !db.t.Friends.has("carol|alice"));

// ---- remove
r = await h(ev("DELETE /friends/{friendID}", "alice", undefined, { pathParameters: { friendID: "bob" } }));
check("removed", r.statusCode === 200);
check("remove deletes both rows", !db.t.Friends.has("alice|bob") && !db.t.Friends.has("bob|alice"));
r = await h(ev("DELETE /friends/{friendID}", "alice", undefined, { pathParameters: { friendID: "bob" } }));
check("removing again is harmless", r.statusCode === 200);

// ---- a failure between the two writes cannot leave half a friendship
db.failNextTransact = Object.assign(new Error("throttled"), { name: "ProvisionedThroughputExceededException" });
r = await h(ev("POST /friends/request", "alice", { friendId: "bob" }));
check("transaction failure is a 500", r.statusCode === 500);
check("and leaves neither row", !db.t.Friends.has("alice|bob") && !db.t.Friends.has("bob|alice"));

// ---- a racing duplicate loses cleanly
db.t.Friends.set("bob|alice", { userId: "bob", otherUserId: "alice", status: "INCOMING" });   // appeared between check and write
r = await h(ev("POST /friends/request", "alice", { friendId: "bob" }));
check("a race loses with a 409, not an overwrite", r.statusCode === 409 && !db.t.Friends.has("alice|bob"));
db.t.Friends.delete("bob|alice");

// ---- spam cap
for (let i = 0; i < MAX_OPEN_REQUESTS; i++) db.t.Friends.set(`alice|u${i}`, { userId: "alice", otherUserId: `u${i}`, status: "PENDING" });
r = await h(ev("POST /friends/request", "alice", { friendId: "bob" }));
check("too many open requests", r.statusCode === 429);
for (let i = 0; i < MAX_OPEN_REQUESTS; i++) db.t.Friends.delete(`alice|u${i}`);

// ---- a request nobody answers disappears after 2 hours
db.t.Friends.clear();
r = await h(ev("POST /friends/request", "alice", { friendId: "bob" }));
check("a new request carries a time-to-live for DynamoDB", db.t.Friends.get("alice|bob").expiresAt === clock / 1000 + REQUEST_TTL_SECONDS && db.t.Friends.get("bob|alice").expiresAt === clock / 1000 + REQUEST_TTL_SECONDS);
clock += (REQUEST_TTL_SECONDS - 60) * 1000;
r = await h(ev("GET /friends", "bob", undefined, { queryStringParameters: { status: "INCOMING" } }));
check("still visible a minute before it expires", J(r).length === 1);
clock += 61 * 1000;
r = await h(ev("GET /friends", "bob", undefined, { queryStringParameters: { status: "INCOMING" } }));
check("gone from the receiver after 2 hours", J(r).length === 0);
r = await h(ev("GET /friends", "alice", undefined, { queryStringParameters: { status: "PENDING" } }));
check("and from the sender", J(r).length === 0);
r = await h(ev("POST /friends/respond", "bob", { requesterId: "alice", action: "accept" }));
check("an expired request cannot be accepted", r.statusCode === 404 && db.t.Friends.get("alice|bob")?.status !== "ACCEPTED");
r = await h(ev("POST /friends/request", "alice", { friendId: "bob" }));
check("it can be sent again, replacing the old one", r.statusCode === 201 && db.t.Friends.get("bob|alice").requestedAt === new Date(clock).toISOString());
await h(ev("POST /friends/respond", "bob", { requesterId: "alice", action: "accept" }));
clock += 10 * REQUEST_TTL_SECONDS * 1000;
r = await h(ev("GET /friends", "bob", undefined, { queryStringParameters: { status: "ACCEPTED" } }));
check("a friendship itself never expires", J(r).length === 1 && db.t.Friends.get("bob|alice").expiresAt === undefined);
await h(ev("DELETE /friends/{friendID}", "alice", undefined, { pathParameters: { friendID: "bob" } }));
for (let i = 0; i < MAX_OPEN_REQUESTS; i++) db.t.Friends.set(`alice|u${i}`, { userId: "alice", otherUserId: `u${i}`, status: "PENDING", requestedAt: new Date(clock - (REQUEST_TTL_SECONDS + 5) * 1000).toISOString() });
r = await h(ev("POST /friends/request", "alice", { friendId: "bob" }));
check("expired requests do not count toward the cap", r.statusCode === 201);
db.t.Friends.clear();

// ---- blocking
db.t.Blocks.set("bob|alice", { blockerId: "bob", blockedId: "alice" });                       // bob blocked alice
r = await h(ev("GET /friends/search", "alice", undefined, { queryStringParameters: { username: "bob" } }));
check("search hides someone who blocked you", J(r).length === 0);
r = await h(ev("GET /friends/search", "bob", undefined, { queryStringParameters: { username: "Alice" } }));
check("and someone you blocked", J(r).length === 0);
r = await h(ev("GET /friends/search", "carol", undefined, { queryStringParameters: { username: "bob" } }));
check("but not from anyone else", J(r).length === 1);
r = await h(ev("POST /friends/request", "alice", { friendId: "bob" }));
check("a request to someone who blocked you looks like any other", r.statusCode === 201 && J(r).status === "PENDING");
check("but only the sender's side is stored", db.t.Friends.get("alice|bob")?.status === "PENDING" && !db.t.Friends.has("bob|alice"));
r = await h(ev("GET /friends", "alice", undefined, { queryStringParameters: { status: "PENDING" } }));
check("the sender sees it pending, like any request nobody has answered", J(r).length === 1 && J(r)[0].id === "bob");
db.t.Friends.set("bob|carol", { userId: "bob", otherUserId: "carol", status: "ACCEPTED" });
db.t.Friends.set("carol|bob", { userId: "carol", otherUserId: "bob", status: "ACCEPTED" });
db.t.Blocks.set("carol|bob", { blockerId: "carol", blockedId: "bob" });
r = await h(ev("GET /friends", "bob", undefined, { queryStringParameters: { status: "ACCEPTED" } }));
check("a blocked person is never listed, even if a stale row remains", J(r).length === 0);
db.t.Friends.set("bob|alice", { userId: "bob", otherUserId: "alice", status: "INCOMING", requestedAt: new Date(clock).toISOString() });
r = await h(ev("POST /friends/respond", "bob", { requesterId: "alice", action: "accept" }));
check("a request from someone you blocked cannot be accepted", r.statusCode === 404);
db.t.Blocks.clear(); db.t.Friends.clear();

// ---- deactivated accounts
db.t.Users.set("dora", { id: "dora", username: "dora", deactivated: true });
r = await h(ev("GET /friends/search", "alice", undefined, { queryStringParameters: { username: "dora" } }));
check("a deactivated account is not found", J(r).length === 0);
r = await h(ev("POST /friends/request", "alice", { friendId: "dora" }));
check("and cannot be asked", r.statusCode === 404);
db.t.Users.delete("dora");

// ---- errors never echo AWS text, logs hold the name only
const broken = makeHandler({ db: { ...db, get: async () => { throw Object.assign(new Error("arn:aws:dynamodb:...:table/Users secret"), { name: "AccessDeniedException" }); } } });
const saved = console.error; let logged = "";
console.error = (...x) => { logged += x.join(" "); };
r = await broken(ev("GET /friends/search", "alice", undefined, { queryStringParameters: { username: "bob" } }));
r = await broken(ev("POST /friends/request", "alice", { friendId: "bob" }));
console.error = saved;
check("500 is generic", r.statusCode === 500 && !r.body.includes("arn:") && !r.body.includes("secret"));
check("log is the error name only", logged.includes("AccessDeniedException") && !logged.includes("arn:") && !logged.includes("alice"));

out(`${passed} passed, ${failures} failed`);
if (failures) throw new Error("tests failed");
