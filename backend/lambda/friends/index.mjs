import { DynamoDBClient } from "@aws-sdk/client-dynamodb";
import { DynamoDBDocumentClient, GetCommand, QueryCommand, TransactWriteCommand } from "@aws-sdk/lib-dynamodb";
import { makeHandler } from "./core.mjs";

const dynamodb = DynamoDBDocumentClient.from(new DynamoDBClient({ region: "ap-southeast-2" }));

const db = {
  get: async (TableName, Key) => (await dynamodb.send(new GetCommand({ TableName, Key, ConsistentRead: false }))).Item,
  query: async (TableName, userId) =>
    (await dynamodb.send(new QueryCommand({
      TableName, ConsistentRead: false, KeyConditionExpression: "userId = :u", ExpressionAttributeValues: { ":u": userId },
    }))).Items ?? [],
  queryIndex: async (TableName, IndexName, attr, value) =>
    (await dynamodb.send(new QueryCommand({
      TableName, IndexName, KeyConditionExpression: "#a = :v", ExpressionAttributeNames: { "#a": attr }, ExpressionAttributeValues: { ":v": value },
    }))).Items ?? [],
  transact: (ops) =>
    dynamodb.send(new TransactWriteCommand({
      TransactItems: ops.map((op) =>
        op.put
          ? { Put: { TableName: op.put.table, Item: op.put.item,
                     ...(op.put.absentKey ? { ConditionExpression: `attribute_not_exists(${op.put.absentKey[0]})` } : {}) } }
          : { Delete: { TableName: op.remove.table, Key: op.remove.key } }),
    })),
};

export const handler = makeHandler({ db });
