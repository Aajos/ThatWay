// Closing an account: two different things, deliberately kept apart (see docs/vault/features/trace-grants.md).
//
//   DELETE EVERYTHING   (POST /account/delete)      removes the person and every record that points at them: friendships and
//                       requests (both rows of each), trace permissions in both roles, the last known position, blocks (made and
//                       received), old trace rows, token offers, the purchase record, the profile, and the sign-in itself.
//                       Reports are the one exception and the app says so first: a report protects other people, so reports
//                       made by or about this account are kept until they expire (a year) and hold no location.
//   DEACTIVATE          (POST /account/deactivate)  the same clean-out of everything social, but the sign-in and the purchase
//                       record are kept so the plan survives. The profile is hidden from search. It is a choice the person makes
//                       by name, never a default. A deactivated account that is not reactivated is deleted after 12 months by the
//                       daily sweep (the app tells people this up front, so the sweep must exist and run).
//   REACTIVATE          (POST /account/reactivate)  brings the profile back. Friends are NOT restored: they were removed.
//
// Every step is safe to repeat, so a half-finished delete can simply be run again. Pure logic: `db` and `auth` are injected.
// Nothing here logs a user id, a name or an email; errors are logged by name only.

export const DEACTIVATION_RETENTION_SECONDS = 365 * 86400;
export const DELETING_GRACE_SECONDS = 86400;       // a delete that stopped half-way is finished by the sweep after a day

const reply = (statusCode, body) => ({ statusCode, headers: { "Content-Type": "application/json" }, body: JSON.stringify(body) });
const BATCH = 40;                                  // operations per transaction (DynamoDB allows 100)

/**
 * `db` needs get(table, key), put(table, item), remove(table, key), query(table, partitionValue), queryIndex(table, index, attr, value),
 * scan(table), transact([{remove:{table,key}}...]). `auth.deleteUser(username)` removes the sign-in (Cognito AdminDeleteUser).
 */
export function makeHandler({ db, auth, now = () => Date.now() }) {
  const sec = () => Math.floor(now() / 1000);

  async function removeAll(ops) {
    for (let i = 0; i < ops.length; i += BATCH) await db.transact(ops.slice(i, i + BATCH).map((remove) => ({ remove })));
  }

  /** Everything social: friendships and requests, trace permissions (both roles), position, blocks, trace rows, offers. */
  async function clearSocial(me) {
    const ops = [];
    for (const f of await db.query("Friends", me)) {
      ops.push({ table: "Friends", key: { userId: me, otherUserId: f.otherUserId } });
      ops.push({ table: "Friends", key: { userId: f.otherUserId, otherUserId: me } });
    }
    for (const g of await db.query("Grants", me)) ops.push({ table: "Grants", key: { traceeId: me, tracerId: g.tracerId } });
    for (const g of await db.queryIndex("Grants", "byTracer", "tracerId", me)) ops.push({ table: "Grants", key: { traceeId: g.traceeId, tracerId: me } });
    for (const b of await db.query("Blocks", me)) ops.push({ table: "Blocks", key: { blockerId: me, blockedId: b.blockedId } });
    for (const b of await db.queryIndex("Blocks", "byBlocked", "blockedId", me)) ops.push({ table: "Blocks", key: { blockerId: b.blockerId, blockedId: me } });
    for (const t of await db.query("TraceSessions", me)) {
      ops.push({ table: "TraceSessions", key: { userId: me, peerId: t.peerId } });
      ops.push({ table: "TraceSessions", key: { userId: t.peerId, peerId: me } });
    }
    for (const o of await db.query("NearbyOffers", me)) ops.push({ table: "NearbyOffers", key: { userId: me, fromUserId: o.fromUserId } });
    await removeAll(ops);
    await db.remove("Positions", { userId: me });
  }

  async function deleteEverything(me, fallbackUsername) {
    const user = await db.get("Users", { id: me });
    if (user) await db.put("Users", { ...user, deactivated: true, deleting: true, deactivatedAt: sec() });   // hidden from search straight away
    await clearSocial(me);
    await db.remove("Entitlements", { userId: me });
    const username = user?.username ?? fallbackUsername;
    if (username) await auth.deleteUser(username);                       // the sign-in itself
    await db.remove("Users", { id: me });                               // last, so a stopped delete can be found and repeated
  }

  async function deactivate(me) {
    const user = await db.get("Users", { id: me });
    if (!user) return false;
    await clearSocial(me);
    await db.put("Users", { ...user, deactivated: true, deactivatedAt: sec() });
    return true;
  }

  async function sweep() {
    let finished = 0;
    for (const u of await db.scan("Users")) {
      if (!u.deactivated || !u.deactivatedAt) continue;
      const age = sec() - u.deactivatedAt;
      if (u.deleting ? age >= DELETING_GRACE_SECONDS : age >= DEACTIVATION_RETENTION_SECONDS) { await deleteEverything(u.id, u.username); finished++; }
    }
    return finished;
  }

  return async function handler(event) {
    try {
      if (event?.source === "aws.events") return { swept: await sweep() };            // the daily schedule
      const me = event.requestContext?.authorizer?.jwt?.claims?.sub;
      if (!me) return reply(401, { error: "Not signed in" });
      const claimedName = event.requestContext?.authorizer?.jwt?.claims?.username;
      const route = event.routeKey;
      let body = {};
      if (event.body) { try { body = JSON.parse(event.body); } catch { return reply(400, { error: "Invalid JSON" }); } }

      if (route === "GET /account") {
        const user = await db.get("Users", { id: me });
        if (!user) return reply(404, { error: "No account" });
        return reply(200, user.deactivated && !user.deleting
          ? { status: "deactivated", deactivatedAt: user.deactivatedAt, deletesAt: user.deactivatedAt + DEACTIVATION_RETENTION_SECONDS }
          : { status: "active" });
      }
      // Both destructive routes insist on an explicit confirmation in the request itself.
      if (route === "POST /account/delete") {
        if (body.confirmed !== true) return reply(400, { error: "Confirmation required" });
        await deleteEverything(me, claimedName);
        return reply(200, { status: "DELETED" });
      }
      if (route === "POST /account/deactivate") {
        if (body.confirmed !== true) return reply(400, { error: "Confirmation required" });
        if (!(await deactivate(me))) return reply(404, { error: "No account" });
        return reply(200, { status: "DEACTIVATED", deletesAt: sec() + DEACTIVATION_RETENTION_SECONDS });
      }
      if (route === "POST /account/reactivate") {
        const user = await db.get("Users", { id: me });
        if (!user || user.deleting) return reply(404, { error: "No account" });
        const { deactivated, deactivatedAt, ...rest } = user;
        await db.put("Users", rest);
        return reply(200, { status: "ACTIVE" });
      }
      return reply(404, { error: "Unknown route" });
    } catch (error) {
      console.error("account failed:", error?.name);       // the name only
      return reply(500, { error: "Something went wrong" });
    }
  };
}
