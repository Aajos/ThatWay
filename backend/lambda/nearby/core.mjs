// Proximity ("find a friend nearby") token exchange. Two phones that want to range each other over UWB each need the
// other's NearbyInteraction discovery token; this relays them. Pure logic, no AWS imports, so it runs under
// `jsc -m test.mjs` (macOS) or `node test.mjs` without credentials. index.mjs wires it to DynamoDB.
//
// Privacy: an offer is an opaque token plus who it is for. It holds no location, is only accepted between ACCEPTED
// friends, expires after two minutes (DynamoDB TTL on `expiresAt`, and every read re-checks it), and the code never
// logs a token or a request body.

export const OFFER_TTL_SECONDS = 120;
export const MAX_TOKEN_LENGTH = 4096;
export const KINDS = ["uwb", "ble"];
const BASE64 = /^[A-Za-z0-9+/_-]+={0,2}$/;

const reply = (statusCode, body) => ({
  statusCode,
  headers: { "Content-Type": "application/json" },
  body: body === undefined ? "" : JSON.stringify(body),
});

export function validateOffer(body) {
  if (!body || typeof body !== "object") return "A JSON body is required";
  const { friendId, token, kind } = body;
  if (typeof friendId !== "string" || friendId.length === 0 || friendId.length > 128) return "friendId required";
  if (typeof token !== "string" || token.length === 0) return "token required";
  if (token.length > MAX_TOKEN_LENGTH) return "token too large";
  if (!BASE64.test(token)) return "token must be base64";
  if (!KINDS.includes(kind)) return "kind must be uwb or ble";
  return null;
}

/** `db` needs get(table, key), put(table, item), query(table, userId), remove(table, key). */
export function makeHandler({ db, now = () => Date.now() }) {
  const nowSeconds = () => Math.floor(now() / 1000);

  async function areFriends(a, b) {
    const row = await db.get("Friends", { userId: a, otherUserId: b });
    return row?.status === "ACCEPTED";
  }

  return async function handler(event) {
    try {
      const me = event.requestContext?.authorizer?.jwt?.claims?.sub;
      if (!me) return reply(401, { error: "Not signed in" });
      const route = event.routeKey;

      if (route === "PUT /nearby/offers") {
        let body;
        try { body = JSON.parse(event.body || "{}"); } catch { return reply(400, { error: "Invalid JSON" }); }
        const problem = validateOffer(body);
        if (problem) return reply(400, { error: problem });
        if (body.friendId === me) return reply(400, { error: "You can't find yourself" });
        if (!(await areFriends(me, body.friendId))) return reply(403, { error: "You can only find accepted friends" });

        const expiresAt = nowSeconds() + OFFER_TTL_SECONDS;
        await db.put("NearbyOffers", {
          userId: body.friendId, fromUserId: me, token: body.token, kind: body.kind,
          expiresAt, updatedAt: new Date(now()).toISOString(),
        });
        return reply(200, { expiresAt });
      }

      if (route === "GET /nearby/offers") {
        const rows = await db.query("NearbyOffers", me);
        const live = rows.filter((r) => r.expiresAt > nowSeconds());
        const offers = [];
        for (const r of live) {
          if (await areFriends(me, r.fromUserId)) {
            offers.push({ friendId: r.fromUserId, token: r.token, kind: r.kind, expiresAt: r.expiresAt });
          }
        }
        return reply(200, offers);
      }

      if (route === "DELETE /nearby/offers/{friendId}") {
        const friendId = event.pathParameters?.friendId;
        if (!friendId) return reply(400, { error: "friendId required" });
        await db.remove("NearbyOffers", { userId: friendId, fromUserId: me });   // what I sent them
        await db.remove("NearbyOffers", { userId: me, fromUserId: friendId });   // what they sent me
        return reply(204);
      }

      return reply(404, { error: "Unknown route" });
    } catch (error) {
      console.error("nearby failed:", error?.name);   // the name only: never a token, body or user id
      return reply(500, { error: "Something went wrong" });
    }
  };
}
