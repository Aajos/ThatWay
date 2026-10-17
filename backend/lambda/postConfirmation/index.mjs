import { DynamoDBClient } from "@aws-sdk/client-dynamodb";
import { DynamoDBDocumentClient, PutCommand } from "@aws-sdk/lib-dynamodb";

const client = new DynamoDBClient({ region: "ap-southeast-2" });
const dynamodb = DynamoDBDocumentClient.from(client);

export const handler = async (event) => {
  try {
    await dynamodb.send(
      new PutCommand({
        TableName: "Users",
        Item: {
          id: event.request.userAttributes.sub,
          username: event.userName,
          email: event.request.userAttributes.email,
          createdAt: new Date().toISOString()
        }
      })
    );
    return event;
  } catch (error) {
    console.error("Error creating user:", error);
    throw error;
  }
};
