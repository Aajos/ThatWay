import { DynamoDBClient } from "@aws-sdk/client-dynamodb";
import { DynamoDBDocumentClient, PutCommand, GetCommand } from "@aws-sdk/lib-dynamodb";

const client = new DynamoDBClient({ region: "ap-southeast-2" });
const dynamodb = DynamoDBDocumentClient.from(client);

const EXISTING_MESSAGES = {
  ACCEPTED: "You are already friends",
  PENDING: "Request already sent",
  INCOMING: "They already sent you a request, accept it instead"
};

export const handler = async (event) => {
  try {
    const userId = event.requestContext.authorizer.jwt.claims.sub;
    const { friendId } = JSON.parse(event.body || "{}");

    if (!friendId) {
      return { statusCode: 400, body: JSON.stringify({ error: "friendId required" }) };
    }
    if (friendId === userId) {
      return { statusCode: 400, body: JSON.stringify({ error: "You can't add yourself" }) };
    }

    const target = await dynamodb.send(
      new GetCommand({ TableName: "Users", Key: { id: friendId } })
    );
    if (!target.Item) {
      return { statusCode: 404, body: JSON.stringify({ error: "User not found" }) };
    }

    const existing = await dynamodb.send(
      new GetCommand({ TableName: "Friends", Key: { userId, otherUserId: friendId } })
    );
    if (existing.Item) {
      const s = existing.Item.status;
      return {
        statusCode: 409,
        body: JSON.stringify({ error: EXISTING_MESSAGES[s] || "Relationship already exists", status: s })
      };
    }

    const requestedAt = new Date().toISOString();

    await dynamodb.send(
      new PutCommand({
        TableName: "Friends",
        Item: { userId, otherUserId: friendId, status: "PENDING", requestedAt }
      })
    );
    await dynamodb.send(
      new PutCommand({
        TableName: "Friends",
        Item: { userId: friendId, otherUserId: userId, status: "INCOMING", requestedAt }
      })
    );

    return { statusCode: 201, body: JSON.stringify({ status: "PENDING", requestedAt }) };
  } catch (error) {
    console.error("Error sending friend request:", error);
    return { statusCode: 500, body: JSON.stringify({ error: error.message }) };
  }
};
