// Trace permissions ("grants"), blocking and reports. Pure logic, no AWS imports: runs under `jsc -m test.mjs` or `node test.mjs`.
// index.mjs wires it to DynamoDB. Needs the tables Grants, Positions, Blocks, Reports (backend/scripts/aws.sh grants).
//
// The model (see docs/vault/features/trace-grants.md):
//   - The person being TRACED (the "tracee") grants a permission to ONE tracer, one-way. Nothing about the tracer's own position
//     is ever uploaded or stored: the tracer sends only a rounded distance BAND, and the server keeps only that band.
//   - EVERY grant has a timer the traced person chose: from 15 minutes up to a hard 24 hours, never more than was asked for.
//     A grant is either a ONE-OFF (it also ends when the tracer switches to someone else) or a WINDOW (it survives switching).
//   - A grant also ends the moment the tracer's plan does: whichever comes first.
//   - A tracer holds at most 10 live grants at once and 5 unanswered requests. An unanswered request disappears after 30 minutes.
//   - Every use goes through authorise(): not blocked either way, mutual ACCEPTED friends, a live ACTIVE grant inside its
//     window, a live plan for the tracer, on the server's clock. Any failure looks identical to the tracer: "User cannot be traced".
//   - A request to someone who blocked you (or who is not your friend) is stored as a phantom: it looks exactly like an
//     unanswered request and expires the same way, so nothing reveals a block.
//   - Not continuous: the tracee's phone uploads a position only while it has a live grant and the app is active. The tracer
//     may ask for a new location at most once every 2 minutes; the tracee is told at most once every 30 minutes.
//   - Blocking ends the friendship, every grant and every request in both directions, silently. Never throttled.
//   - Nothing is logged except an error name.

export const GRANT_MIN_SECONDS = 900;           // 15 minutes
export const GRANT_MAX_SECONDS = 86400;         // 24 hours, always
export const REQUEST_TTL_SECONDS = 1800;        // an unanswered request disappears after 30 minutes
export const LOCATE_MIN_INTERVAL = 120;         // the tracer can ask for a new location once every 2 minutes
export const FOLLOW_UP_WINDOW = 30;             // ...and for 30 s after asking, may re-read to collect the fresh fix that ask caused
export const NEAR_PUSH_INTERVAL = 600;          // "X is nearby looking for you" at most every 10 minutes
export const NOTICE_MIN_INTERVAL = 1800;        // the tracee is told "still tracing you" at most once every 30 minutes
export const POSITION_TTL_SECONDS = 7200;       // a last-known position is kept for 2 hours at most
export const MAX_OPEN_REQUESTS = 5;
export const MAX_ACTIVE_GRANTS = 10;            // one tracer can hold at most 10 live grants (they look at one at a time)
export const CONSENT_VERSION_MAX_LENGTH = 32;
export const REPORT_CATEGORIES = ["unwanted_tracing", "harassment", "threat", "impersonation", "other"];
export const REPORT_DETAILS_MAX = 500;
export const REPORT_RETENTION_SECONDS = 365 * 86400;

const reply = (statusCode, body) => ({ statusCode, headers: { "Content-Type": "application/json" }, body: body === undefined ? "" : JSON.stringify(body) });
const isId = (v) => typeof v === "string" && v.length > 0 && v.length <= 128;
const isNum = (v) => typeof v === "number" && Number.isFinite(v);
const CANNOT = { error: "User cannot be traced" };       // the one message for every failure, whatever the cause

/** How far the tracer is, as the traced person is shown it. Rounded up, so it never claims to be closer than it is. */
export function distanceBand(metres) {
  if (!isNum(metres) || metres < 0) return null;
  if (metres < 50) return "under 50 m";
  if (metres < 200) return "under 200 m";
  if (metres < 500) return "under 500 m";
  if (metres < 1000) return "under 1 km";
  if (metres < 20000) return `about ${Math.ceil(metres / 1000)} km`;
  return "over 20 km";
}

const randomId = () => (globalThis.crypto?.randomUUID?.() ?? `${Date.now().toString(36)}-${Math.random().toString(36).slice(2)}${Math.random().toString(36).slice(2)}`);

/**
 * `db` needs: get(table, key), put(table, item), query(table, userId), queryIndex(table, index, attr, value),
 * remove(table, key), transact([{put:{table,item}} | {remove:{table,key}}]).
 * `planUntil(userId)` says when that person's plan (trace3, trace24, trace+, lifetrace) ends, as epoch seconds: the server's
 * own record. null/0/undefined means no plan; Infinity means it never ends (or the check is switched off).
 */
