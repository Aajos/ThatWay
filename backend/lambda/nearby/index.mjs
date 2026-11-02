import { DynamoDBClient } from "@aws-sdk/client-dynamodb";
import { DynamoDBDocumentClient, GetCommand, PutCommand, QueryCommand, DeleteCommand } from "@aws-sdk/lib-dynamodb";
import { makeHandler } from "./core.mjs";

const dynamodb = DynamoDBDocumentClient.from(new DynamoDBClient({ region: "ap-southeast-2" }));

const db = {
  // Token rows can be read eventually consistently (a poll that is a second stale is fine), but who is allowed to range with whom
  // (friends, blocks, trace permissions) is a safety decision: those are always read consistently.
  get: async (TableName, Key) => (await dynamodb.send(new GetCommand({ TableName, Key, ConsistentRead: TableName !== "NearbyOffers" }))).Item,
  put: (TableName, Item) => dynamodb.send(new PutCommand({ TableName, Item })),
  query: async (TableName, userId) =>
    (await dynamodb.send(new QueryCommand({
      TableName, ConsistentRead: false, KeyConditionExpression: "userId = :u", ExpressionAttributeValues: { ":u": userId },
    }))).Items ?? [],
  remove: (TableName, Key) => dynamodb.send(new DeleteCommand({ TableName, Key })),
};

// The tracer's plan, from the server's own record. Off (never expires) until purchases are verified: set PLAN_CHECK=on then.
const planUntil = async (userId) => {
  if (process.env.PLAN_CHECK !== "on") return Infinity;
  return (await db.get("Entitlements", { userId }))?.planUntil ?? null;
};

export const handler = makeHandler({ db, planUntil });
