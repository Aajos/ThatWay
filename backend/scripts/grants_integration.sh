#!/usr/bin/env bash
# End-to-end test of trace permissions, blocking, reports and account deletion against the REAL deployed API, with throwaway
# accounts. It creates three Cognito users (zz_itest_a/b/c, random passwords that are never printed), signs them in, drives the
# real HTTPS routes with their access tokens, checks the tables directly, and deletes everything it made (also on failure).
# It touches no real user, prints no tokens, emails or positions.
#   backend/scripts/grants_integration.sh
set -uo pipefail
REGION="${AWS_REGION:-ap-southeast-2}"
POOL="${POOL_ID:-ap-southeast-2_I6w74AQkj}"
CLIENT="${CLIENT_ID:-2ute5p0mqgufhech5u59sn1is7}"
export AWS_PAGER=""
API="$("$(dirname "$0")/aws.sh" url | tail -1)"
N=(a b c)
# (macOS ships bash 3.2: no associative arrays, so SUB_a, TOK_a... are plain variables read with ${!var})
sub() { local v="SUB_$1"; echo "${!v:-}"; }
tok() { local v="TOK_$1"; echo "${!v:-}"; }
fail=0
ok()   { echo "ok    $1"; }
bad()  { echo "FAIL  $1"; fail=1; }
check(){ if [ "$2" = "$3" ]; then ok "$1"; else bad "$1 (expected $3, got $2)"; fi; }
PW="Aa1!$(LC_ALL=C tr -dc 'A-Za-z0-9' </dev/urandom | head -c 18)"

cleanup() {
  for x in "${N[@]}"; do
    aws cognito-idp admin-delete-user --region "$REGION" --user-pool-id "$POOL" --username "zz_itest_$x" >/dev/null 2>&1
    id="$(sub $x)"
    [ -z "$id" ] && continue
    aws dynamodb delete-item --region "$REGION" --table-name Users --key "{\"id\":{\"S\":\"$id\"}}" >/dev/null 2>&1
    aws dynamodb delete-item --region "$REGION" --table-name Positions --key "{\"userId\":{\"S\":\"$id\"}}" >/dev/null 2>&1
    aws dynamodb delete-item --region "$REGION" --table-name Devices --key "{\"userId\":{\"S\":\"$id\"},\"token\":{\"S\":\"$(printf 'ab%.0s' $(seq 32))\"}}" >/dev/null 2>&1
    aws dynamodb delete-item --region "$REGION" --table-name Entitlements --key "{\"userId\":{\"S\":\"$id\"}}" >/dev/null 2>&1
    for y in "${N[@]}"; do
      o="$(sub $y)"; [ -z "$o" ] && continue
      aws dynamodb delete-item --region "$REGION" --table-name Friends --key "{\"userId\":{\"S\":\"$id\"},\"otherUserId\":{\"S\":\"$o\"}}" >/dev/null 2>&1
      aws dynamodb delete-item --region "$REGION" --table-name Grants --key "{\"traceeId\":{\"S\":\"$id\"},\"tracerId\":{\"S\":\"$o\"}}" >/dev/null 2>&1
      aws dynamodb delete-item --region "$REGION" --table-name Blocks --key "{\"blockerId\":{\"S\":\"$id\"},\"blockedId\":{\"S\":\"$o\"}}" >/dev/null 2>&1
    done
  done
  # reports made by the throwaway users (their reporterId is their Cognito sub)
  for x in "${N[@]}"; do
    id="$(sub $x)"; [ -z "$id" ] && continue
    for rid in $(aws dynamodb scan --region "$REGION" --table-name Reports --filter-expression "reporterId = :r" --expression-attribute-values "{\":r\":{\"S\":\"$id\"}}" --query 'Items[].reportId.S' --output text 2>/dev/null); do
      [ "$rid" = "None" ] && continue
      aws dynamodb delete-item --region "$REGION" --table-name Reports --key "{\"reportId\":{\"S\":\"$rid\"}}" >/dev/null 2>&1
    done
  done
}
trap cleanup EXIT
cleanup

