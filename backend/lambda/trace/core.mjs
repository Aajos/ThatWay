// Consent-based friend tracing ("point me to my friend, at any range"). Pure logic, no AWS imports, so it runs under
// `jsc -m test.mjs` (macOS) or `node test.mjs`. index.mjs wires it to DynamoDB.
//
// The model, one row per person per pair (like the Friends table), key userId + peerId:
//   OUTGOING  I asked them; waiting.            INCOMING  they asked me; I must accept or decline.
//   ACTIVE    both said yes: positions flow.    DECLINED  they said no (kept 60 s so the asker sees it).
//
// Safety, enforced here and not in the app:
//   - only ACCEPTED friends can ask; nothing is shared until the other person accepts; either side can end at any time
//   - a position is only ever returned to the partner of an ACTIVE session, only while the friendship still stands,
//     and only if it is under 90 s old; rows expire on their own (requests 10 min; active sessions 60 min after the
//     last upload, 24 h at the very most)
//   - no response ever carries a username or email; the app shows direction and distance, never coordinates or a map
//   - nothing is logged except an error name: never a position, body or id

export const REQUEST_TTL_SECONDS = 600;
// A trace has to survive a whole trip. It is kept alive by use: each person's row expires 60 minutes after *their* last
// position upload (so a tunnel or a dead zone does not end it), and no session lasts more than 24 hours in any case.
export const ACTIVE_IDLE_SECONDS = 3600;
export const ACTIVE_MAX_SECONDS = 86400;
export const DECLINED_TTL_SECONDS = 60;
export const POSITION_MAX_AGE_SECONDS = 90;
export const MAX_OPEN_REQUESTS = 3;

const reply = (statusCode, body) => ({
  statusCode,
  headers: { "Content-Type": "application/json" },
  body: body === undefined ? "" : JSON.stringify(body),
});
const isId = (v) => typeof v === "string" && v.length > 0 && v.length <= 128;
const isNum = (v) => typeof v === "number" && Number.isFinite(v);

export function validatePosition(b) {
  if (!b || typeof b !== "object") return "A JSON body is required";
  if (!isId(b.friendId)) return "friendId required";
  if (!isNum(b.lat) || b.lat < -90 || b.lat > 90) return "lat out of range";
  if (!isNum(b.lon) || b.lon < -180 || b.lon > 180) return "lon out of range";
  if (b.acc !== undefined && (!isNum(b.acc) || b.acc < 0 || b.acc > 100000)) return "acc out of range";
  return null;
}

