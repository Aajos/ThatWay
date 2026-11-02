// Paid plans, decided on the SERVER. The phone proves a purchase by sending Apple's signed transaction (a JWS from StoreKit 2);
// this module checks it was signed by Apple for THIS app, works out how long the plan lasts, and records it. Nothing else may
// write the Entitlements table, and the trace functions read it (PLAN_CHECK=on) to decide whether a tracer's plan is live.
//
//   trace3     3-hour pass      consumable      stacks: bought again, it adds to what is left
//   trace24    24-hour pass     consumable      stacks the same way
//   trace+     monthly          subscription    lasts until the renewal date Apple reports
//   lifetrace  lifetime         non-consumable  lasts for good (modelled as year 2100)
//
// A pass starts when it is CLAIMED (the moment the app reports it), not when it was bought, so a pass bought while offline
// is not eaten by the delay. Each transaction counts once, for one account: a claimed pass cannot be credited twice, and a
// subscription or lifetime purchase belongs to one account at a time (claiming it elsewhere moves it).
// Pure logic: `verify` (Apple's signature check) and `db` are injected. Logs nothing but error names.

export const BUNDLE_ID = "com.thatway.app";
export const FOREVER = 4102444800;                                   // 2100-01-01
export const PRODUCTS = {
  "com.thatway.trace3": { kind: "pass", seconds: 3 * 3600 },
  "com.thatway.trace24": { kind: "pass", seconds: 24 * 3600 },
  "com.thatway.traceplus": { kind: "subscription" },
  "com.thatway.lifetrace": { kind: "lifetime" },
};
export const MAX_TRANSACTIONS_PER_SYNC = 20;

const reply = (statusCode, body) => ({ statusCode, headers: { "Content-Type": "application/json" }, body: JSON.stringify(body) });

/** When the plan ends, from the stored pieces. */
export const planUntil = (row) => (row?.lifetime ? FOREVER : Math.max(row?.passUntil ?? 0, row?.subUntil ?? 0));

/** `db` needs get(table, key), put(table, item). `verify(jws)` returns the decoded transaction payload, or null if it is not a genuine Apple signature. */
export function makeHandler({ db, verify, now = () => Date.now(), allowSandbox = true }) {
  const sec = () => Math.floor(now() / 1000);

  async function claim(me, payload) {
    const product = PRODUCTS[payload.productId];
    if (!product) return "unknown product";
    if (payload.bundleId !== BUNDLE_ID) return "wrong app";
    if (payload.revocationDate) return "refunded";
    if (payload.environment === "Sandbox" && !allowSandbox) return "sandbox";
    if (payload.environment !== "Sandbox" && payload.environment !== "Production") return "unknown environment";
    const row = (await db.get("Entitlements", { userId: me })) ?? { userId: me };
    const key = (prefix, id) => ({ userId: `${prefix}:${id}` });

    if (product.kind === "pass") {
      const id = String(payload.transactionId ?? "");
      if (!id) return "no transaction";
      const seen = await db.get("Entitlements", key("tx", id));
      if (seen) return seen.owner === me ? "already counted" : "belongs to another account";
      await db.put("Entitlements", { ...key("tx", id), owner: me, at: sec() });
      row.passUntil = Math.max(sec(), row.passUntil ?? 0) + product.seconds;   // stacks on what is left
    } else {
      const id = String(payload.originalTransactionId ?? payload.transactionId ?? "");
      if (!id) return "no transaction";
      if (product.kind === "subscription" && !(payload.expiresDate > 0)) return "no expiry";
      const owned = await db.get("Entitlements", key("orig", id));
      if (owned && owned.owner !== me) {                                           // it moves: the previous account loses it
        const previous = await db.get("Entitlements", { userId: owned.owner });
        if (previous) {
          if (product.kind === "lifetime") previous.lifetime = false; else previous.subUntil = 0;
          previous.planUntil = planUntil(previous);
          await db.put("Entitlements", previous);
        }
      }
      await db.put("Entitlements", { ...key("orig", id), owner: me, at: sec() });
      if (product.kind === "lifetime") row.lifetime = true;
      else row.subUntil = Math.floor(payload.expiresDate / 1000);                 // Apple reports milliseconds
    }
    row.planUntil = planUntil(row);
    row.updatedAt = sec();
    await db.put("Entitlements", row);
    return null;
  }

  return async function handler(event) {
    try {
      const me = event.requestContext?.authorizer?.jwt?.claims?.sub;
      if (!me) return reply(401, { error: "Not signed in" });
      const route = event.routeKey;
      let body = {};
      if (event.body) { try { body = JSON.parse(event.body); } catch { return reply(400, { error: "Invalid JSON" }); } }

      if (route === "GET /plan") {
        const row = await db.get("Entitlements", { userId: me });
        const until = planUntil(row);
        return reply(200, { until: until > sec() ? until : null, forever: until === FOREVER });
      }

      if (route === "POST /plan/sync") {
        const list = Array.isArray(body.transactions) ? body.transactions.filter((t) => typeof t === "string" && t.length < 20000) : [];
        if (list.length === 0 || list.length > MAX_TRANSACTIONS_PER_SYNC) return reply(400, { error: "transactions required" });
        const results = [];
        for (const jws of list) {
          let payload = null;
          try { payload = await verify(jws); } catch { payload = null; }
          if (!payload) { results.push({ ok: false, reason: "not verified" }); continue; }    // not Apple's signature: counts for nothing
          const problem = await claim(me, payload);
          results.push({ ok: problem === null || problem === "already counted", reason: problem ?? undefined, productId: payload.productId });
        }
        const row = await db.get("Entitlements", { userId: me });
        const until = planUntil(row);
        return reply(200, { until: until > sec() ? until : null, forever: until === FOREVER, results });
      }

      return reply(404, { error: "Unknown route" });
    } catch (error) {
      console.error("plan failed:", error?.name);     // the name only
      return reply(500, { error: "Something went wrong" });
    }
  };
}