for x in "${N[@]}"; do
  name="zz_itest_$x"
  aws cognito-idp admin-create-user --region "$REGION" --user-pool-id "$POOL" --username "$name" \
    --user-attributes "Name=email,Value=itest-$x@example.com" "Name=email_verified,Value=true" --message-action SUPPRESS >/dev/null 2>&1 || { echo "cannot create test users"; exit 2; }
  aws cognito-idp admin-set-user-password --region "$REGION" --user-pool-id "$POOL" --username "$name" --password "$PW" --permanent >/dev/null 2>&1 || { echo "cannot set password"; exit 2; }
  s_=$(aws cognito-idp admin-get-user --region "$REGION" --user-pool-id "$POOL" --username "$name" --query "UserAttributes[?Name=='sub'].Value | [0]" --output text)
  printf -v "SUB_$x" '%s' "$s_"
  t_=$(aws cognito-idp initiate-auth --region "$REGION" --client-id "$CLIENT" --auth-flow USER_PASSWORD_AUTH --auth-parameters "USERNAME=$name,PASSWORD=$PW" --query AuthenticationResult.AccessToken --output text 2>/dev/null)
  { [ -z "$t_" ] || [ "$t_" = "None" ]; } && { echo "cannot sign in a test user (is USER_PASSWORD_AUTH enabled?)"; exit 2; }
  printf -v "TOK_$x" '%s' "$t_"
  aws dynamodb put-item --region "$REGION" --table-name Users --item "{\"id\":{\"S\":\"$s_\"},\"username\":{\"S\":\"$name\"},\"createdAt\":{\"S\":\"itest\"}}" >/dev/null || { echo "cannot write Users"; exit 2; }
done
A=$(sub a); B=$(sub b); C=$(sub c)

# api <who> <METHOD> <path> [json]  ->  "<status> <body>"
api() {
  local who="$1" method="$2" path="$3" data="${4:-}"
  local args=(-s -o /tmp/tw_it_body -w '%{http_code}' -X "$method" -H "Authorization: Bearer $(tok $who)" -H "Content-Type: application/json")
  [ -n "$data" ] && args+=(--data "$data")
  local code; code=$(curl "${args[@]}" "$API$path")
  echo "$code $(cat /tmp/tw_it_body)"
}
st() { echo "$1" | cut -d' ' -f1; }
bd() { echo "$1" | cut -d' ' -f2-; }
j()  { python3 -c "import json,sys; d=json.loads(sys.argv[1]); print(eval(sys.argv[2]))" "$(bd "$1")" "$2" 2>/dev/null; }

# ---- befriend a and b through the real friends service
r=$(api a POST /friends/request "{\"friendId\":\"$B\"}"); check "friend request sent" "$(st "$r")" 201
r=$(api b POST /friends/respond "{\"requesterId\":\"$A\",\"action\":\"accept\"}"); check "friend request accepted" "$(st "$r")" 200

# ---- the unauthenticated door is closed
code=$(curl -s -o /dev/null -w '%{http_code}' "$API/grants"); check "no token, no grants" "$code" 401

# ---- tracer asks, tracee grants
r=$(api a POST /grants/request "{\"friendId\":\"$B\",\"kind\":\"window\",\"hours\":2}"); check "a asks b for 2 hours" "$(st "$r")" 200
r=$(api b GET /grants); check "b sees the request" "$(j "$r" "d['asTraced'][0]['status']")" REQUESTED
check "with the length asked for" "$(j "$r" "d['asTraced'][0]['requestedHours']")" 2
r=$(api a GET /grants); check "a is shown it waiting" "$(j "$r" "d['asTracer'][0]['status']")" waiting
r=$(api b POST /grants/respond "{\"tracerId\":\"$A\",\"action\":\"grant\",\"hours\":0.5}"); check "granting without the second confirmation is refused" "$(st "$r")" 400
r=$(api b POST /grants/respond "{\"tracerId\":\"$A\",\"action\":\"grant\",\"hours\":0.5,\"confirmed\":true,\"kind\":\"window\",\"consentVersion\":\"itest\"}"); check "b grants 30 minutes" "$(st "$r")" 200
r=$(api a GET /grants); check "a now sees only 'active'" "$(j "$r" "d['asTracer'][0]['status']")" active
check "and no end time" "$(j "$r" "'until' in d['asTracer'][0]")" False
r=$(api b GET /grants); check "b sees who may trace them and until when" "$(j "$r" "d['asTraced'][0]['tracerId']==\"$A\" and d['asTraced'][0]['until']>0")" True

# ---- positions flow one way
r=$(api a PUT /grants/position '{"lat":-37.8,"lon":145.2}'); check "the tracer's own position is refused" "$(st "$r")" 409
r=$(api b PUT /grants/position '{"lat":-37.8136,"lon":144.9631,"acc":8}'); check "b uploads a position" "$(st "$r")" 200
r=$(api a POST /grants/locate "{\"traceeId\":\"$B\",\"distanceM\":1500}"); check "a locates b" "$(st "$r")" 200
check "and gets a position with its age" "$(j "$r" "d['position']['age']>=0")" True
r=$(api a POST /grants/locate "{\"traceeId\":\"$B\",\"distanceM\":1500}"); check "asking again within 2 minutes is limited" "$(st "$r")" 429
r=$(api c POST /grants/locate "{\"traceeId\":\"$B\",\"distanceM\":10}"); check "a stranger gets the generic answer" "$(st "$r")" 403
check "word for word" "$(j "$r" "d['error']")" "User cannot be traced"
r=$(api b GET /grants); check "b is told someone is still tracing" "$(j "$r" "d['asTraced'][0].get('stillTracing')")" True
check "b sees a band, not a number" "$(j "$r" "d['asTraced'][0]['band']")" "about 2 km"

