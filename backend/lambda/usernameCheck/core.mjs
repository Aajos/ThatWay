// "Is this username free?" for the sign-up screen. Nobody is signed in at that point, so this route is PUBLIC (no JWT
// authorizer): it answers only available or not and why, never who owns a name, never an id or an email, and it is
// rate limited on the API route. Cognito's own SignUp is still the final word (a name taken a second ago is refused there).
//
// Rules, which the app applies too: lowercase letters, digits and underscore; start with a letter; 3 to 20 characters.
// Names are compared in lowercase, so "Sam" and "sam" cannot both exist.

export const RULE = /^[a-z][a-z0-9_]{2,19}$/;
export const RESERVED = ["admin", "administrator", "root", "support", "help", "thatway", "staff", "moderator", "system", "official", "null", "undefined"];

const reply = (statusCode, body) => ({ statusCode, headers: { "Content-Type": "application/json" }, body: JSON.stringify(body) });

/** `db` needs queryIndex(table, index, attr, value). */
export function makeHandler({ db }) {
  return async function handler(event) {
    try {
      const raw = event.queryStringParameters?.username;
      if (typeof raw !== "string" || raw.length === 0 || raw.length > 64) return reply(400, { error: "username required" });
      const typed = raw.trim();
      const name = typed.toLowerCase();
      if (!RULE.test(name)) return reply(200, { available: false, reason: "invalid" });
      if (RESERVED.includes(name)) return reply(200, { available: false, reason: "reserved" });

      let taken = (await db.queryIndex("Users", "byUsername", "username", name)).length > 0;
      // Older accounts may have been created with capitals: check the spelling the person typed as well.
      if (!taken && typed !== name) taken = (await db.queryIndex("Users", "byUsername", "username", typed)).length > 0;
      return reply(200, taken ? { available: false, reason: "taken" } : { available: true });
    } catch (error) {
      console.error("usernameCheck failed:", error?.name);   // the name only
      return reply(500, { error: "Something went wrong" });
    }
  };
}
