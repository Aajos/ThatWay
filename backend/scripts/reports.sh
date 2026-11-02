#!/usr/bin/env bash
# Read ThatWay reports, and stop an account that is being misused. Run after a report email arrives.
#
#   backend/scripts/reports.sh list [days]       reports from the last N days (default 30), newest first
#   backend/scripts/reports.sh show <reportId>   one report in full, with usernames and how many reports there are about that person
#   backend/scripts/reports.sh disable <username>   stop the account NOW: sign-in disabled, signed out everywhere, every trace permission
#                                                   they hold or have given ended, shared position removed. Reversible (enable).
#   backend/scripts/reports.sh enable <username>    let them sign in again (permissions are not restored: they must be asked for again)
#
# Reports hold no locations. This prints usernames, ids, categories and the note the reporter wrote: handle it as private.
# disable: Cognito keeps an already-issued access token valid for up to an hour, but everything behind it is already ended
# (the server checks the permission on every look), so a disabled account can see and be seen by no one.
set -uo pipefail
REGION="${AWS_REGION:-ap-southeast-2}"
POOL_ID="${POOL_ID:-ap-southeast-2_I6w74AQkj}"
export AWS_PAGER=""
aws sts get-caller-identity >/dev/null 2>&1 || { echo "Not signed in to AWS. Run: aws login"; exit 2; }

name_of() { aws dynamodb get-item --region "$REGION" --table-name Users --key "{\"id\":{\"S\":\"$1\"}}" --query 'Item.username.S' --output text 2>/dev/null | sed 's/^None$/(deleted account)/'; }
id_of()   { aws cognito-idp admin-get-user --region "$REGION" --user-pool-id "$POOL_ID" --username "$1" --query 'UserAttributes[?Name==`sub`].Value | [0]' --output text 2>/dev/null; }

case "${1:-}" in
  list)
    days="${2:-30}"; since=$(( $(date +%s) - days * 86400 ))
    aws dynamodb scan --region "$REGION" --table-name Reports --filter-expression "createdAt >= :s" \
      --expression-attribute-values "{\":s\":{\"N\":\"$since\"}}" --output json |
    python3 -c '
import sys, json, datetime
items = json.load(sys.stdin)["Items"]
items.sort(key=lambda i: -int(i["createdAt"]["N"]))
if not items: print("no reports in this period")
for i in items:
    when = datetime.datetime.fromtimestamp(int(i["createdAt"]["N"]), datetime.timezone.utc).strftime("%Y-%m-%d %H:%M UTC")
    print(i["reportId"]["S"], when, i["category"]["S"], "reporter=" + i["reporterId"]["S"][:8], "about=" + i["reportedId"]["S"][:8])
' ;;
  show)
    id="${2:?usage: reports.sh show <reportId>}"
    item=$(aws dynamodb get-item --region "$REGION" --table-name Reports --key "{\"reportId\":{\"S\":\"$id\"}}" --output json)
    echo "$item" | grep -q '"Item"' || { echo "no report with that id"; exit 1; }
    reporter=$(echo "$item" | python3 -c 'import sys,json; print(json.load(sys.stdin)["Item"]["reporterId"]["S"])')
    reported=$(echo "$item" | python3 -c 'import sys,json; print(json.load(sys.stdin)["Item"]["reportedId"]["S"])')
    echo "$item" | python3 -c '
import sys, json, datetime
i = json.load(sys.stdin)["Item"]
print("Report   ", i["reportId"]["S"])
print("Category ", i["category"]["S"])
print("When     ", datetime.datetime.fromtimestamp(int(i["createdAt"]["N"]), datetime.timezone.utc).isoformat())
print("Details  ", i.get("details", {}).get("S") or "(none written)")'
    echo "Made by   $(name_of "$reporter") ($reporter)"
    echo "About     $(name_of "$reported") ($reported)"
    n=$(aws dynamodb scan --region "$REGION" --table-name Reports --filter-expression "reportedId = :r" --expression-attribute-values "{\":r\":{\"S\":\"$reported\"}}" --select COUNT --query Count --output text)
    echo "Reports about this person in total: $n"
    echo "To stop them now:  backend/scripts/reports.sh disable $(name_of "$reported")" ;;
  disable|enable)
    user="${2:?usage: reports.sh $1 <username>}"
    sub=$(id_of "$user"); [ -z "$sub" ] || [ "$sub" = "None" ] && { echo "no sign-in named $user"; exit 1; }
    if [ "$1" = "enable" ]; then
      aws cognito-idp admin-enable-user --region "$REGION" --user-pool-id "$POOL_ID" --username "$user" && echo "$user can sign in again."
      exit 0
    fi
    printf "Disable %s? They are signed out everywhere and every trace permission they hold or gave ends. Type the username to confirm: " "$user"
    read -r typed; [ "$typed" = "$user" ] || { echo "not confirmed, nothing changed"; exit 1; }
    aws cognito-idp admin-disable-user --region "$REGION" --user-pool-id "$POOL_ID" --username "$user" && echo "sign-in disabled"
    aws cognito-idp admin-user-global-sign-out --region "$REGION" --user-pool-id "$POOL_ID" --username "$user" && echo "signed out everywhere"
    ended=0
    for key in traceeId tracerId; do
      rows=$(aws dynamodb scan --region "$REGION" --table-name Grants --filter-expression "$key = :u" --expression-attribute-values "{\":u\":{\"S\":\"$sub\"}}" \
        --projection-expression "traceeId, tracerId" --output json | python3 -c 'import sys,json; [print(i["traceeId"]["S"], i["tracerId"]["S"]) for i in json.load(sys.stdin)["Items"]]')
      while read -r tracee tracer; do
        [ -z "$tracee" ] && continue
        aws dynamodb delete-item --region "$REGION" --table-name Grants --key "{\"traceeId\":{\"S\":\"$tracee\"},\"tracerId\":{\"S\":\"$tracer\"}}" && ended=$((ended+1))
      done <<< "$rows"
    done
    aws dynamodb delete-item --region "$REGION" --table-name Positions --key "{\"userId\":{\"S\":\"$sub\"}}"
    echo "ended $ended trace permission(s) and removed their shared position."
    echo "To undo the sign-in block: backend/scripts/reports.sh enable $user" ;;
  *) echo "usage: reports.sh list [days] | show <reportId> | disable <username> | enable <username>"; exit 2 ;;
esac
