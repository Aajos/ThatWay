import { DynamoDBClient } from "@aws-sdk/client-dynamodb";
import { DynamoDBDocumentClient, PutCommand, DeleteCommand, GetCommand } from "@aws-sdk/lib-dynamodb";

const client = new DynamoDBClient({ region: "ap-southeast-2" });
const dynamodb = DynamoDBDocumentClient.from(client);

export const handler = async (event) => {
  try {
    const responderId = event.requestContext.authorizer.jwt.claims.sub;
    const { requesterId, action } = JSON.parse(event.body || "{}");

    if (!requesterId || !action) {
      return { statusCode: 400, body: JSON.stringify({ error: "requesterId and action required" }) };
    }
    if (action !== "accept" && action !== "reject") {
      return { statusCode: 400, body: JSON.stringify({ error: "Invalid action" }) };
    }

    // Only the recipient of a real request can respond to it
    const incoming = await dynamodb.send(
      new GetCommand({ TableName: "Friends", Key: { userId: responderId, otherUserId: requesterId } })
    );
    if (!incoming.Item || incoming.Item.status !== "INCOMING") {
      return { statusCode: 404, body: JSON.stringify({ error: "No pending request from that user" }) };
    }

    if (action === "accept") {
      const acceptedAt = new Date().toISOString();
      const requestedAt = incoming.Item.requestedAt ?? null;

      await dynamodb.send(
        new PutCommand({
          TableName: "Friends",
          Item: { userId: requesterId, otherUserId: responderId, status: "ACCEPTED", requestedAt, acceptedAt }
        })
      );
      await dynamodb.send(
        new PutCommand({
          TableName: "Friends",
          Item: { userId: responderId, otherUserId: requesterId, status: "ACCEPTED", requestedAt, acceptedAt }
        })
      );

      return { statusCode: 200, body: JSON.stringify({ status: "ACCEPTED" }) };
    }

    // reject: remove both rows
    await dynamodb.send(
      new DeleteCommand({ TableName: "Friends", Key: { userId: requesterId, otherUserId: responderId } })
    );
    await dynamodb.send(
      new DeleteCommand({ TableName: "Friends", Key: { userId: responderId, otherUserId: requesterId } })
    );

    return { statusCode: 200, body: JSON.stringify({ status: "REJECTED" }) };
  } catch (error) {
    console.error("Error responding to friend request:", error);
    return { statusCode: 500, body: JSON.stringify({ error: error.message }) };
  }
};
