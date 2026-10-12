#!/usr/bin/env bash
# Audit the ThatWay AWS backend (read-only), or create the proximity ("Find a friend") pieces.
#
#   backend/scripts/aws.sh audit                  read-only: what exists, what is missing, why email may not arrive
#   backend/scripts/aws.sh nearby                 DRY RUN: prints what it would create
#   backend/scripts/aws.sh nearby --apply         creates the NearbyOffers table, IAM policy, nearby Lambda, 3 routes, deploys Dev
#   backend/scripts/aws.sh trace                  DRY RUN for the friend-tracing backend (consent flow + positions)
#   backend/scripts/aws.sh trace --apply          creates the TraceSessions table, IAM policy, trace Lambda, 5 routes
#   backend/scripts/aws.sh friends [--apply]      DRY RUN / deploy the rewritten friends code into the five existing functions
#   backend/scripts/aws.sh url                    prints the invoke URL to paste into ThatWay/Config.swift
#
# Needs the AWS CLI signed in to the account (aws login, or aws sso login, or a profile): set AWS_PROFILE if you use one.
# It never prints tokens, secrets or user emails/usernames: only counts, names of AWS resources and settings.
# Nothing is deleted. Re-running is safe: every step checks first.
# Cost: NearbyOffers is PROVISIONED at 5 RCU / 5 WCU and TraceSessions at 10 / 10: 15 of DynamoDB's always-free 25 / 25 in
# total, so they can throttle under load but never bill. Switch to on-demand (aws dynamodb update-table --billing-mode
# PAY_PER_REQUEST) when real users arrive.
set -uo pipefail

REGION="${AWS_REGION:-ap-southeast-2}"
API_NAME="${API_NAME:-ThatWay-api}"
STAGE="${STAGE:-Dev}"
ROLE_NAME="${ROLE_NAME:-thatway-lambda-role}"
POOL_ID="${POOL_ID:-ap-southeast-2_I6w74AQkj}"
FN="nearby"
TABLE="NearbyOffers"
HERE="$(cd "$(dirname "$0")" && pwd)"
LAMBDA_DIR="$HERE/../lambda/nearby"
export AWS_PAGER=""

MODE="${1:-audit}"; APPLY=0; [ "${2:-}" = "--apply" ] && APPLY=1
ok()   { echo "ok      $*"; }
miss() { echo "MISSING $*"; }
info() { echo "        $*"; }
run()  { if [ "$APPLY" = 1 ]; then echo "+ $*"; "$@"; else echo "would: $*"; fi; }

command -v aws >/dev/null || { echo "The AWS CLI is not installed (brew install awscli), then sign in: aws login"; exit 2; }
ACCT=$(aws sts get-caller-identity --query Account --output text 2>/dev/null) || { echo "Not signed in to AWS. Run: aws login   (or aws sso login)"; exit 2; }
echo "Account ${ACCT}, region ${REGION}"

api_id() { aws apigatewayv2 get-apis --region "$REGION" --query "Items[?Name=='$API_NAME'].ApiId | [0]" --output text 2>/dev/null | grep -v '^None$'; }