# ---- push: Apple accepts our credentials (a fake token is refused as a bad token, which removes it; a bad key would keep it)
r=$(api b PUT /devices '{"token":"'"$(printf 'ab%.0s' $(seq 32))"'","environment":"sandbox"}'); check "a phone token is stored" "$(st "$r")" 200
r=$(api b POST /grants/revoke "{\"tracerId\":\"$A\"}")
r=$(api a POST /grants/request "{\"friendId\":\"$B\",\"hours\":1}"); check "a request still succeeds with push on" "$(st "$r")" 200
n=$(aws dynamodb query --region "$REGION" --table-name Devices --key-condition-expression "userId = :u" --expression-attribute-values "{\":u\":{\"S\":\"$B\"}}" --select COUNT --query Count --output text)
check "Apple answered, so the fake token was dropped (credentials are accepted)" "$n" 0

# ---- ending it
r=$(api b POST /grants/revoke "{\"tracerId\":\"$A\"}"); check "b stops it" "$(st "$r")" 200
r=$(api a POST /grants/locate "{\"traceeId\":\"$B\"}"); check "a can no longer locate" "$(st "$r")" 403
pos=$(aws dynamodb get-item --region "$REGION" --table-name Positions --key "{\"userId\":{\"S\":\"$B\"}}" --query 'Item.userId.S' --output text 2>/dev/null)
check "and b's position was dropped" "$pos" None

# ---- blocking looks like silence
r=$(api a POST /grants/request "{\"friendId\":\"$B\",\"kind\":\"oneoff\",\"hours\":1}"); check "a asks again" "$(st "$r")" 200
r=$(api b POST /blocks "{\"userId\":\"$A\"}"); check "b blocks a" "$(st "$r")" 200
r=$(api b GET /blocks); check "b can list the block" "$(j "$r" "d[0]['userId']==\"$A\"")" True
r=$(api a GET /blocks); check "a cannot see it" "$(bd "$r")" "[]"
r=$(api a GET "/friends/search?username=zz_itest_b"); check "a no longer finds b in search" "$(bd "$r")" "[]"
r=$(api a GET "/friends?status=ACCEPTED"); check "and they are no longer friends" "$(bd "$r")" "[]"
r=$(api a POST /grants/request "{\"friendId\":\"$B\",\"kind\":\"window\",\"hours\":1}"); check "a's new request is answered like any other" "$(j "$r" "d['status']")" WAITING
r=$(api a GET /grants); check "and a is shown it waiting" "$(j "$r" "d['asTracer'][0]['status']")" waiting
r=$(api b GET /grants); check "b never sees it" "$(j "$r" "len(d['asTraced'])")" 0
r=$(api b DELETE "/blocks/$A"); check "b unblocks" "$(st "$r")" 200

# ---- reports are accepted and hold no position
r=$(api b POST /reports "{\"userId\":\"$A\",\"category\":\"unwanted_tracing\",\"details\":\"integration test\"}"); check "a report is received" "$(st "$r")" 200
r=$(api b POST /reports "{\"userId\":\"$A\",\"category\":\"nonsense\"}"); check "an unknown category is refused" "$(st "$r")" 400

# ---- plans: nothing is believed unless Apple signed it
r=$(api b GET /plan); check "no purchase, no plan" "$(j "$r" "d['until']")" None
r=$(api b POST /plan/sync '{"transactions":["not.a.signature","eyJhbGciOiJub25lIn0.e30.x"]}'); check "a forged purchase is accepted by the door" "$(st "$r")" 200
check "but counts for nothing" "$(j "$r" "d['until'] is None and not any(x['ok'] for x in d['results'])")" True
code=$(curl -s -o /dev/null -w '%{http_code}' "$API/plan"); check "no token, no plan" "$code" 401

# ---- account: c deletes everything
r=$(api c POST /account/delete '{}'); check "deleting without confirming is refused" "$(st "$r")" 400
r=$(api c GET /account); check "c's account is active" "$(j "$r" "d['status']")" active
r=$(api c POST /account/delete '{"confirmed":true}'); check "c deletes their account" "$(st "$r")" 200
aws cognito-idp admin-get-user --region "$REGION" --user-pool-id "$POOL" --username "zz_itest_c" >/dev/null 2>&1 && bad "c's sign-in still exists" || ok "c's sign-in is gone"
u=$(aws dynamodb get-item --region "$REGION" --table-name Users --key "{\"id\":{\"S\":\"$C\"}}" --query 'Item.id.S' --output text 2>/dev/null); check "and c's profile" "$u" None

echo; [ $fail = 0 ] && echo "ALL OK" || echo "SOME FAILED"; exit $fail
