// Cognito "Define auth challenge" trigger for the CUSTOM_AUTH flow used by Sign in with
// Apple: one challenge (verify the Apple identity token), then issue tokens on success.
exports.handler = async (event) => {
    const session = event.request.session;

    if (session.length === 0) {
        event.response.challengeName = "CUSTOM_CHALLENGE";
        event.response.issueTokens = false;
        event.response.failAuthentication = false;
    } else if (
        session.length === 1 &&
        session[0].challengeName === "CUSTOM_CHALLENGE" &&
        session[0].challengeResult === true
    ) {
        event.response.issueTokens = true;
        event.response.failAuthentication = false;
    } else {
        event.response.issueTokens = false;
        event.response.failAuthentication = true;
    }

    return event;
};
