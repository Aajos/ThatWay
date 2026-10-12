// The friends API: search, request, respond, list, remove. One tested module behind five Lambdas (each function directory
// holds an identical index.mjs and a copy of this file: `backend/scripts/sync_friends.sh` keeps them in step). Pure logic,
// no AWS imports, so it runs under `jsc -m test.mjs` or `node test.mjs`.
//
// What changed from the first version, and why:
//   - search returns {id, username} only: it used to return every user's email address to any signed-in searcher
//   - the two rows of a friendship are written/removed in ONE transaction, so a failure cannot leave half a friendship
//   - a request only succeeds if neither row exists yet (a condition inside the transaction), so two requests at the same
//     moment cannot overwrite each other
//   - open outgoing requests are capped, so one account cannot spam everyone it can search for
//   - errors never echo AWS messages back to the app, and logs hold the error name only

export const MAX_OPEN_REQUESTS = 50;
const STATUSES = ["ACCEPTED", "PENDING", "INCOMING"];
const EXISTING = {
  ACCEPTED: "You are already friends",
  PENDING: "Request already sent",
  INCOMING: "They already sent you a request, accept it instead",
};

const reply = (statusCode, body) => ({ statusCode, body: JSON.stringify(body) });
const isId = (v) => typeof v === "string" && v.length > 0 && v.length <= 128;

/**
 * `db` needs: get(table, key), query(table, userId), queryIndex(table, index, attr, value),
 * transact([{ put: {table, item, absentKey?: [pk, sk]} } | { remove: {table, key} }]).
 */
export function makeHandler({ db, now = () => Date.now() }) {
  const iso = () => new Date(now()).toISOString();

  return async function handler(event) {
    try {
      const me = event.requestContext?.authorizer?.jwt?.claims?.sub;
      if (!me) return reply(401, { error: "Not signed in" });
      const route = event.routeKey;
      let body = {};
      if (event.body) { try { body = JSON.parse(event.body); } catch { return reply(400, { error: "Invalid JSON" }); } }

      // ---- GET /friends?status=ACCEPTED|PENDING|INCOMING
      if (route === "GET /friends") {
        const status = (event.queryStringParameters?.status || "ACCEPTED").toUpperCase();
        if (!STATUSES.includes(status)) return reply(400, { error: "status must be ACCEPTED, PENDING or INCOMING" });
        const rows = (await db.query("Friends", me)).filter((r) => r.status === status);
        const users = await Promise.all(rows.map((r) => db.get("Users", { id: r.otherUserId })));
        return reply(200, rows.map((r, i) => ({
          id: r.otherUserId,
          username: users[i]?.username ?? "unknown",
          status: r.status,
          requestedAt: r.requestedAt ?? null,
          acceptedAt: r.acceptedAt ?? null,
        })));
      }

      // ---- GET /friends/search?username=
      if (route === "GET /friends/search") {
        const username = event.queryStringParameters?.username;
        if (!isId(username)) return reply(400, { error: "Username required" });
        const hits = await db.queryIndex("Users", "byUsername", "username", username);
        // Id and username only. (Never an email, and never the caller themselves.)
        return reply(200, hits.filter((u) => u.id !== me).map((u) => ({ id: u.id, username: u.username })));
      }

      // ---- POST /friends/request {friendId}
      if (route === "POST /friends/request") {
        const friendId = body.friendId;
        if (!isId(friendId)) return reply(400, { error: "friendId required" });
        if (friendId === me) return reply(400, { error: "You can't add yourself" });
        if (!(await db.get("Users", { id: friendId }))) return reply(404, { error: "User not found" });

        const existing = await db.get("Friends", { userId: me, otherUserId: friendId });
        if (existing) {
          const s = existing.status;
          return reply(409, { error: EXISTING[s] || "Relationship already exists", status: s });
        }
        const open = (await db.query("Friends", me)).filter((r) => r.status === "PENDING").length;
        if (open >= MAX_OPEN_REQUESTS) return reply(429, { error: "Too many pending requests" });

        const requestedAt = iso();
        try {
          await db.transact([
            { put: { table: "Friends", item: { userId: me, otherUserId: friendId, status: "PENDING", requestedAt }, absentKey: ["userId", "otherUserId"] } },
            { put: { table: "Friends", item: { userId: friendId, otherUserId: me, status: "INCOMING", requestedAt }, absentKey: ["userId", "otherUserId"] } },
          ]);
        } catch (error) {
          if (error?.name === "TransactionCanceledException") return reply(409, { error: "A request already exists" });
          throw error;
        }
        return reply(201, { status: "PENDING", requestedAt });
      }

      // ---- POST /friends/respond {requesterId, action: accept|reject}
      if (route === "POST /friends/respond") {
        const { requesterId, action } = body;
        if (!isId(requesterId) || !action) return reply(400, { error: "requesterId and action required" });
        if (action !== "accept" && action !== "reject") return reply(400, { error: "Invalid action" });
        // Only the recipient of a real request can answer it.
        const incoming = await db.get("Friends", { userId: me, otherUserId: requesterId });
        if (!incoming || incoming.status !== "INCOMING") return reply(404, { error: "No pending request from that user" });

        if (action === "accept") {
          const acceptedAt = iso();
          const requestedAt = incoming.requestedAt ?? null;
          await db.transact([
            { put: { table: "Friends", item: { userId: requesterId, otherUserId: me, status: "ACCEPTED", requestedAt, acceptedAt } } },
            { put: { table: "Friends", item: { userId: me, otherUserId: requesterId, status: "ACCEPTED", requestedAt, acceptedAt } } },
          ]);
          return reply(200, { status: "ACCEPTED" });
        }
        await db.transact([
          { remove: { table: "Friends", key: { userId: requesterId, otherUserId: me } } },
          { remove: { table: "Friends", key: { userId: me, otherUserId: requesterId } } },
        ]);
        return reply(200, { status: "REJECTED" });
      }

      // ---- DELETE /friends/{friendID}   (unfriend, or cancel a request I sent)
      if (route === "DELETE /friends/{friendID}") {
        const friendId = event.pathParameters?.friendID ?? event.pathParameters?.friendId;
        if (!isId(friendId)) return reply(400, { error: "friendId required" });
        await db.transact([
          { remove: { table: "Friends", key: { userId: me, otherUserId: friendId } } },
          { remove: { table: "Friends", key: { userId: friendId, otherUserId: me } } },
        ]);
        return reply(200, { message: "Friend removed" });
      }

      return reply(404, { error: "Unknown route" });
    } catch (error) {
      console.error("friends failed:", error?.name);   // the name only: never an AWS message, id or body
      return reply(500, { error: "Something went wrong" });
    }
  };
}
