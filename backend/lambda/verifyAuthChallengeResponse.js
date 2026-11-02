const { verifyAppleIdentityToken } = require("./shared/appleVerify");

// Cognito "Verify auth challenge response" trigger. `challengeAnswer` is the raw Apple
// identity token the app just got from ASAuthorizationAppleIDProvider. Re-verifying it here
// (rather than trusting authAppleRegister.js's earlier check) is what actually gates the
// CUSTOM_AUTH login — this is the one check that decides whether Cognito issues tokens.
exports.handler = async (event) => {
    const answer = event.request.challengeAnswer;
    const username = event.userName; // "apple_<sub>" — see authAppleRegister.js

    try {
        const claims = await verifyAppleIdentityToken(answer);
        const expectedSub = username.startsWith("apple_") ? username.slice("apple_".length) : null;
        event.response.answerCorrect = expectedSub !== null && claims.sub === expectedSub;
    } catch {
        event.response.answerCorrect = false;
    }

    return event;
};
