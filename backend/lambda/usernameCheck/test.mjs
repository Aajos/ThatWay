// Run:  /System/Library/Frameworks/JavaScriptCore.framework/Versions/A/Helpers/jsc -m test.mjs     (or: node test.mjs)
import { makeHandler, RESERVED } from "./core.mjs";

const out = typeof print === "function" ? print : console.log;
if (typeof console === "undefined") globalThis.console = { log: out, error() {} };
let failures = 0, passed = 0;
const check = (name, ok) => { if (ok) passed++; else { failures++; out("FAIL: " + name); } };

const users = [{ id: "1", username: "aadit" }, { id: "2", username: "OldCaps" }];
const db = { queries: 0, queryIndex: async (t, i, attr, value) => { db.queries++; return users.filter((u) => u[attr] === value); } };
const h = makeHandler({ db });
const ask = async (u) => { const r = await h({ queryStringParameters: u === undefined ? {} : { username: u } }); return { status: r.statusCode, body: JSON.parse(r.body) }; };

let r = await ask("freshname"); check("a free name is available", r.status === 200 && r.body.available === true);
r = await ask("aadit"); check("a taken name is not", r.body.available === false && r.body.reason === "taken");
r = await ask("AADIT"); check("case does not matter", r.body.available === false && r.body.reason === "taken");
r = await ask("OldCaps"); check("the exact older spelling is taken", r.body.available === false && r.body.reason === "taken");
r = await ask("ab"); check("too short is invalid", r.body.available === false && r.body.reason === "invalid");
r = await ask("a".repeat(21)); check("too long is invalid", r.body.reason === "invalid");
r = await ask("1abc"); check("must start with a letter", r.body.reason === "invalid");
r = await ask("sam smith"); check("spaces are invalid", r.body.reason === "invalid");
r = await ask("sam-smith"); check("hyphens are invalid", r.body.reason === "invalid");
r = await ask("sam_smith2"); check("underscore and digits are fine", r.body.available === true);
r = await ask("Admin"); check("reserved names are refused", r.body.reason === "reserved");
check("every reserved name is itself valid (so the reason is meaningful)", RESERVED.every((n) => /^[a-z][a-z0-9_]{2,19}$/.test(n)));
const before = db.queries; await ask("ab"); await ask("admin");
check("invalid and reserved names never touch the database", db.queries === before);
r = await ask(undefined); check("a missing username is a 400", r.status === 400);
r = await ask("x".repeat(65)); check("an absurdly long input is a 400", r.status === 400);
check("the answer never carries an id or an email", !JSON.stringify(await ask("aadit")).match(/id|email/));

const broken = makeHandler({ db: { queryIndex: async () => { throw Object.assign(new Error("arn:aws secret table"), { name: "Boom" }); } } });
const saved = console.error; let logged = "";
console.error = (...x) => { logged += x.join(" "); };
const e = await broken({ queryStringParameters: { username: "somebody" } });
console.error = saved;
check("a failure is a generic 500", e.statusCode === 500 && !e.body.includes("arn"));
check("the log holds the error name only", logged.includes("Boom") && !logged.includes("somebody") && !logged.includes("arn"));

out(`${passed} passed, ${failures} failed`);
if (failures) throw new Error("tests failed");