/** `db` needs get(table, key), put(table, item), query(table, userId), remove(table, key). */
export function makeHandler({ db, now = () => Date.now(), makeId = () => String(now()) }) {
  const T = "TraceSessions";
  const sec = () => Math.floor(now() / 1000);
  const live = (row) => row && row.expiresAt > sec();
  const getRow = async (userId, peerId) => db.get(T, { userId, peerId });
  // Both rows must say ACCEPTED: this feature shares a position, so a half-removed friendship counts as no friendship.
  const areFriends = async (a, b) =>
    (await db.get("Friends", { userId: a, otherUserId: b }))?.status === "ACCEPTED" &&
    (await db.get("Friends", { userId: b, otherUserId: a }))?.status === "ACCEPTED";
  const dropPair = async (a, b) => { await db.remove(T, { userId: a, peerId: b }); await db.remove(T, { userId: b, peerId: a }); };

  return async function handler(event) {
    try {
      const me = event.requestContext?.authorizer?.jwt?.claims?.sub;
      if (!me) return reply(401, { error: "Not signed in" });
      const route = event.routeKey;
      let body = {};
      if (event.body) { try { body = JSON.parse(event.body); } catch { return reply(400, { error: "Invalid JSON" }); } }

      if (route === "POST /trace/request") {
        const friendId = body.friendId;
        if (!isId(friendId)) return reply(400, { error: "friendId required" });
        if (friendId === me) return reply(400, { error: "You can't trace yourself" });
        if (!(await areFriends(me, friendId))) return reply(403, { error: "You can only trace accepted friends" });

        const mine = await getRow(me, friendId);
        const theirs = await getRow(friendId, me);
        if (live(mine) && mine.status === "ACTIVE") return reply(409, { error: "Already tracing", status: "ACTIVE" });
        if (live(mine) && mine.status === "OUTGOING") return reply(200, { status: "OUTGOING", expiresAt: mine.expiresAt });
        if (live(mine) && mine.status === "DECLINED") return reply(429, { error: "They declined a moment ago. Try again shortly." });

        // They already asked me: asking back is the same as saying yes.
        if (live(mine) && mine.status === "INCOMING" && live(theirs) && theirs.status === "OUTGOING") {
          const sessionId = theirs.sessionId || makeId();
          const expiresAt = sec() + ACTIVE_IDLE_SECONDS;
          await db.put(T, { userId: me, peerId: friendId, status: "ACTIVE", sessionId, startedAt: sec(), expiresAt });
          await db.put(T, { userId: friendId, peerId: me, status: "ACTIVE", sessionId, startedAt: sec(), expiresAt });
          return reply(200, { status: "ACTIVE", sessionId, expiresAt });
        }

        const open = (await db.query(T, me)).filter((r) => live(r) && r.status === "OUTGOING");
        if (open.length >= MAX_OPEN_REQUESTS) return reply(429, { error: "Too many open requests" });

        const expiresAt = sec() + REQUEST_TTL_SECONDS;
        const sessionId = makeId();
        const requestedAt = new Date(now()).toISOString();
        await db.put(T, { userId: me, peerId: friendId, status: "OUTGOING", sessionId, requestedAt, expiresAt });
        await db.put(T, { userId: friendId, peerId: me, status: "INCOMING", sessionId, requestedAt, expiresAt });
        return reply(201, { status: "OUTGOING", sessionId, expiresAt });
      }

      if (route === "GET /trace") {
        const rows = (await db.query(T, me)).filter(live);
        const out = [];
        for (const r of rows) {
          if (!(await areFriends(me, r.peerId))) { await dropPair(me, r.peerId); continue; }   // unfriended: the session ends
          const item = { friendId: r.peerId, status: r.status, sessionId: r.sessionId, expiresAt: r.expiresAt, requestedAt: r.requestedAt ?? null };
          if (r.status === "ACTIVE") {
            const peer = await getRow(r.peerId, me);
            if (live(peer) && peer.status === "ACTIVE" && isNum(peer.lat) && isNum(peer.lon)) {
              const age = sec() - (peer.posAt ?? 0);
              if (age <= POSITION_MAX_AGE_SECONDS) item.peer = { lat: peer.lat, lon: peer.lon, acc: peer.acc ?? null, age };
            }
          }
          out.push(item);
        }
        return reply(200, out);
      }

      if (route === "POST /trace/respond") {
        const { friendId, action } = body;
        if (!isId(friendId)) return reply(400, { error: "friendId required" });
        if (action !== "accept" && action !== "decline") return reply(400, { error: "action must be accept or decline" });
        const mine = await getRow(me, friendId);
        if (!live(mine) || mine.status !== "INCOMING") return reply(404, { error: "No request to answer" });
        if (!(await areFriends(me, friendId))) { await dropPair(me, friendId); return reply(403, { error: "Not friends" }); }
        const theirs = await getRow(friendId, me);

        if (action === "decline") {
          await db.remove(T, { userId: me, peerId: friendId });
          if (live(theirs)) await db.put(T, { userId: friendId, peerId: me, status: "DECLINED", sessionId: mine.sessionId, expiresAt: sec() + DECLINED_TTL_SECONDS });
          return reply(200, { status: "DECLINED" });
        }
        if (!live(theirs) || theirs.status !== "OUTGOING") { await db.remove(T, { userId: me, peerId: friendId }); return reply(404, { error: "The request is gone" }); }
        const expiresAt = sec() + ACTIVE_IDLE_SECONDS;
        await db.put(T, { userId: me, peerId: friendId, status: "ACTIVE", sessionId: mine.sessionId, startedAt: sec(), expiresAt });
        await db.put(T, { userId: friendId, peerId: me, status: "ACTIVE", sessionId: mine.sessionId, startedAt: sec(), expiresAt });
        return reply(200, { status: "ACTIVE", sessionId: mine.sessionId, expiresAt });
      }

      if (route === "PUT /trace/position") {
        const problem = validatePosition(body);
        if (problem) return reply(400, { error: problem });
        const mine = await getRow(me, body.friendId);
        const theirs = await getRow(body.friendId, me);
        if (!live(mine) || mine.status !== "ACTIVE" || !live(theirs) || theirs.status !== "ACTIVE")
          return reply(409, { error: "No active trace with that friend" });
        const startedAt = mine.startedAt ?? sec();
        if (sec() >= startedAt + ACTIVE_MAX_SECONDS) {
          await dropPair(me, body.friendId);
          return reply(409, { error: "This trace reached its 24 hour limit. Ask again to keep going." });
        }
        // Using it keeps it alive: slide my row's expiry forward, never past the hard cap.
        const expiresAt = Math.min(sec() + ACTIVE_IDLE_SECONDS, startedAt + ACTIVE_MAX_SECONDS);
        await db.put(T, { ...mine, startedAt, lat: body.lat, lon: body.lon, acc: body.acc ?? null, posAt: sec(), expiresAt });
        return reply(200, { expiresAt });
      }

      if (route === "DELETE /trace/{friendId}") {
        const friendId = event.pathParameters?.friendId;
        if (!isId(friendId)) return reply(400, { error: "friendId required" });
        const theirs = await getRow(friendId, me);
        await db.remove(T, { userId: me, peerId: friendId });
        // If I am ending a pending ask or an active session, they are told by their row disappearing; if they had
        // already declined, leave their DECLINED row alone only when it is mine to clear.
        if (theirs && theirs.status !== "DECLINED") await db.remove(T, { userId: friendId, peerId: me });
        return reply(204);
      }

      return reply(404, { error: "Unknown route" });
    } catch (error) {
      console.error("trace failed:", error?.name);   // the name only: never a position, body or id
      return reply(500, { error: "Something went wrong" });
    }
  };
}
