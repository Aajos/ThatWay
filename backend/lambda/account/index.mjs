import { DynamoDBClient } from "@aws-sdk/client-dynamodb";
import { DynamoDBDocumentClient, GetCommand, PutCommand, QueryCommand, DeleteCommand, ScanCommand, TransactWriteCommand } from "@aws-sdk/lib-dynamodb";
import { CognitoIdentityProviderClient, AdminDeleteUserCommand } from "@aws-sdk/client-cognito-identity-provider";
import { makeHandler } from "./core.mjs";

const dynamodb = DynamoDBDocumentClient.from(new DynamoDBClient({ region: "ap-southeast-2" }));
const cognito = new CognitoIdentityProviderClient({ region: "ap-southeast-2" });
const POOL_ID = process.env.POOL_ID ?? "ap-southeast-2_I6w74AQkj";
const partitionKey = { Users: "id", Grants: "traceeId", Blocks: "blockerId" };       // every other table partitions on userId
const pk = (table) => partitionKey[table] ?? "userId";

const db = {
  get: async (TableName, Key) => (await dynamodb.send(new GetCommand({ TableName, Key, ConsistentRead: true }))).Item,
  put: (TableName, Item) => dynamodb.send(new PutCommand({ TableName, Item })),
  remove: (TableName, Key) => dynamodb.send(new DeleteCommand({ TableName, Key })),
  query: async (TableName, value) => {
    const items = []; let ExclusiveStartKey;
    do {
      const page = await dynamodb.send(new QueryCommand({
        TableName, ConsistentRead: true, ExclusiveStartKey, KeyConditionExpression: "#p = :v",
        ExpressionAttributeNames: { "#p": pk(TableName) }, ExpressionAttributeValues: { ":v": value },
      }));
      items.push(...(page.Items ?? [])); ExclusiveStartKey = page.LastEvaluatedKey;
    } while (ExclusiveStartKey);
    return items;
  },
  queryIndex: async (TableName, IndexName, attr, value) => {
    const items = []; let ExclusiveStartKey;
    do {
      const page = await dynamodb.send(new QueryCommand({
        TableName, IndexName, ExclusiveStartKey, KeyConditionExpression: "#a = :v", ExpressionAttributeNames: { "#a": attr }, ExpressionAttributeValues: { ":v": value },
      }));
      items.push(...(page.Items ?? [])); ExclusiveStartKey = page.LastEvaluatedKey;
    } while (ExclusiveStartKey);
    return items;
  },
  scan: async (TableName) => {
    const items = []; let ExclusiveStartKey;
    do {
      const page = await dynamodb.send(new ScanCommand({ TableName, ExclusiveStartKey }));
      items.push(...(page.Items ?? [])); ExclusiveStartKey = page.LastEvaluatedKey;
    } while (ExclusiveStartKey);
    return items;
  },
  transact: (ops) => dynamodb.send(new TransactWriteCommand({ TransactItems: ops.map((op) => ({ Delete: { TableName: op.remove.table, Key: op.remove.key } })) })),
};

const auth = {
  deleteUser: async (Username) => {
    try { await cognito.send(new AdminDeleteUserCommand({ UserPoolId: POOL_ID, Username })); }
    catch (error) { if (error?.name !== "UserNotFoundException") throw error; }        // already gone is fine: the delete can be repeated
  },
};

export const handler = makeHandler({ db, auth });
