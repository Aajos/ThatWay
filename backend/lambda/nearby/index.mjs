import { DynamoDBClient } from "@aws-sdk/client-dynamodb";
import { DynamoDBDocumentClient, GetCommand, PutCommand, QueryCommand, DeleteCommand } from "@aws-sdk/lib-dynamodb";
import { makeHandler } from "./core.mjs";

const dynamodb = DynamoDBDocumentClient.from(new DynamoDBClient({ region: "ap-southeast-2" }));

const db = {
  get: async (TableName, Key) => (await dynamodb.send(new GetCommand({ TableName, Key }))).Item,
  put: (TableName, Item) => dynamodb.send(new PutCommand({ TableName, Item })),
  query: async (TableName, userId) =>
    (await dynamodb.send(new QueryCommand({
      TableName, KeyConditionExpression: "userId = :u", ExpressionAttributeValues: { ":u": userId },
    }))).Items ?? [],
  remove: (TableName, Key) => dynamodb.send(new DeleteCommand({ TableName, Key })),
};

export const handler = makeHandler({ db });
