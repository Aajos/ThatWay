const {
    CognitoIdentityProviderClient, AdminCreateUserCommand, AdminGetUserCommand,
} = require("@aws-sdk/client-cognito-identity-provider");
const { QueryCommand, PutCommand } = require("@aws-sdk/lib-dynamodb");
const { client, USERS_TABLE, jsonResponse } = require("./shared/dynamo");
const { verifyAppleIdentityToken } = require("./shared/appleVerify");

const cognito = new CognitoIdentityProviderClient({});
const USER_POOL_ID = process.env.USER_POOL_ID;

// Public route (no Cognito authorizer — there's no session yet). One-time bridge between
// "I have a verified Apple identity" and "I have a Cognito account to run CUSTOM_AUTH
// against". The actual login still happens via Cognito's InitiateAuth/RespondToAuthChallenge,
// verified independently by verifyAuthChallengeResponse.js — this endpoint only ever
// provisions an account, it never itself authenticates anyone.
//
// POST /auth/apple/register  { "identityToken": "...", "username"?: "..." }
exports.handler = async (event) => {
    let body;
    try {
        body = JSON.parse(event.body || "{}");
    } catch {
        return jsonResponse(400, { message: "Invalid JSON body." });
    }
    if (!body.identityToken) {
        return jsonResponse(400, { message: "Missing identityToken." });
    }

    let claims;
    try {
        claims = await verifyAppleIdentityToken(body.identityToken);
    } catch {
        return jsonResponse(401, { message: "Invalid Apple identity token." });
    }

    const cognitoUsername = `apple_${claims.sub}`.replace(/[^A-Za-z0-9_.-]/g, "_");

    const existing = await cognito.send(
        new AdminGetUserCommand({ UserPoolId: USER_POOL_ID, Username: cognitoUsername })
    ).catch((err) => {
        if (err.name === "UserNotFoundException") return null;
        throw err;
    });

    if (existing) {
        return jsonResponse(200, { registered: true, username: cognitoUsername });
    }

    const chosenUsername = (body.username || "").trim();
    if (!chosenUsername) {
        // First time we've seen this Apple account and no handle was supplied yet — the
        // app should collect one (same field as password sign-up) and retry.
        return jsonResponse(200, { registered: false, needsUsername: true });
    }

    const usernameLower = chosenUsername.toLowerCase();
    const taken = await client.send(new QueryCommand({
        TableName: USERS_TABLE,
        IndexName: "byUsername",
        KeyConditionExpression: "usernameLower = :u",
        ExpressionAttributeValues: { ":u": usernameLower },
    }));
    if ((taken.Items || []).length > 0) {
        return jsonResponse(409, { message: "That username is taken." });
    }

    const email = claims.email || `${cognitoUsername}@privaterelay.appleid.com`;
    const created = await cognito.send(new AdminCreateUserCommand({
        UserPoolId: USER_POOL_ID,
        Username: cognitoUsername,
        MessageAction: "SUPPRESS",
        UserAttributes: [
            { Name: "email", Value: email },
            { Name: "email_verified", Value: "true" },
        ],
    }));

    const sub = created.User.Attributes.find((a) => a.Name === "sub")?.Value;
    await client.send(new PutCommand({
        TableName: USERS_TABLE,
        Item: { id: sub, username: chosenUsername, usernameLower, email, createdAt: new Date().toISOString() },
    }));

    return jsonResponse(201, { registered: true, username: cognitoUsername });
};
