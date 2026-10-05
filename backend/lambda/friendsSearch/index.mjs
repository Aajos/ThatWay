import { DynamoDBClient } from "@aws-sdk/client-dynamodb";
import { DynamoDBDocumentClient, QueryCommand } from "@aws-sdk/lib-dynamodb";

const client = new DynamoDBClient({ region: "ap-southeast-2" });
const dynamodb = DynamoDBDocumentClient.from(client);

export const handler = async (event) => {
  const username = event.queryStringParameters?.username;

  if (!username) {
    return { statusCode: 400, body: JSON.stringify({ error: "Username required" }) };
  }

  try {
    const result = await dynamodb.send(
      new QueryCommand({
        TableName: "Users",
        IndexName: "byUsername",
        KeyConditionExpression: "username = :username",
        ExpressionAttributeValues: { ":username": username }
      })
    );

    const users = (result.Items || []).map((item) => ({
      id: item.id,
      username: item.username,
      email: item.email
    }));

    return { statusCode: 200, body: JSON.stringify(users) };
  } catch (error) {
    console.error("Error searching users:", error);
    return { statusCode: 500, body: JSON.stringify({ error: error.message }) };
  }
};
