#!/usr/bin/env bash
# End-to-end test of the friends backend against the REAL tables and the REAL deployed functions, using two throwaway
# users (ids zz-itest-a / zz-itest-b). It creates their Users rows, runs search -> request -> list -> accept -> list ->
# remove through the actual Lambdas with synthetic API events, checks the Friends table directly after each step, and
# deletes everything it created (also on failure). It touches no real user and prints no emails.
#   backend/scripts/friends_integration.sh
set -uo pipefail
REGION="${AWS_REGION:-ap-southeast-2}"
export AWS_PAGER=""
A="zz-itest-a"; B="zz-itest-b"; UA="zz_itest_a"; UB="zz_itest_b"
fail=0
ok()   { echo "ok    $1"; }
bad()  { echo "FAIL  $1"; fail=1; }
check(){ if [ "$2" = "$3" ]; then ok "$1"; else bad "$1 (expected $3, got $2)"; fi; }

cleanup() {
  for u in $A $B; do
    aws dynamodb delete-item --region "$REGION" --table-name Users --key "{\"id\":{\"S\":\"$u\"}}" >/dev/null 2>&1
    for v in $A $B; do
      aws dynamodb delete-item --region "$REGION" --table-name Friends --key "{\"userId\":{\"S\":\"$u\"},\"otherUserId\":{\"S\":\"$v\"}}" >/dev/null 2>&1
    done
  done
}
trap cleanup EXIT
cleanup   # leftovers from an earlier aborted run

for pair in "$A:$UA" "$B:$UB"; do
  id=${pair%%:*}; name=${pair##*:}
  aws dynamodb put-item --region "$REGION" --table-name Users --item "{\"id\":{\"S\":\"$id\"},\"username\":{\"S\":\"$name\"},\"createdAt\":{\"S\":\"itest\"}}" >/dev/null || { echo "cannot write Users"; exit 2; }
done

# call <function> <routeKey> <sub> <json body or ''> <query json or ''> <path param json or ''>  -> prints "<status> <body>"
call() {
  local fn="$1" route="$2" sub="$3" body="$4" query="$5" pp="$6"
  local ev; ev=$(python3 - "$route" "$sub" "$body" "$query" "$pp" <<'PY'
import json, sys
route, sub, body, query, pp = sys.argv[1:6]
e = {"routeKey": route, "requestContext": {"authorizer": {"jwt": {"claims": {"sub": sub}}}}}
if body: e["body"] = body
if query: e["queryStringParameters"] = json.loads(query)
if pp: e["pathParameters"] = json.loads(pp)
print(json.dumps(e))
PY
)
  local out; out=$(mktemp)
  aws lambda invoke --region "$REGION" --function-name "$fn" --cli-binary-format raw-in-base64-out --payload "$ev" "$out" >/dev/null 2>&1
  python3 - "$out" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
print(d.get("statusCode"), d.get("body", ""))
PY
  rm -f "$out"
}
status() { echo "$1" | cut -d' ' -f1; }
body()   { echo "$1" | cut -d' ' -f2-; }
row() { aws dynamodb get-item --region "$REGION" --table-name Friends --key "{\"userId\":{\"S\":\"$1\"},\"otherUserId\":{\"S\":\"$2\"}}" --query 'Item.status.S' --output text 2>/dev/null; }

r=$(call friendsSearch "GET /friends/search" $A "" "{\"username\":\"$UB\"}" "")
check "search finds the other user" "$(status "$r")" 200
echo "$(body "$r")" | grep -q "\"id\":\"$B\"" && ok "search result carries the id" || bad "search result carries the id"
echo "$(body "$r")" | grep -qi "email" && bad "search must not return an email" || ok "search returns no email field"

r=$(call friendsSearch "GET /friends/search" $A "" "{\"username\":\"$UA\"}" ""); check "search never returns yourself" "$(body "$r")" "[]"
r=$(call friendsRequest "POST /friends/request" $A "{\"friendId\":\"$A\"}" "" ""); check "cannot add yourself" "$(status "$r")" 400
r=$(call friendsRequest "POST /friends/request" $A "{\"friendId\":\"$B\"}" "" ""); check "request created" "$(status "$r")" 201
check "row A->B is PENDING" "$(row $A $B)" PENDING
check "row B->A is INCOMING" "$(row $B $A)" INCOMING
r=$(call friendsRequest "POST /friends/request" $A "{\"friendId\":\"$B\"}" "" ""); check "asking twice is refused" "$(status "$r")" 409
r=$(call friendsRequest "POST /friends/request" $B "{\"friendId\":\"$A\"}" "" ""); check "asking back is refused with a hint" "$(status "$r")" 409

r=$(call friendsList "GET /friends" $B "" "{\"status\":\"INCOMING\"}" "")
echo "$(body "$r")" | grep -q "$UA" && ok "B sees A's request with a username" || bad "B sees A's request with a username"
r=$(call friendsRespond "POST /friends/respond" $A "{\"requesterId\":\"$B\",\"action\":\"accept\"}" "" ""); check "the asker cannot accept" "$(status "$r")" 404
r=$(call friendsRespond "POST /friends/respond" $B "{\"requesterId\":\"$A\",\"action\":\"accept\"}" "" ""); check "B accepts" "$(status "$r")" 200
check "row A->B is ACCEPTED" "$(row $A $B)" ACCEPTED
check "row B->A is ACCEPTED" "$(row $B $A)" ACCEPTED
r=$(call friendsList "GET /friends" $A "" "{\"status\":\"ACCEPTED\"}" "")
echo "$(body "$r")" | grep -q "$UB" && ok "A lists B as a friend" || bad "A lists B as a friend"

r=$(call friendsRemove "DELETE /friends/{friendID}" $A "" "" "{\"friendID\":\"$B\"}"); check "removed" "$(status "$r")" 200
check "row A->B gone" "$(row $A $B)" None
check "row B->A gone" "$(row $B $A)" None

# a rejected request leaves nothing behind
call friendsRequest "POST /friends/request" $A "{\"friendId\":\"$B\"}" "" "" >/dev/null
r=$(call friendsRespond "POST /friends/respond" $B "{\"requesterId\":\"$A\",\"action\":\"reject\"}" "" ""); check "B rejects" "$(status "$r")" 200
check "rejection leaves no rows" "$(row $A $B)$(row $B $A)" NoneNone

echo; [ $fail = 0 ] && echo "friends backend: all checks passed (test users removed)" || echo "friends backend: FAILURES above (test users removed)"
exit $fail
