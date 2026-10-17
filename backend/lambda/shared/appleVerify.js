const { jwtVerify, createRemoteJWKSet } = require("jose");

const APPLE_ISSUER = "https://appleid.apple.com";

// Cached across warm Lambda invocations, same as any module-level client.
const APPLE_JWKS = createRemoteJWKSet(new URL("https://appleid.apple.com/auth/keys"));

// Verifies a raw Apple identity token (the JWT string from ASAuthorizationAppleIDCredential)
// against Apple's live public keys. Throws if the signature, issuer, audience, or expiry
// don't check out. `payload.sub` is Apple's stable, per-app-id user identifier.
async function verifyAppleIdentityToken(token) {
    const { payload } = await jwtVerify(token, APPLE_JWKS, {
        issuer: APPLE_ISSUER,
        audience: process.env.APPLE_BUNDLE_ID,
    });
    return payload;
}

module.exports = { verifyAppleIdentityToken };
