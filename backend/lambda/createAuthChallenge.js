// Cognito "Create auth challenge" trigger. Nothing to hand the client here — the "answer"
// it needs to produce (a fresh Apple identity token) doesn't depend on anything we generate.
exports.handler = async (event) => {
    if (event.request.challengeName === "CUSTOM_CHALLENGE") {
        event.response.publicChallengeParameters = {};
        event.response.privateChallengeParameters = {};
        event.response.challengeMetadata = "APPLE_IDENTITY_TOKEN";
    }
    return event;
};