audit() {
  echo; echo "== Cognito user pool"
  if aws cognito-idp describe-user-pool --region "$REGION" --user-pool-id "$POOL_ID" \
       --query 'UserPool.{status:Status,emailSending:EmailConfiguration.EmailSendingAccount,from:EmailConfiguration.From,sourceArn:EmailConfiguration.SourceArn,autoVerified:AutoVerifiedAttributes,verification:VerificationMessageTemplate.DefaultEmailOption,mfa:MfaConfiguration,postConfirmation:LambdaConfig.PostConfirmation}' \
       --output table 2>/tmp/tw_aws_err; then ok "pool reachable"; else miss "cannot describe the pool: $(head -c 200 /tmp/tw_aws_err)"; fi
  echo "   Reading the table: emailSending COGNITO_DEFAULT means the 50-a-day cap and the verificationemail.com sender;"
  echo "   DEVELOPER means SES. autoVerified must contain email. verification must be CONFIRM_WITH_CODE. postConfirmation should be the postConfirmation Lambda."
  local unconfirmed total
  total=$(aws cognito-idp list-users --region "$REGION" --user-pool-id "$POOL_ID" --query 'length(Users)' --output text 2>/dev/null)
  unconfirmed=$(aws cognito-idp list-users --region "$REGION" --user-pool-id "$POOL_ID" --query "length(Users[?UserStatus=='UNCONFIRMED'])" --output text 2>/dev/null)
  echo "   users: ${total:-?} total, ${unconfirmed:-?} unconfirmed (counts only)"
  [ "${unconfirmed:-0}" != "0" ] && info "Unconfirmed users mean sign-up reached AWS and only the email is missing: see SETUP.md section 13."

  echo; echo "== SES (email)"
  aws sesv2 get-account --region "$REGION" --query '{production:ProductionAccessEnabled,sendingEnabled:SendingEnabled,sent24h:SendQuota.SentLast24Hours,max24h:SendQuota.Max24HourSend}' --output table 2>/dev/null \
    || info "SES not readable (fine if the pool uses Cognito's default sender)"

  echo; echo "== DynamoDB tables"
  for t in Users Friends "$TABLE" TraceSessions; do
    if aws dynamodb describe-table --region "$REGION" --table-name "$t" >/dev/null 2>&1; then ok "table $t"; else miss "table $t"; fi
  done
  aws dynamodb describe-time-to-live --region "$REGION" --table-name "$TABLE" --query 'TimeToLiveDescription.TimeToLiveStatus' --output text 2>/dev/null | sed 's/^/        TTL on NearbyOffers: /'

  echo; echo "== Lambda functions"
  for f in postConfirmation friendsSearch friendsRequest friendsRespond friendsList friendsRemove "$FN" trace; do
    rt=$(aws lambda get-function-configuration --region "$REGION" --function-name "$f" --query Runtime --output text 2>/dev/null) \
      && ok "function $f ($rt)" || miss "function $f"
  done

  echo; echo "== API Gateway"
  local api; api=$(api_id)
  if [ -z "$api" ]; then miss "HTTP API named $API_NAME"; return; fi
  ok "API $API_NAME id $api"
  echo "        Invoke URL for Config.swift: https://${api}.execute-api.${REGION}.amazonaws.com/${STAGE}"
  aws apigatewayv2 get-stage --region "$REGION" --api-id "$api" --stage-name "$STAGE" >/dev/null 2>&1 && ok "stage $STAGE" || miss "stage $STAGE (the URL needs /$STAGE)"
  local auth; auth=$(aws apigatewayv2 get-authorizers --region "$REGION" --api-id "$api" --query "Items[0].AuthorizerId" --output text 2>/dev/null)
  [ -n "$auth" ] && [ "$auth" != "None" ] && ok "JWT authorizer ($auth)" || miss "JWT authorizer"
  aws apigatewayv2 get-authorizers --region "$REGION" --api-id "$api" \
    --query 'Items[0].{identitySource:IdentitySource[0],issuer:JwtConfiguration.Issuer,audience:JwtConfiguration.Audience[0]}' --output table 2>/dev/null
  echo "   The audience must equal the app client id 2ute5p0mqgufhech5u59sn1is7 and the issuer must end with $POOL_ID."
  local routes; routes=$(aws apigatewayv2 get-routes --region "$REGION" --api-id "$api" --query 'Items[].RouteKey' --output text 2>/dev/null)
  for r in "GET /friends" "GET /friends/search" "POST /friends/request" "POST /friends/respond" "DELETE /friends/{friendID}" \
           "PUT /nearby/offers" "GET /nearby/offers" "DELETE /nearby/offers/{friendId}" \
           "POST /trace/request" "GET /trace" "POST /trace/respond" "PUT /trace/position" "DELETE /trace/{friendId}"; do
    echo "$routes" | tr '\t' '\n' | grep -Fxq "$r" && ok "route $r" || miss "route $r"
  done
}

