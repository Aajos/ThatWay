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
//
// Added 2026-10-17:
//   - a friend request that nobody answers disappears after 2 hours (the row also carries `expiresAt`, so DynamoDB's TTL
//     removes it; every read re-checks the time because TTL deletion can lag by a day or more)
//   - people who blocked you (or whom you blocked) never appear in search or lists, and a request to someone who blocked
//     you is stored on your side only: it looks pending for 2 hours and then goes, like any request nobody answered
//   - deactivated accounts are not found by search

export const MAX_OPEN_REQUESTS = 50;
export const REQUEST_TTL_SECONDS = 7200;
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
  const sec = () => Math.floor(now() / 1000);

  /** A waiting request nobody answered in 2 hours. (Accepted friendships never expire.) */
  const expired = (row) => {
    if (!row || (row.status !== "PENDING" && row.status !== "INCOMING")) return false;
    const at = row.requestedAt ? Date.parse(row.requestedAt) : NaN;
    return Number.isFinite(at) ? at + REQUEST_TTL_SECONDS * 1000 <= now() : false;
  };
  const blockedEitherWay = async (a, b) =>
    Boolean(await db.get("Blocks", { blockerId: a, blockedId: b }) || await db.get("Blocks", { blockerId: b, blockedId: a }));

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
        const all = (await db.query("Friends", me)).filter((r) => r.status === status && !expired(r));
        // A request I sent is always shown to me (if they blocked me it is the quiet one that just looks unanswered); anything
        // else involving a blocked person is hidden.
        const blocked = await Promise.all(all.map((r) => status === "PENDING" ? false : blockedEitherWay(me, r.otherUserId)));
        const rows = all.filter((_, i) => !blocked[i]);
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
        // Id and username only. (Never an email, never the caller, nobody who blocked them or whom they blocked, nobody deactivated.)
        const candidates = hits.filter((u) => u.id !== me && !u.deactivated);
        const blocked = await Promise.all(candidates.map((u) => blockedEitherWay(me, u.id)));
        return reply(200, candidates.filter((_, i) => !blocked[i]).map((u) => ({ id: u.id, username: u.username })));
      }

      // ---- POST /friends/request {friendId}
      if (route === "POST /friends/request") {
        const friendId = body.friendId;
        if (!isId(friendId)) return reply(400, { error: "friendId required" });
        if (friendId === me) return reply(400, { error: "You can't add yourself" });
        const target = await db.get("Users", { id: friendId });
        if (!target || target.deactivated) return reply(404, { error: "User not found" });

        let existing = await db.get("Friends", { userId: me, otherUserId: friendId });
        if (expired(existing)) {                       // an old unanswered request: clear both rows, then carry on as if it never was
          await db.transact([
            { remove: { table: "Friends", key: { userId: me, otherUserId: friendId } } },
            { remove: { table: "Friends", key: { userId: friendId, otherUserId: me } } },
          ]);
          existing = undefined;
        }
        if (existing) {
          const s = existing.status;
          return reply(409, { error: EXISTING[s] || "Relationship already exists", status: s });
        }
        const open = (await db.query("Friends", me)).filter((r) => r.status === "PENDING" && !expired(r)).length;
        if (open >= MAX_OPEN_REQUESTS) return reply(429, { error: "Too many pending requests" });

        const requestedAt = iso();
        const expiresAt = sec() + REQUEST_TTL_SECONDS;
        // Someone who blocked you never receives it: your own side looks pending until it expires, like any ignored request.
        const quiet = await blockedEitherWay(me, friendId);
        try {
          await db.transact([
            { put: { table: "Friends", item: { userId: me, otherUserId: friendId, status: "PENDING", requestedAt, expiresAt }, absentKey: ["userId", "otherUserId"] } },
            ...(quiet ? [] : [{ put: { table: "Friends", item: { userId: friendId, otherUserId: me, status: "INCOMING", requestedAt, expiresAt }, absentKey: ["userId", "otherUserId"] } }]),
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
        if (!incoming || incoming.status !== "INCOMING" || expired(incoming) || (await blockedEitherWay(me, requesterId)))
          return reply(404, { error: "No pending request from that user" });

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
