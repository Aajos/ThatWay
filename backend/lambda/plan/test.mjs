// Run:  /System/Library/Frameworks/JavaScriptCore.framework/Versions/A/Helpers/jsc -m test.mjs     (or: node test.mjs)
import { makeHandler, planUntil, PRODUCTS, FOREVER, BUNDLE_ID } from "./core.mjs";

const out = typeof print === "function" ? print : console.log;
if (typeof console === "undefined") globalThis.console = { log: out, error() {} };
let failures = 0, passed = 0;
const check = (name, ok) => { if (ok) passed++; else { failures++; out("FAIL: " + name); } };

const rows = new Map();
const db = { get: async (t, k) => rows.get(k.userId), put: async (t, item) => { rows.set(item.userId, { ...item }); } };
let clock = 1_800_000_000_000;
const sec = () => clock / 1000;
// The fake verifier: a "jws" is just JSON here. A string that is not JSON is "not signed by Apple".
const verify = async (jws) => { try { const p = JSON.parse(jws); return p.__apple === true ? p : null; } catch { return null; } };
const h = makeHandler({ db, verify, now: () => clock });
const ev = (route, sub, body) => ({ routeKey: route, body: body === undefined ? undefined : JSON.stringify(body), requestContext: { authorizer: { jwt: { claims: { sub } } } } });
const J = (r) => JSON.parse(r.body);
let n = 0;
const tx = (productId, extra = {}) => JSON.stringify({ __apple: true, bundleId: BUNDLE_ID, productId, transactionId: `t${++n}`, originalTransactionId: `o${n}`, environment: "Production", ...extra });
const sync = (sub, ...jws) => h(ev("POST /plan/sync", sub, { transactions: jws }));

let r = await h({ routeKey: "GET /plan", requestContext: {} });
check("unauthenticated refused", r.statusCode === 401);
r = await h(ev("GET /plan", "a")); check("no purchase, no plan", J(r).until === null);

// passes
r = await sync("a", tx("com.thatway.trace3"));
check("a 3-hour pass starts now and lasts 3 hours", J(r).until === sec() + 3 * 3600 && J(r).results[0].ok);
const first = tx("com.thatway.trace24");
r = await sync("a", first);
check("a 24-hour pass stacks on what is left", J(r).until === sec() + 27 * 3600);
r = await sync("a", first);
check("the same transaction is never counted twice", J(r).until === sec() + 27 * 3600 && J(r).results[0].reason === "already counted");
r = await sync("b", first);
check("nor by another account", J(r).until === null && J(r).results[0].reason === "belongs to another account");
clock += 28 * 3600 * 1000;
r = await h(ev("GET /plan", "a")); check("a plan that has run out reports none", J(r).until === null);
r = await sync("a", tx("com.thatway.trace3"));
check("buying again after it ran out starts from now, not from the old end", J(r).until === sec() + 3 * 3600);

// forgeries and mistakes
r = await sync("c", "not a signature");
check("something not signed by Apple counts for nothing", J(r).until === null && J(r).results[0].reason === "not verified");
r = await sync("c", JSON.stringify({ __apple: false, productId: "com.thatway.lifetrace" }));
check("a claimed lifetime plan with a bad signature counts for nothing", J(r).until === null);
r = await sync("c", tx("com.thatway.trace3", { bundleId: "com.other.app" }));
check("a purchase from another app is refused", J(r).results[0].reason === "wrong app" && J(r).until === null);
r = await sync("c", tx("com.thatway.free"));
check("an unknown product is refused", J(r).results[0].reason === "unknown product");
r = await sync("c", tx("com.thatway.trace3", { revocationDate: 1 }));
check("a refunded purchase is refused", J(r).results[0].reason === "refunded");
r = await sync("c", tx("com.thatway.trace3", { environment: "Xcode" }));
check("an unknown environment is refused", J(r).results[0].reason === "unknown environment");
const noSandbox = makeHandler({ db, verify, now: () => clock, allowSandbox: false });
r = await noSandbox(ev("POST /plan/sync", "c", { transactions: [tx("com.thatway.trace3", { environment: "Sandbox" })] }));
check("sandbox purchases can be refused when the server is in production mode", J(r).results[0].reason === "sandbox");
r = await sync("c"); check("an empty sync is refused", r.statusCode === 400);
r = await h(ev("POST /plan/sync", "c", { transactions: Array.from({ length: 21 }, () => "x") })); check("too many at once is refused", r.statusCode === 400);

// subscription
const month = tx("com.thatway.traceplus", { expiresDate: (sec() + 30 * 86400) * 1000 });
r = await sync("d", month);
check("a subscription lasts until Apple's renewal date", J(r).until === sec() + 30 * 86400);
r = await sync("d", tx("com.thatway.traceplus"));
check("a subscription without a renewal date is refused", J(r).results[0].reason === "no expiry");
const renewed = JSON.stringify({ ...JSON.parse(month), transactionId: "renewal", expiresDate: (sec() + 60 * 86400) * 1000 });
r = await sync("d", renewed);
check("a renewal extends it", J(r).until === sec() + 60 * 86400);
r = await sync("d", tx("com.thatway.trace3"));
check("a pass inside a subscription does not shorten it", J(r).until === sec() + 60 * 86400);

// lifetime and moving between accounts
const life = tx("com.thatway.lifetrace");
r = await sync("e", life);
check("lifetime never ends", J(r).forever === true && J(r).until === FOREVER);
r = await sync("f", life);
check("the same lifetime purchase moves to the account that claims it", J(r).forever === true);
r = await h(ev("GET /plan", "e"));
check("and the account it left loses it", J(r).until === null && J(r).forever === false);
check("planUntil of a lifetime row", planUntil({ lifetime: true }) === FOREVER && planUntil(undefined) === 0 && planUntil({ passUntil: 5, subUntil: 9 }) === 9);

// the products the app sells
check("the catalogue is the four plans", Object.keys(PRODUCTS).length === 4 && PRODUCTS["com.thatway.trace3"].seconds === 10800 && PRODUCTS["com.thatway.trace24"].seconds === 86400);

// failures never leak
const broken = makeHandler({ db: { get: async () => { throw Object.assign(new Error("secret"), { name: "Boom" }); }, put: async () => {} }, verify, now: () => clock });
const saved = console.error; let logged = ""; console.error = (...x) => { logged += x.join(" "); };
r = await broken(ev("GET /plan", "a")); console.error = saved;
check("a failure is a generic 500 and the log holds the name only", r.statusCode === 500 && !r.body.includes("secret") && logged.includes("Boom") && !logged.includes("secret"));

out(`${passed} passed, ${failures} failed`);
if (failures) throw new Error("tests failed");
