import { DynamoDBClient } from "@aws-sdk/client-dynamodb";
import { DynamoDBDocumentClient, DeleteCommand } from "@aws-sdk/lib-dynamodb";

const client = new DynamoDBClient({ region: "ap-southeast-2" });
const dynamodb = DynamoDBDocumentClient.from(client);

export const handler = async (event) => {
  try {
    const userId = event.requestContext.authorizer.jwt.claims.sub;
    const friendId = event.pathParameters?.friendID ?? event.pathParameters?.friendId;

    if (!friendId) {
      return { statusCode: 400, body: JSON.stringify({ error: "friendId required" }) };
    }

    await dynamodb.send(
      new DeleteCommand({ TableName: "Friends", Key: { userId, otherUserId: friendId } })
    );
    await dynamodb.send(
      new DeleteCommand({ TableName: "Friends", Key: { userId: friendId, otherUserId: userId } })
    );

    return { statusCode: 200, body: JSON.stringify({ message: "Friend removed" }) };
  } catch (error) {
    console.error("Error removing friend:", error);
    return { statusCode: 500, body: JSON.stringify({ error: error.message }) };
  }
};
