const { DynamoDBClient } = require("@aws-sdk/client-dynamodb");
const { DynamoDBDocumentClient } = require("@aws-sdk/lib-dynamodb");

const client = DynamoDBDocumentClient.from(new DynamoDBClient({}));

const USERS_TABLE = process.env.USERS_TABLE;
const FRIENDSHIPS_TABLE = process.env.FRIENDSHIPS_TABLE;

function jsonResponse(statusCode, body) {
    return {
        statusCode,
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(body),
    };
}

// The HTTP API JWT authorizer puts the verified token claims here — `sub` is the
// Cognito user id, safe to trust without re-checking the token ourselves.
function callerId(event) {
    return event.requestContext.authorizer.jwt.claims.sub;
}

function callerUsername(event) {
    const claims = event.requestContext.authorizer.jwt.claims;
    return claims["cognito:username"] || claims.username;
}

module.exports = { client, USERS_TABLE, FRIENDSHIPS_TABLE, jsonResponse, callerId, callerUsername };
