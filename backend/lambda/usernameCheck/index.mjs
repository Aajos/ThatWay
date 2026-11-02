import { DynamoDBClient } from "@aws-sdk/client-dynamodb";
import { DynamoDBDocumentClient, QueryCommand } from "@aws-sdk/lib-dynamodb";
import { makeHandler } from "./core.mjs";

const dynamodb = DynamoDBDocumentClient.from(new DynamoDBClient({ region: "ap-southeast-2" }));

const db = {
  queryIndex: async (TableName, IndexName, attr, value) =>
    (await dynamodb.send(new QueryCommand({
      TableName, IndexName, Limit: 1, KeyConditionExpression: "#a = :v",
      ExpressionAttributeNames: { "#a": attr }, ExpressionAttributeValues: { ":v": value },
    }))).Items ?? [],
};

export const handler = makeHandler({ db });