export function makeHandler({ db, now = () => Date.now(), planUntil = async () => Infinity, newId = randomId, notify = async () => {} }) {
  // notify(userId, "request" | "still", fromUserId): a push to that person's phones. Best effort: a failure never fails the request.
  const tell = async (userId, kind, from) => { try { await notify(userId, kind, from); } catch { /* push is a convenience, never a dependency */ } };
  const sec = () => Math.floor(now() / 1000);

  const blockedEitherWay = async (a, b) =>
    Boolean(await db.get("Blocks", { blockerId: a, blockedId: b }) || await db.get("Blocks", { blockerId: b, blockedId: a }));
  const mutualFriends = async (a, b) =>
    (await db.get("Friends", { userId: a, otherUserId: b }))?.status === "ACCEPTED" &&
    (await db.get("Friends", { userId: b, otherUserId: a }))?.status === "ACCEPTED";
  const reachable = async (a, b) => !(await blockedEitherWay(a, b)) && (await mutualFriends(a, b));
  const planLive = async (userId) => { const until = await planUntil(userId); return Boolean(until) && until > sec(); };
  const liveGrant = (row) => Boolean(row) && row.status === "ACTIVE" && row.grantedUntil > sec() && row.grantedUntil - row.grantedAt <= GRANT_MAX_SECONDS;

  /** The single safety check. Returns the grant row when (and only when) tracing is allowed right now. */
  async function authorise(tracerId, traceeId) {
    if (tracerId === traceeId) return null;
    if (!(await reachable(tracerId, traceeId))) { await endGrant(traceeId, tracerId, true); return null; }
    const row = await db.get("Grants", { traceeId, tracerId });
    if (!liveGrant(row)) return null;
    if (!(await planLive(tracerId))) { await endGrant(traceeId, tracerId, true); return null; }     // plan over: so is the trace, for good
    return row;
  }

  async function dropPositionIfUnwatched(traceeId) {
    const rows = await db.query("Grants", traceeId);
    if (!rows.some(liveGrant)) await db.remove("Positions", { userId: traceeId });     // keep nothing nobody may see
  }
  /** `onlyActive`: leave a request (real or phantom) alone, so that checking a trace can never reveal which requests are phantoms. */
  async function endGrant(traceeId, tracerId, onlyActive = false) {
    const row = await db.get("Grants", { traceeId, tracerId });
    if (!row || (onlyActive && row.status !== "ACTIVE")) return;
    await db.remove("Grants", { traceeId, tracerId });
    await dropPositionIfUnwatched(traceeId);
  }
  const liveCountFor = async (tracerId) => (await db.queryIndex("Grants", "byTracer", "tracerId", tracerId)).filter(liveGrant).length;
  const hoursBetween = (v, lo, hi, fallback) => Math.min(hi, Math.max(lo, isNum(v) ? v : fallback));

  return async function handler(event) {
    try {
      const me = event.requestContext?.authorizer?.jwt?.claims?.sub;
      if (!me) return reply(401, { error: "Not signed in" });
      const route = event.routeKey;
      let body = {};
      if (event.body) { try { body = JSON.parse(event.body); } catch { return reply(400, { error: "Invalid JSON" }); } }

      // ---- tracer: ask a friend for permission to trace them
      if (route === "POST /grants/request") {
        const { friendId } = body;
        if (!isId(friendId) || friendId === me) return reply(400, { error: "friendId required" });
        // Whether it is a one-off or a window is the TRACED person's choice, made when they answer. A request only carries a length.
        if (!(await planLive(me))) return reply(402, { error: "A trace plan is needed to ask" });
        const ok = await reachable(me, friendId);
        const existing = await db.get("Grants", { traceeId: friendId, tracerId: me });
        if (ok && liveGrant(existing)) return reply(200, { status: "ACTIVE" });
        const mine = await db.queryIndex("Grants", "byTracer", "tracerId", me);
        if (mine.filter((r) => r.status === "REQUESTED" && r.expiresAt > sec()).length >= MAX_OPEN_REQUESTS) return reply(429, { error: "Too many waiting requests" });
        if (mine.filter(liveGrant).length >= MAX_ACTIVE_GRANTS) return reply(429, { error: `You can trace up to ${MAX_ACTIVE_GRANTS} people at once. Stop one first.` });
        // Both kinds carry the length the tracer is asking for (15 minutes to 24 hours); the tracee can only shorten it.
        const requestedHours = hoursBetween(body.hours, GRANT_MIN_SECONDS / 3600, GRANT_MAX_SECONDS / 3600, 1);
        // Not reachable (blocked, not friends, unknown): stored as a phantom so it looks exactly like an unanswered request.
        await db.put("Grants", { traceeId: friendId, tracerId: me, status: "REQUESTED", kind: "window", requestedHours, requestedAt: sec(), expiresAt: sec() + REQUEST_TTL_SECONDS, ...(ok ? {} : { phantom: true }) });
        if (ok) await tell(friendId, "request", me);                  // a phantom (blocked) request never reaches the person
        return reply(200, { status: "WAITING", expiresAt: sec() + REQUEST_TTL_SECONDS });
      }

      // ---- both sides: what do I have? (the tracer sees almost nothing; the tracee sees who, for how long, how far)
      if (route === "GET /grants") {
        const asTraced = [];
        for (const r of await db.query("Grants", me)) {
          if (r.status === "REQUESTED") {
            if (r.expiresAt <= sec() || r.phantom || !(await reachable(me, r.tracerId))) continue;   // never deleted here: that would reveal a block
            asTraced.push({ tracerId: r.tracerId, status: "REQUESTED", kind: r.kind, requestedHours: r.requestedHours, requestedAt: r.requestedAt, requestExpiresAt: r.expiresAt });
            continue;
          }
          if (!liveGrant(r)) continue;
          if (!(await authorise(r.tracerId, me))) continue;               // blocked, unfriended or plan over: ended just now
          const item = { tracerId: r.tracerId, status: "ACTIVE", kind: r.kind };
          item.until = r.grantedUntil;                                       // only the TRACED person is ever shown the end time
          if (r.lastLookedAt) item.lastLookedAt = r.lastLookedAt;
          if (r.band && sec() - (r.bandAt ?? 0) <= 600) item.band = r.band;   // a distance older than 10 minutes is not shown
          if (r.noticePending) { item.stillTracing = true; await db.put("Grants", { ...r, noticePending: false }); }
          asTraced.push(item);
        }
        const asTracer = [];
        const until = await planUntil(me);
        const lapsed = !(until && until > sec());
        for (const r of await db.queryIndex("Grants", "byTracer", "tracerId", me)) {
          if (r.status === "REQUESTED") { if (r.expiresAt > sec()) asTracer.push({ traceeId: r.traceeId, status: "waiting", kind: r.kind, expiresAt: r.expiresAt }); }
          else if (liveGrant(r)) {
            if (lapsed) { await endGrant(r.traceeId, me, true); continue; }       // plan over: the traces end with it
            asTracer.push({ traceeId: r.traceeId, status: "active", kind: r.kind });   // never the time left
          }
        }
        return reply(200, { asTraced, asTracer, plan: { until: Number.isFinite(until) ? until : null, active: !lapsed } });
      }

      // ---- tracee: grant (with the slider) or decline
      if (route === "POST /grants/respond") {
        const { tracerId, action } = body;
        if (!isId(tracerId)) return reply(400, { error: "tracerId required" });
        if (action !== "grant" && action !== "decline") return reply(400, { error: "action must be grant or decline" });
        const row = await db.get("Grants", { traceeId: me, tracerId });
        if (!row || row.status !== "REQUESTED" || row.expiresAt <= sec() || row.phantom) return reply(404, { error: "No request to answer" });
        if (action === "decline") { await db.remove("Grants", { traceeId: me, tracerId }); return reply(200, { status: "DECLINED" }); }
        // The app asks twice and checks Face ID / Touch ID / passcode first; the server insists on the second confirmation
        // and on knowing which wording was agreed to.
        if (body.confirmed !== true) return reply(400, { error: "Confirmation required" });
        if (body.kind !== "oneoff" && body.kind !== "window") return reply(400, { error: "kind must be oneoff or window" });
        if (typeof body.consentVersion !== "string" || body.consentVersion.length === 0 || body.consentVersion.length > CONSENT_VERSION_MAX_LENGTH)
          return reply(400, { error: "consentVersion required" });
        if (!(await reachable(me, tracerId))) return reply(404, { error: "No request to answer" });
        if (await liveCountFor(tracerId) >= MAX_ACTIVE_GRANTS) return reply(409, { error: "This request can't be accepted right now" });
        const hours = Math.min(row.requestedHours, hoursBetween(body.hours, GRANT_MIN_SECONDS / 3600, GRANT_MAX_SECONDS / 3600, row.requestedHours));   // never more than was asked for
        const seconds = Math.min(GRANT_MAX_SECONDS, Math.max(GRANT_MIN_SECONDS, Math.round(hours * 3600)));
        const grantedAt = sec();
        await db.put("Grants", { traceeId: me, tracerId, status: "ACTIVE", kind: body.kind, grantedAt, grantedUntil: grantedAt + seconds, consentVersion: body.consentVersion, expiresAt: grantedAt + seconds });
        return reply(200, { status: "ACTIVE", until: grantedAt + seconds });
      }

      // ---- tracee: stop a tracer now (always works, never throttled)
      if (route === "POST /grants/revoke") {
        if (!isId(body.tracerId)) return reply(400, { error: "tracerId required" });
        await endGrant(me, body.tracerId);
        return reply(200, { status: "REVOKED" });
      }

      // ---- tracer: switching away or stopping. Ends a one-off; a window stays until it runs out. (Also withdraws a waiting request.)
      if (route === "POST /grants/release") {
        if (!isId(body.traceeId)) return reply(400, { error: "traceeId required" });
        const row = await db.get("Grants", { traceeId: body.traceeId, tracerId: me });
        if (row && (row.kind === "oneoff" || row.status === "REQUESTED")) await endGrant(body.traceeId, me);
        return reply(200, { status: "RELEASED" });
      }

      // ---- tracee's phone: upload a position, only while someone may see it
      if (route === "PUT /grants/position") {
        if (!isNum(body.lat) || body.lat < -90 || body.lat > 90 || !isNum(body.lon) || body.lon < -180 || body.lon > 180) return reply(400, { error: "position out of range" });
        const acc = isNum(body.acc) && body.acc >= 0 && body.acc <= 100000 ? body.acc : null;
        const rows = await db.query("Grants", me);
        let watched = false;
        for (const r of rows.filter(liveGrant)) if (await authorise(r.tracerId, me)) { watched = true; break; }
        if (!watched) return reply(409, { error: "Nobody may trace you right now" });
        await db.put("Positions", { userId: me, lat: body.lat, lon: body.lon, acc, at: sec(), expiresAt: sec() + POSITION_TTL_SECONDS });
        return reply(200, { ok: true });
      }

      // ---- tracer: "request new location" (also what opening the compass does)
      if (route === "POST /grants/locate") {
        const traceeId = body.traceeId;
        if (!isId(traceeId)) return reply(400, { error: "traceeId required" });
        if (!(await planLive(me))) { await endGrant(traceeId, me, true); return reply(402, { error: "A trace plan is needed" }); }
        const row = await authorise(me, traceeId);
        if (!row) return reply(403, CANNOT);
        const last = row.lastLocateAt ?? 0;
        // A follow-up is not a new request: it only re-reads the stored position shortly after a real one, so the fresh fix the
        // traced phone uploads in answer reaches the tracer. It changes nothing and tells nobody anything.
        if (body.followUp === true) {
          if (sec() - last > FOLLOW_UP_WINDOW) return reply(429, { error: "Try again in a moment", retryAfter: Math.max(1, LOCATE_MIN_INTERVAL - (sec() - last)) });
          const p = await db.get("Positions", { userId: traceeId });
          return reply(200, { position: p && p.expiresAt > sec() ? { lat: p.lat, lon: p.lon, acc: p.acc, age: sec() - p.at } : null, retryAfter: Math.max(0, LOCATE_MIN_INTERVAL - (sec() - last)) });
        }
        if (sec() - last < LOCATE_MIN_INTERVAL) return reply(429, { error: "Try again in a moment", retryAfter: LOCATE_MIN_INTERVAL - (sec() - last) });
        const pos = await db.get("Positions", { userId: traceeId });
        const next = { ...row, lastLocateAt: sec(), lastLookedAt: sec() };
        const band = distanceBand(body.distanceM);                                   // the tracer sent a number; only a band is kept
        if (band) { next.band = band; next.bandAt = sec(); }
        if (sec() - (row.lastNoticeAt ?? 0) >= NOTICE_MIN_INTERVAL) { next.lastNoticeAt = sec(); next.noticePending = true; }
        await db.put("Grants", next);
        if (next.noticePending && next.lastNoticeAt === sec()) await tell(traceeId, "still", me);
        // Close by: ask the traced person to open ThatWay, because the precise last metres need both apps open.
        if ((band === "under 50 m" || band === "under 200 m") && sec() - (row.lastNearPushAt ?? 0) >= NEAR_PUSH_INTERVAL) {
          await db.put("Grants", { ...next, lastNearPushAt: sec() });
          await tell(traceeId, "near", me);
        }
        const position = pos && pos.expiresAt > sec() ? { lat: pos.lat, lon: pos.lon, acc: pos.acc, age: sec() - pos.at } : null;
        return reply(200, { position, retryAfter: LOCATE_MIN_INTERVAL });
      }

      // ---- push: this phone's token, so requests can reach a closed app
      if (route === "PUT /devices") {
        const { token, environment } = body;
        if (typeof token !== "string" || !/^[0-9a-fA-F]{32,200}$/.test(token)) return reply(400, { error: "token required" });
        if (environment !== "sandbox" && environment !== "production") return reply(400, { error: "environment required" });
        await db.put("Devices", { userId: me, token: token.toLowerCase(), environment, updatedAt: sec() });
        return reply(200, { ok: true });
      }
      if (route === "POST /devices/remove") {                                   // sign-out: this phone stops receiving this person's pushes
        const token = typeof body.token === "string" ? body.token.toLowerCase() : null;
        for (const d of await db.query("Devices", me)) if (!token || d.token === token) await db.remove("Devices", { userId: me, token: d.token });
        return reply(200, { ok: true });
      }

      // ---- blocking (never throttled; the blocked person is told nothing)
      if (route === "POST /blocks") {
        const { userId } = body;
        if (!isId(userId) || userId === me) return reply(400, { error: "userId required" });
        await db.transact([
          { put: { table: "Blocks", item: { blockerId: me, blockedId: userId, at: sec() } } },
          { remove: { table: "Friends", key: { userId: me, otherUserId: userId } } },
          { remove: { table: "Friends", key: { userId: userId, otherUserId: me } } },
          { remove: { table: "Grants", key: { traceeId: me, tracerId: userId } } },
          { remove: { table: "Grants", key: { traceeId: userId, tracerId: me } } },
          { remove: { table: "TraceSessions", key: { userId: me, peerId: userId } } },
          { remove: { table: "TraceSessions", key: { userId: userId, peerId: me } } },
          { remove: { table: "NearbyOffers", key: { userId: me, fromUserId: userId } } },
          { remove: { table: "NearbyOffers", key: { userId: userId, fromUserId: me } } },
        ]);
        await dropPositionIfUnwatched(me); await dropPositionIfUnwatched(userId);
        return reply(200, { status: "BLOCKED" });
      }
      if (route === "GET /blocks") {
        // The blocker sees the usernames of the people they blocked (they are no longer friends, so the app cannot look them up).
        const blocks = await db.query("Blocks", me);
        return reply(200, await Promise.all(blocks.map(async (b) => ({ userId: b.blockedId, username: (await db.get("Users", { id: b.blockedId }))?.username ?? null }))));
      }
      if (route === "DELETE /blocks/{userId}") {
        const userId = event.pathParameters?.userId;
        if (!isId(userId)) return reply(400, { error: "userId required" });
        await db.remove("Blocks", { blockerId: me, blockedId: userId });             // unblocking does not bring the friendship back
        return reply(200, { status: "UNBLOCKED" });
      }

      // ---- reporting (never throttled by us; stored for a person to read; holds no location)
      if (route === "POST /reports") {
        const { userId, category } = body;
        if (!isId(userId) || userId === me) return reply(400, { error: "userId required" });
        if (!REPORT_CATEGORIES.includes(category)) return reply(400, { error: "category not recognised" });
        const details = typeof body.details === "string" ? body.details.slice(0, REPORT_DETAILS_MAX) : "";
        const at = sec();
        await db.put("Reports", { reportId: newId(), reporterId: me, reportedId: userId, category, details, createdAt: at, expiresAt: at + REPORT_RETENTION_SECONDS });
        return reply(200, { status: "RECEIVED" });
      }

      return reply(404, { error: "Unknown route" });
    } catch (error) {
      console.error("grants failed:", error?.name);   // the name only
      return reply(500, { error: "Something went wrong" });
    }
  };
}