# provision <function> <table> <pk> <sk> <rcu> <wcu> <policy-name> <extra-dynamo-resource-or-empty> <route>...
provision() {
  local fn="$1" table="$2" pk="$3" sk="$4" rcu="$5" wcu="$6" policy="$7" extra="$8"; shift 8
  local api; api=$(api_id)
  [ -z "$api" ] && { echo "No HTTP API named $API_NAME found: build it first (SETUP.md section 6)."; exit 1; }
  local role_arn; role_arn=$(aws iam get-role --role-name "$ROLE_NAME" --query Role.Arn --output text 2>/dev/null)
  [ -z "$role_arn" ] && { echo "IAM role $ROLE_NAME not found (SETUP.md section 3)."; exit 1; }
  local auth; auth=$(aws apigatewayv2 get-authorizers --region "$REGION" --api-id "$api" --query "Items[0].AuthorizerId" --output text)
  if [ -z "$auth" ] || [ "$auth" = "None" ]; then echo "No JWT authorizer on $API_NAME (SETUP.md section 6)."; exit 1; fi
  [ "$APPLY" = 1 ] || echo "DRY RUN: nothing is created. Add --apply to do it."
  echo "API $api, role $role_arn, authorizer $auth"

  echo; echo "== 1. DynamoDB table $table (provisioned $rcu/$wcu, always-free; TTL on expiresAt)"
  if aws dynamodb describe-table --region "$REGION" --table-name "$table" >/dev/null 2>&1; then ok "exists"; else
    run aws dynamodb create-table --region "$REGION" --table-name "$table" \
      --attribute-definitions "AttributeName=$pk,AttributeType=S" "AttributeName=$sk,AttributeType=S" \
      --key-schema "AttributeName=$pk,KeyType=HASH" "AttributeName=$sk,KeyType=RANGE" \
      --billing-mode PROVISIONED --provisioned-throughput "ReadCapacityUnits=$rcu,WriteCapacityUnits=$wcu"
    [ "$APPLY" = 1 ] && aws dynamodb wait table-exists --region "$REGION" --table-name "$table"
  fi
  local ttl; ttl=$(aws dynamodb describe-time-to-live --region "$REGION" --table-name "$table" --query TimeToLiveDescription.TimeToLiveStatus --output text 2>/dev/null)
  if [ "$ttl" = "ENABLED" ] || [ "$ttl" = "ENABLING" ]; then ok "TTL on expiresAt already $ttl"; else
    run aws dynamodb update-time-to-live --region "$REGION" --table-name "$table" --time-to-live-specification "Enabled=true,AttributeName=expiresAt"
  fi

  echo; echo "== 2. IAM: an extra inline policy on $ROLE_NAME (the existing policies are not touched)"
  local pol; pol=$(mktemp)
  local resources="\"arn:aws:dynamodb:${REGION}:${ACCT}:table/${table}\""
  [ -n "$extra" ] && resources="$resources,\"arn:aws:dynamodb:${REGION}:${ACCT}:table/${extra}\""
  cat > "$pol" <<JSON
{"Version":"2012-10-17","Statement":[{"Sid":"ThatWay${fn}Access","Effect":"Allow",
 "Action":["dynamodb:GetItem","dynamodb:PutItem","dynamodb:Query","dynamodb:DeleteItem"],
 "Resource":[${resources}]}]}
JSON
  run aws iam put-role-policy --role-name "$ROLE_NAME" --policy-name "$policy" --policy-document "file://$pol"

  echo; echo "== 3. Lambda $fn (index.mjs + core.mjs)"
  local zip="/tmp/${fn}.zip"; rm -f "$zip"; (cd "$HERE/../lambda/$fn" && zip -q "$zip" index.mjs core.mjs)
  if aws lambda get-function --region "$REGION" --function-name "$fn" >/dev/null 2>&1; then
    run aws lambda update-function-code --region "$REGION" --function-name "$fn" --zip-file "fileb://$zip"
  else
    run aws lambda create-function --region "$REGION" --function-name "$fn" --runtime nodejs24.x --handler index.handler \
      --role "$role_arn" --timeout 10 --memory-size 128 --zip-file "fileb://$zip"
    [ "$APPLY" = 1 ] && aws lambda wait function-active-v2 --region "$REGION" --function-name "$fn"
  fi
  run aws lambda add-permission --region "$REGION" --function-name "$fn" --statement-id "apigw-${fn}" \
    --action lambda:InvokeFunction --principal apigateway.amazonaws.com \
    --source-arn "arn:aws:execute-api:${REGION}:${ACCT}:${api}/*/*/${fn}*" 2>/dev/null || true

  echo; echo "== 4. Routes (same API, same authorizer)"
  local fn_arn="arn:aws:lambda:${REGION}:${ACCT}:function:${fn}"
  local integ; integ=$(aws apigatewayv2 get-integrations --region "$REGION" --api-id "$api" \
      --query "Items[?IntegrationUri=='$fn_arn'].IntegrationId | [0]" --output text 2>/dev/null)
  if [ -z "$integ" ] || [ "$integ" = "None" ]; then
    if [ "$APPLY" = 1 ]; then
      integ=$(aws apigatewayv2 create-integration --region "$REGION" --api-id "$api" --integration-type AWS_PROXY \
        --integration-uri "$fn_arn" --payload-format-version 2.0 --query IntegrationId --output text)
      echo "+ created integration $integ"
    else echo "would: create the Lambda integration"; integ="<new>"; fi
  else ok "integration $integ"; fi
  local routes; routes=$(aws apigatewayv2 get-routes --region "$REGION" --api-id "$api" --query 'Items[].RouteKey' --output text)
  for r in "$@"; do
    if echo "$routes" | tr '\t' '\n' | grep -Fxq "$r"; then ok "route $r"; else
      run aws apigatewayv2 create-route --region "$REGION" --api-id "$api" --route-key "$r" \
        --target "integrations/$integ" --authorization-type JWT --authorizer-id "$auth"
    fi
  done

  echo; echo "== 5. Deploy stage $STAGE"
  local auto; auto=$(aws apigatewayv2 get-stage --region "$REGION" --api-id "$api" --stage-name "$STAGE" --query AutoDeploy --output text 2>/dev/null)
  if [ "$auto" = "True" ] || [ "$auto" = "true" ]; then ok "stage $STAGE has auto-deploy: the routes are already live"; else
    run aws apigatewayv2 create-deployment --region "$REGION" --api-id "$api" --stage-name "$STAGE"
  fi
  echo; echo "Invoke URL: https://${api}.execute-api.${REGION}.amazonaws.com/${STAGE}"
}

