import { DynamoDBClient } from "@aws-sdk/client-dynamodb";
import { DynamoDBDocumentClient, QueryCommand, GetCommand } from "@aws-sdk/lib-dynamodb";

const client = new DynamoDBClient({ region: "ap-southeast-2" });
const dynamodb = DynamoDBDocumentClient.from(client);

const ALLOWED = ["ACCEPTED", "PENDING", "INCOMING"];

export const handler = async (event) => {
  try {
    const userId = event.requestContext.authorizer.jwt.claims.sub;
    const status = (event.queryStringParameters?.status || "ACCEPTED").toUpperCase();

    if (!ALLOWED.includes(status)) {
      return {
        statusCode: 400,
        body: JSON.stringify({ error: "status must be ACCEPTED, PENDING or INCOMING" })
      };
    }

    const result = await dynamodb.send(
      new QueryCommand({
        TableName: "Friends",
        KeyConditionExpression: "userId = :userId",
        FilterExpression: "#status = :status",
        ExpressionAttributeNames: { "#status": "status" },
        ExpressionAttributeValues: { ":userId": userId, ":status": status }
      })
    );

    const rows = result.Items || [];

    const users = await Promise.all(
      rows.map((row) =>
        dynamodb.send(new GetCommand({ TableName: "Users", Key: { id: row.otherUserId } }))
      )
    );

    const friends = rows.map((row, i) => ({
      id: row.otherUserId,
      username: users[i].Item?.username ?? "unknown",
      status: row.status,
      requestedAt: row.requestedAt ?? null,
      acceptedAt: row.acceptedAt ?? null
    }));

    return { statusCode: 200, body: JSON.stringify(friends) };
  } catch (error) {
    console.error("Error:", error);
    return { statusCode: 500, body: JSON.stringify({ error: error.message }) };
  }
};
