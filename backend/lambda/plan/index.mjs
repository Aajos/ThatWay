import { DynamoDBClient } from "@aws-sdk/client-dynamodb";
import { DynamoDBDocumentClient, GetCommand, PutCommand } from "@aws-sdk/lib-dynamodb";
import { makeHandler } from "./core.mjs";
import { verifyAppleJws } from "./appleJws.mjs";

const dynamodb = DynamoDBDocumentClient.from(new DynamoDBClient({ region: "ap-southeast-2" }));
const db = {
  get: async (TableName, Key) => (await dynamodb.send(new GetCommand({ TableName, Key, ConsistentRead: true }))).Item,
  put: (TableName, Item) => dynamodb.send(new PutCommand({ TableName, Item })),
};

// Sandbox purchases (TestFlight, App Review) are accepted until the app is live: set ALLOW_SANDBOX=off to refuse them.
export const handler = makeHandler({ db, verify: async (jws) => verifyAppleJws(jws), allowSandbox: process.env.ALLOW_SANDBOX !== "off" });
