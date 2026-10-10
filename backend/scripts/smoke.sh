#!/usr/bin/env bash
# Confirms the deployed backend is wired up end to end, using an already-confirmed test account.
#   CLIENT_ID=<app client id> API=https://<id>.execute-api.ap-southeast-2.amazonaws.com/Dev backend/scripts/smoke.sh <username>
# The password is read from the terminal (not echoed, not stored). Tokens and responses are never printed.
set -uo pipefail
REGION="${REGION:-ap-southeast-2}"
: "${CLIENT_ID:?set CLIENT_ID}"; : "${API:?set API (invoke URL including the /Dev stage)}"
USERNAME_IN="${1:?usage: smoke.sh <confirmed username>}"
read -r -s -p "Password for $USERNAME_IN: " PASSWORD; echo

fail=0
check() { if [ "$2" = "$3" ]; then echo "ok    $1"; else echo "FAIL  $1 (expected $3, got $2)"; fail=1; fi; }

body=$(python3 -c 'import json,sys; print(json.dumps({"AuthFlow":"USER_PASSWORD_AUTH","ClientId":sys.argv[1],"AuthParameters":{"USERNAME":sys.argv[2],"PASSWORD":sys.argv[3]}}))' "$CLIENT_ID" "$USERNAME_IN" "$PASSWORD")
resp=$(curl -s -m 20 -X POST "https://cognito-idp.$REGION.amazonaws.com/" \
  -H "Content-Type: application/x-amz-json-1.1" -H "X-Amz-Target: AWSCognitoIdentityProviderService.InitiateAuth" -d "$body")
TOKEN=$(printf '%s' "$resp" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("AuthenticationResult",{}).get("AccessToken",""))' 2>/dev/null)
unset PASSWORD body
if [ -z "$TOKEN" ]; then
  echo "FAIL  sign-in: $(printf '%s' "$resp" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d.get("__type","?"))' 2>/dev/null)"; exit 1
fi
echo "ok    sign-in"

code() { curl -s -o /dev/null -m 20 -w '%{http_code}' "$@"; }
check "GET /friends (with token)"            "$(code "$API/friends?status=ACCEPTED" -H "Authorization: Bearer $TOKEN")" 200
check "GET /friends (no token is refused)"   "$(code "$API/friends?status=ACCEPTED")" 401
check "GET /nearby/offers (with token)"      "$(code "$API/nearby/offers" -H "Authorization: Bearer $TOKEN")" 200
check "GET /nearby/offers (no token refused)" "$(code "$API/nearby/offers")" 401
check "PUT /nearby/offers to a stranger is refused" \
  "$(code -X PUT "$API/nearby/offers" -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" -d '{"friendId":"not-a-friend","token":"QUJD","kind":"uwb"}')" 403
exit $fail
