import { DynamoDBClient } from "@aws-sdk/client-dynamodb";
import { DynamoDBDocumentClient, GetCommand, PutCommand, QueryCommand, DeleteCommand, TransactWriteCommand } from "@aws-sdk/lib-dynamodb";
import { makeHandler, formatReportAlert } from "./core.mjs";
import { SNSClient, PublishCommand } from "@aws-sdk/client-sns";
import { sendPush } from "./push.mjs";

const dynamodb = DynamoDBDocumentClient.from(new DynamoDBClient({ region: "ap-southeast-2" }));
const partitionKey = { Grants: "traceeId", Blocks: "blockerId", Reports: "reportId" };   // every other table partitions on userId
const pk = (table) => partitionKey[table] ?? "userId";

// Consistent reads everywhere: a block or a stop must be seen by the very next request, not a moment later.
const db = {
  get: async (TableName, Key) => (await dynamodb.send(new GetCommand({ TableName, Key, ConsistentRead: true }))).Item,
  put: (TableName, Item) => dynamodb.send(new PutCommand({ TableName, Item })),
  remove: (TableName, Key) => dynamodb.send(new DeleteCommand({ TableName, Key })),
  query: async (TableName, id) =>
    (await dynamodb.send(new QueryCommand({
      TableName, ConsistentRead: true, KeyConditionExpression: "#p = :v", ExpressionAttributeNames: { "#p": pk(TableName) }, ExpressionAttributeValues: { ":v": id },
    }))).Items ?? [],
  queryIndex: async (TableName, IndexName, attr, value) =>
    (await dynamodb.send(new QueryCommand({
      TableName, IndexName, KeyConditionExpression: "#a = :v", ExpressionAttributeNames: { "#a": attr }, ExpressionAttributeValues: { ":v": value },
    }))).Items ?? [],
  transact: (ops) =>
    dynamodb.send(new TransactWriteCommand({
      TransactItems: ops.map((op) => op.put
        ? { Put: { TableName: op.put.table, Item: op.put.item } }
        : { Delete: { TableName: op.remove.table, Key: op.remove.key } }),
    })),
};

// The tracer's plan, as the server's own record (the Entitlements table, written only by the plan function after it has
// verified a purchase with Apple). Until purchases exist the check is OFF so the flow can be tested: set PLAN_CHECK=on in the
// function's environment to switch it on. With it on, a person with no record has no plan.
const planCheckOn = process.env.PLAN_CHECK === "on";
const planUntil = async (userId) => {
  if (!planCheckOn) return Infinity;
  const row = await db.get("Entitlements", { userId });
  return row?.planUntil ?? null;
};

// A push to every phone the person has signed in on. Dead tokens (Apple says gone) are forgotten.
const notify = async (userId, kind, from) => {
  const name = (await db.get("Users", { id: from }))?.username ?? "A friend";
  for (const d of await db.query("Devices", userId)) {
    const result = await sendPush({ deviceToken: d.token, environment: d.environment, kind, name });
    if (result === "gone") await db.remove("Devices", { userId, token: d.token });
  }
};

// A report is emailed to the owner through an SNS topic (REPORT_ALERT_TOPIC_ARN). With no topic set nothing is sent: the report is
// still stored. Usernames are looked up here so the email says who, not just ids.
const sns = new SNSClient({ region: "ap-southeast-2" });
const reportAlert = async (report) => {
  const topic = process.env.REPORT_ALERT_TOPIC_ARN;
  if (!topic) return;
  const reporter = (await db.get("Users", { id: report.reporterId }))?.username;
  const reported = (await db.get("Users", { id: report.reportedId }))?.username;
  const { subject, body } = formatReportAlert(report, { reporter, reported });
  try { await sns.send(new PublishCommand({ TopicArn: topic, Subject: subject, Message: body })); }
  catch (error) { console.error("report alert failed:", error?.name); }       // the name only; the report is already stored
};

export const handler = makeHandler({ db, planUntil, notify, reportAlert });
