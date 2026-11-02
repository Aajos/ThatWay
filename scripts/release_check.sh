#!/usr/bin/env bash
# The gate before an App Store submission. It lists everything that is fine for testing and wrong for the public, and exits
# non-zero while any FAIL remains. Run it before every archive:   scripts/release_check.sh
#
#   FAIL  must be fixed before submitting
#   WARN  a decision to confirm (the answer may be "keep it")
#   ok    checked and fine
#
# Parts that need AWS only run when you are signed in (aws login); otherwise they say SKIPPED, and count as not yet checked.
set -uo pipefail
cd "$(dirname "$0")/.."
REGION="${AWS_REGION:-ap-southeast-2}"
export AWS_PAGER=""
fails=0; warns=0
fail() { echo "FAIL  $*"; fails=$((fails+1)); }
warn() { echo "WARN  $*"; warns=$((warns+1)); }
ok()   { echo "ok    $*"; }
skip() { echo "SKIP  $* (not signed in to AWS: run aws login)"; fails=$((fails+1)); }

echo "== The app"
if grep -q "<key>UIFileSharingEnabled</key>" ThatWay/Info.plist; then
  fail "Info.plist has UIFileSharingEnabled: the app's Documents folder (the test logs) shows in the Files app. REMOVE the test logs before launch: delete UIFileSharingEnabled and LSSupportsOpeningDocumentsInPlace"
else ok "no Files-app sharing"; fi
if grep -q "<key>LSSupportsOpeningDocumentsInPlace</key>" ThatWay/Info.plist; then fail "Info.plist has LSSupportsOpeningDocumentsInPlace (test-log sharing)"; else ok "no open-in-place"; fi
if grep -n "testLogsSection(theme" ThatWay/Compass/ProfileScreen.swift | grep -v "func " | grep -q .; then
  # the call is acceptable only inside a #if DEBUG block
  if awk '/#if DEBUG/{d=1} /#endif/{d=0} /testLogsSection\(theme/ && !/func /{ if(!d) bad=1 } END{exit bad?0:1}' ThatWay/Compass/ProfileScreen.swift; then
    fail "the TEST LOGS section is shown in release builds (ProfileScreen.swift): wrap it in #if DEBUG or remove it before launch"
  else ok "test logs are debug-only"; fi
fi
if grep -rq "https://routing.openstreetmap.de" ThatWayCore/Sources; then
  fail "routing still uses the public OSRM demo servers (ThatWayCore/Sources/ThatWayCore/WatchSync.swift): not allowed for a paid app. Choose a production routing host, and update the privacy policy"
else ok "routing is not on the demo servers"; fi
if grep -q 'static let serverIsAuthoritative = false' ThatWay/Managers/Entitlements.swift; then
  fail "Entitlements.serverIsAuthoritative is false (the app still trusts a test unlock): flip it together with PLAN_CHECK=on"
else ok "the server decides plans"; fi
if grep -q "ITSAppUsesNonExemptEncryption" ThatWay/Info.plist ThatWay.xcodeproj/project.pbxproj; then ok "export compliance is answered"; else fail "ITSAppUsesNonExemptEncryption is not set (export compliance): your attestation, then add one line"; fi
if grep -q "<key>UIFileSharingEnabled</key>" ThatWayWatch/Info.plist; then fail "the watch Info.plist has UIFileSharingEnabled (spike logging): remove it before launch"; else ok "no file sharing on the watch"; fi
if grep -qi "spike" ThatWay.xcodeproj/project.pbxproj; then fail "the project still has spike wording in user-facing strings (the watch name or its permission text): $(grep -ci spike ThatWay.xcodeproj/project.pbxproj) line(s) in project.pbxproj"; else ok "no spike wording in the watch name or permission text"; fi
[ -f ThatWay/PrivacyInfo.xcprivacy ] && [ -f ThatWayWatch/PrivacyInfo.xcprivacy ] && ok "privacy manifests present" || fail "a privacy manifest is missing"
if grep -q 'apiBaseURL = ".*/Dev"' ThatWay/Config.swift; then warn "the app talks to the API stage named Dev (decide whether to add a Prod stage before launch)"; else ok "the API stage is not Dev"; fi
target=$(grep -m1 "IPHONEOS_DEPLOYMENT_TARGET" ThatWay.xcodeproj/project.pbxproj | sed 's/[^0-9.]//g')
warn "deployment target is iOS $target: only phones on that version or later can install it (decide whether that is wanted)"

echo; echo "== The words"
if grep -nE "\[[A-Z][A-Z ,:/'\"a-z.-]{3,}\]" docs/legal/privacy.html docs/legal/terms.html | grep -q .; then
  fail "the legal pages still have [BRACKETED] placeholders:"; grep -noE "\[[A-Z][A-Z ,:/'\"a-z.-]{3,}\]" docs/legal/privacy.html docs/legal/terms.html | sed 's/^/        /'
else ok "no placeholders left in the legal pages"; fi
if grep -q "AgeRule" ThatWay/Managers/AuthManager.swift; then
  want=$(grep -m1 "static let minimum" ThatWay/Managers/AuthManager.swift | sed 's/[^0-9]//g')
  if grep -q "at least $want" docs/legal/terms.html && grep -q "under $want" docs/legal/privacy.html; then ok "minimum age $want matches the app, the terms and the privacy policy"
  else fail "the minimum age ($want) does not match the terms or the privacy policy"; fi
fi

echo; echo "== AWS"
if ! aws sts get-caller-identity >/dev/null 2>&1; then skip "backend checks"; else
  env_of() { aws lambda get-function-configuration --region "$REGION" --function-name "$1" --query "Environment.Variables.$2" --output text 2>/dev/null; }
  [ "$(env_of grants PLAN_CHECK)" = "on" ] && ok "grants checks plans (PLAN_CHECK=on)" || fail "grants does not check plans yet (PLAN_CHECK is not on)"
  [ "$(env_of nearby PLAN_CHECK)" = "on" ] && ok "nearby checks plans" || fail "nearby does not check plans yet (PLAN_CHECK is not on)"
  [ "$(env_of plan ALLOW_SANDBOX)" = "off" ] && ok "sandbox purchases are refused" || fail "plan still accepts sandbox purchases (set ALLOW_SANDBOX=off once the app is public)"
  [ "$(aws sesv2 get-account --region "$REGION" --query ProductionAccessEnabled --output text 2>/dev/null)" = "True" ] && ok "SES is out of sandbox" || fail "SES is in sandbox: sign-up emails use Cognito's 50-a-day sender"
  [ "$(aws cognito-idp describe-user-pool --region "$REGION" --user-pool-id ap-southeast-2_I6w74AQkj --query UserPool.EmailConfiguration.EmailSendingAccount --output text 2>/dev/null)" = "DEVELOPER" ] && ok "Cognito sends through SES" || fail "Cognito still uses its default email sender"
  subs=$(aws sns list-subscriptions-by-topic --region "$REGION" --topic-arn "arn:aws:sns:$REGION:$(aws sts get-caller-identity --query Account --output text):thatway-alerts" --query 'Subscriptions[].SubscriptionArn' --output text 2>/dev/null)
  if [ -z "$subs" ]; then fail "nobody is subscribed to report and error alerts"; elif echo "$subs" | grep -q "PendingConfirmation"; then fail "the alert email subscription is not confirmed yet (check the inbox)"; else ok "report and error alerts are confirmed"; fi
fi

echo
echo "$fails to fix, $warns to confirm."
[ "$fails" -eq 0 ]
