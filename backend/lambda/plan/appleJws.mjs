// Checks that a StoreKit 2 signed transaction (a JWS) really came from Apple. Node only (node:crypto); the rest of the plan
// logic never sees a certificate. Fails closed: anything unexpected is "not Apple's".
//
// A JWS header carries a certificate chain (x5c): leaf, intermediate, root. It is accepted only when
//   1. the algorithm is ES256 and the chain has exactly three certificates;
//   2. every certificate is inside its validity dates, each one is signed by the next, and the last is Apple Root CA - G3,
//      pinned by its SHA-256 fingerprint (so a chain to any other authority is refused);
//   3. the leaf and the intermediate carry Apple's App Store marker extensions. (This matters: Apple's root also signs
//      certificates for developers in general, and those must not be able to forge a purchase.)
//   4. the signature over header.payload verifies with the leaf's public key.

import { X509Certificate, createPublicKey, verify as cryptoVerify } from "node:crypto";

// Apple Root CA - G3 (valid to 2039). Read from the macOS system keychain: `security find-certificate -c "Apple Root CA - G3" -p`.
export const APPLE_ROOT_G3_SHA256 = "63:34:3A:BF:B8:9A:6A:03:EB:B5:7E:9B:3F:5F:A7:BE:7C:4F:5C:75:6F:30:17:B3:A8:C4:88:C3:65:3E:91:79";
// DER encodings of the marker OIDs: 1.2.840.113635.100.6.11.1 (leaf, App Store receipt signing) and 1.2.840.113635.100.6.2.1 (intermediate).
const LEAF_OID = Buffer.from("060A2A864886F76364060B01", "hex");
const INTERMEDIATE_OID = Buffer.from("060A2A864886F76364060201", "hex");

const b64url = (s) => Buffer.from(s.replace(/-/g, "+").replace(/_/g, "/"), "base64");

/** Returns the decoded payload when `jws` is genuinely Apple's, otherwise null. `roots`, `at` and `requireMarkers` exist so tests can use their own chain. */
export function verifyAppleJws(jws, { roots = [APPLE_ROOT_G3_SHA256], at = new Date(), requireMarkers = true } = {}) {
  try {
    if (typeof jws !== "string") return null;
    const parts = jws.split(".");
    if (parts.length !== 3) return null;
    const header = JSON.parse(b64url(parts[0]).toString("utf8"));
    if (header.alg !== "ES256" || !Array.isArray(header.x5c) || header.x5c.length !== 3) return null;
    const chain = header.x5c.map((der) => new X509Certificate(Buffer.from(der, "base64")));

    for (const cert of chain) {
      if (new Date(cert.validFrom) > at || new Date(cert.validTo) < at) return null;
    }
    if (!chain[0].verify(chain[1].publicKey) || !chain[1].verify(chain[2].publicKey)) return null;
    if (!chain[2].verify(chain[2].publicKey)) return null;                       // the root signs itself
    if (!roots.includes(chain[2].fingerprint256)) return null;                  // ...and is the one Apple root we trust
    if (requireMarkers && (!chain[0].raw.includes(LEAF_OID) || !chain[1].raw.includes(INTERMEDIATE_OID))) return null;

    const ok = cryptoVerify("sha256", Buffer.from(`${parts[0]}.${parts[1]}`), { key: createPublicKey(chain[0].publicKey.export({ type: "spki", format: "pem" })), dsaEncoding: "ieee-p1363" }, b64url(parts[2]));
    if (!ok) return null;
    return JSON.parse(b64url(parts[1]).toString("utf8"));
  } catch {
    return null;
  }
}