provision_nearby() {
  provision nearby NearbyOffers userId fromUserId 5 5 thatway-nearby-access "" \
    "PUT /nearby/offers" "GET /nearby/offers" "DELETE /nearby/offers/{friendId}"
}

provision_trace() {
  provision trace TraceSessions userId peerId 10 10 thatway-trace-access "" \
    "POST /trace/request" "GET /trace" "POST /trace/respond" "PUT /trace/position" "DELETE /trace/{friendId}"
}

deploy_friends() {
  "$HERE/sync_friends.sh" --check >/dev/null || { echo "The friends copies have drifted: run backend/scripts/sync_friends.sh"; exit 1; }
  [ "$APPLY" = 1 ] || echo "DRY RUN: nothing is changed. Add --apply to do it."
  for fn in friendsSearch friendsRequest friendsRespond friendsList friendsRemove; do
    if ! aws lambda get-function --region "$REGION" --function-name "$fn" >/dev/null 2>&1; then miss "function $fn"; continue; fi
    local zip="/tmp/${fn}.zip"; rm -f "$zip"; (cd "$HERE/../lambda/$fn" && zip -q "$zip" index.mjs core.mjs)
    run aws lambda update-function-code --region "$REGION" --function-name "$fn" --zip-file "fileb://$zip"
  done
  [ "$APPLY" = 1 ] && echo "Next: backend/scripts/friends_integration.sh"
}

case "$MODE" in
  audit) audit ;;
  nearby) provision_nearby ;;
  trace) provision_trace ;;
  friends) deploy_friends ;;
  url) a=$(api_id); [ -n "$a" ] && echo "https://${a}.execute-api.${REGION}.amazonaws.com/${STAGE}" || { echo "no API named $API_NAME"; exit 1; } ;;
  *) echo "usage: aws.sh audit | nearby [--apply] | trace [--apply] | friends [--apply] | url"; exit 2 ;;
esac
