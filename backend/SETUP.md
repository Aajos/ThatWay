# ThatWay backend setup (AWS Console runbook)

**This backend is already built and deployed.** This file is kept as the record of how it was
provisioned by hand in the console, for reference and for rebuilding if it's ever torn down.
A handful of facts below were corrected after the fact to match exactly what's live (table
name, Lambda runtime/file convention, routes) — see `backend/lambda/README.md` for which
functions are actually deployed versus written-ahead-of-time (Sign in with Apple, parked).
If anything here ever conflicts with the running system, the running system wins; check
CloudWatch logs before assuming this doc is still accurate.

This provisions real accounts (Cognito) and a friends API (API Gateway + Lambda + DynamoDB)
for the ThatWay app. Everything here is done by hand in the AWS Console on purpose — the point
is to learn what each piece does before automating it. `.github/workflows/deploy-backend.yml`
deploys *code changes* to the six live Lambdas; the CI/CD section below covers wiring that up.

Region used throughout: **ap-southeast-2 (Sydney)**. Pick whatever region you want, but use the
same one everywhere below — Cognito, DynamoDB, Lambda, and API Gateway all need to agree.

## 1. Cognito User Pool

1. Console → **Cognito** → **User pools** → **Create user pool**.
2. Sign-in options: **Email** (this adds email as a login *alias* on top of whatever Username
   the person picks at sign-up — it does not force the Username itself to be an email address).
3. Password policy: defaults are fine (or tighten if you want).
4. MFA: **No MFA** for now (you can turn it on later without touching app code).
5. Self-service sign-up: **Enable**. Required attributes: `email`. Attribute verification:
   **Send email**, code (not link) — the app expects a 6-digit code. The app's sign-up screen
   collects a separate, freely-chosen **Username** (this is what friends search by and see —
   never their email) alongside the email and password.
6. Message delivery: **Send email with Cognito** (fine for dev; SES for production volume).
7. User pool name: `thatway-users`.
8. **App client**: name it `thatway-ios` (deployed as `ThatWay`), type **Public client**. Under
   "Authentication flows", explicitly enable:
   - **`ALLOW_USER_PASSWORD_AUTH`** — off by default; lets the app call `InitiateAuth` with a
     plain username/password over REST instead of the Amplify SDK's SRP challenge flow.
   - **`ALLOW_REFRESH_TOKEN_AUTH`** — on by default; needed for the app to silently renew its
     60-minute access token instead of forcing a re-login.
   - **`ALLOW_CUSTOM_AUTH`** — only needed once Sign in with Apple (section 7) is actually built.

   Do **not** generate a client secret (public clients on a mobile app can't keep a secret safe).
9. Create the pool. Note down, from the pool's **App integration** tab:
   - **User pool ID** (e.g. `ap-southeast-2_AbCdEfGhI`)
   - **App client ID** (e.g. `1a2b3c4d5e6f7g8h9i0j`)

These are not secrets — they identify the pool/client, they don't authenticate anything by
themselves — so they're safe to put directly in `Config.swift`.

## 2. DynamoDB tables

**Users**
- Table name: `Users`
- Partition key: `id` (String) — this will be the Cognito `sub`
- After creation → **Indexes** tab → **Create index**:
  - Index name: `byUsername`
  - Partition key: `username` (String) — exact match, case-sensitive (whatever casing the
    person typed as their Cognito Username at sign-up)
  - Projected attributes: All

**Friends**
- Table name: `Friends`
- Partition key: `userId` (String)
- Sort key: `otherUserId` (String)
- No extra index needed — every query in this app is `userId = <me>`, which the base table
  already serves.

Leave both on-demand (pay-per-request) capacity — no need to think about provisioned throughput
for a personal project.

## 3. IAM role for the Lambda functions

Console → **IAM** → **Roles** → **Create role** → trusted entity **AWS service** → **Lambda**.

Attach:
- `AWSLambdaBasicExecutionRole` (managed policy — lets it write CloudWatch logs)
- A new inline policy, `thatway-dynamodb-access`, scoped to just the two tables:
  ```json
  {
    "Version": "2012-10-17",
    "Statement": [{
      "Sid": "ThatWayDynamoAccess",
      "Effect": "Allow",
      "Action": ["dynamodb:GetItem", "dynamodb:Query", "dynamodb:PutItem", "dynamodb:DeleteItem"],
      "Resource": [
        "arn:aws:dynamodb:ap-southeast-2:<your-account-id>:table/Users",
        "arn:aws:dynamodb:ap-southeast-2:<your-account-id>:table/Users/index/byUsername",
        "arn:aws:dynamodb:ap-southeast-2:<your-account-id>:table/Friends"
      ]
    }]
  }
  ```
  Any new DynamoDB action or table needs a matching entry here — an index needs its own ARN
  line, it isn't covered by its table's ARN.

Name the role `thatway-lambda-role`.

For Sign in with Apple (section 7), one more function — `authAppleRegister` — needs a
**second** role, since it's the only one that touches Cognito itself. Create it the same way:
- `AWSLambdaBasicExecutionRole`
- The same `thatway-dynamo-access`-style inline policy, but you only need `GetItem`/`PutItem`/
  `Query` on `Users` and its index (this function never touches `Friendships`)
- A new inline policy, `thatway-cognito-admin`, scoped to just this pool:
  ```json
  {
    "Version": "2012-10-17",
    "Statement": [{
      "Effect": "Allow",
      "Action": ["cognito-idp:AdminCreateUser", "cognito-idp:AdminGetUser"],
      "Resource": "arn:aws:cognito-idp:ap-southeast-2:<your-account-id>:userpool/<your-user-pool-id>"
    }]
  }
  ```

Name it `thatway-lambda-apple-role`.

## 4. Lambda functions

**Live today**, all **Node.js 24.x**, table names hardcoded in each function (no environment
variables to set — `Users`/`Friends` are literal strings in the code, matching step 2 exactly):

| Function name (must match exactly — the deploy workflow depends on it) | Source | Role |
|---|---|---|
| `postConfirmation` | `backend/lambda/postConfirmation/index.mjs` | `thatway-lambda-role` |
| `friendsSearch` | `backend/lambda/friendsSearch/index.mjs` | `thatway-lambda-role` |
| `friendsRequest` | `backend/lambda/friendsRequest/index.mjs` | `thatway-lambda-role` |
| `friendsRespond` | `backend/lambda/friendsRespond/index.mjs` | `thatway-lambda-role` |
| `friendsList` | `backend/lambda/friendsList/index.mjs` | `thatway-lambda-role` |
| `friendsRemove` | `backend/lambda/friendsRemove/index.mjs` | `thatway-lambda-role` |

For each one: paste the file's contents straight into the Lambda console's inline code editor
(saved as `index.mjs`, since the runtime is ES modules — `require()` fails with "require is not
defined in ES module scope"), handler `index.handler`. **Click Deploy** — editing the inline
code does nothing until you do. No `package.json`, `node_modules`, or layer — the AWS SDK v3
clients these `import` are built into the Node.js 24.x runtime already; adding your own copy
just risks a version mismatch.

**Written, not deployed yet** (Sign in with Apple — parked, see `backend/lambda/README.md`):
`defineAuthChallenge.js`, `createAuthChallenge.js`, `verifyAuthChallengeResponse.js`,
`authAppleRegister.js`, under `thatway-lambda-role` and a second `thatway-lambda-apple-role`
(needs `cognito-idp:AdminCreateUser`/`AdminGetUser` on this pool's ARN, plus the same
`Users`-table access as above). These four *do* still use CommonJS (`require`) and need
`npm install` run in `backend/lambda/` to produce `node_modules/` before zipping, and
`verifyAuthChallengeResponse`/`authAppleRegister` need `APPLE_BUNDLE_ID` = this app's bundle id
(check **Signing & Capabilities** in Xcode) plus, for `authAppleRegister`, `USER_POOL_ID`. None
of this matters until Sign in with Apple is actually being built — section 7 covers it.

## 5. Wire the Post Confirmation trigger

Cognito → your user pool → **User pool properties** (or **Extensions** depending on console
version) → **Lambda triggers** → **Post confirmation** → select the `postConfirmation`
function. This makes Cognito call it automatically right after someone verifies their email —
that's what creates their row in `Users`.

## 6. API Gateway (HTTP API)

1. API Gateway → **Create API** → **HTTP API** → **Build**. Name: `ThatWay-api`.
2. Add routes, each integrated with the matching Lambda:
   - `GET /friends` → `friendsList` (query string `?status=ACCEPTED|PENDING|INCOMING`,
     defaults to `ACCEPTED`)
   - `GET /friends/search` → `friendsSearch` (query string `?username=<exact name>`)
   - `POST /friends/request` → `friendsRequest`
   - `POST /friends/respond` → `friendsRespond`
   - `DELETE /friends/{friendID}` → `friendsRemove`
3. **Authorization**: create a **JWT authorizer**, name `cognito-auth` —
   - Identity source: `$request.header.Authorization`
   - Issuer: `https://cognito-idp.ap-southeast-2.amazonaws.com/<your-user-pool-id>`
   - Audience: your App Client ID from step 1
   - Attach this authorizer to all five `/friends*` routes. Nothing else needs auth — the app
     talks to Cognito directly for sign-up/sign-in, and sends the **access token** (not the ID
     token) as `Authorization: Bearer <token>` on every one of these calls — this authorizer
     matches its Audience against the access token's `client_id` claim.
4. Deploy to a stage named **`Dev`** (not `$default` — the deployed API uses an explicit stage).
   Note the **Invoke URL**, e.g. `https://abc123xyz.execute-api.ap-southeast-2.amazonaws.com`;
   the app's `apiBaseURL` needs `/Dev` appended to that, no trailing slash — every call 404s
   without the stage.

## 7. Sign in with Apple (native, CUSTOM_AUTH)

This lets the app's native black "Sign in with Apple" button produce a real Cognito session,
without Cognito's Hosted UI or any Apple Services ID/key. The trade-off for skipping that is
this section: three new Cognito Lambda triggers plus the `authAppleRegister` endpoint from
steps 3–6 above.

**How it works end to end**: the app gets an Apple identity token natively (no web view) →
calls `POST /auth/apple/register` once to provision (or confirm) a Cognito account for that
Apple user → then calls Cognito's own `InitiateAuth` with `AuthFlow=CUSTOM_AUTH` → Cognito asks
`defineAuthChallenge` what to do → issues one `CUSTOM_CHALLENGE` (via `createAuthChallenge`,
which needs no real content — the "answer" is just a fresh Apple identity token) → the app
calls `RespondToAuthChallenge` with that identity token as the answer → `verifyAuthChallengeResponse`
independently re-verifies it against Apple's public keys → Cognito issues real tokens directly
in that response, same shape as the password flow.

This is currently parked — it needs a paid Apple Developer Program membership (Sign in with
Apple isn't available to free/personal teams at all; see `Config.appleSignInEnabled` in the iOS
app), and the pieces below were never actually provisioned. Whenever it's picked back up:

1. **Apple Developer portal** (developer.apple.com/account → **Identifiers**) → open the App ID
   for `com.aadittesting.ThatWay.ThatWay` → enable the **Sign in with Apple** capability and
   save. (Nothing else Apple-side is needed — no Services ID, no key, no redirect URI; that
   machinery is only for the Hosted-UI/web OAuth approach, which this isn't.)
2. In Xcode, re-add `CODE_SIGN_ENTITLEMENTS = ThatWay/ThatWay.entitlements;` to both build
   configs in `project.pbxproj` (it was removed because a free team can't provision it), confirm
   **Signing & Capabilities** shows "Sign in with Apple" on the `ThatWay` target, and flip
   `Config.appleSignInEnabled` back to `true`.
3. Enable `ALLOW_CUSTOM_AUTH` on the App Client (see step 1.8 above, if you haven't already).
4. Create the four Lambda functions listed as "written, not deployed yet" in step 4 (they need
   `npm install` + zipping, unlike the six live ones), and add `POST /auth/apple/register` →
   `authAppleRegister` as a new API Gateway route with **no authorizer** attached — there's no
   session yet at that point, which is the whole reason it's a separate public endpoint.
5. Cognito → your user pool → **Lambda triggers** (same place as Post confirmation) → wire:
   - **Define auth challenge** → `defineAuthChallenge`
   - **Create auth challenge** → `createAuthChallenge`
   - **Verify auth challenge response** → `verifyAuthChallengeResponse`

You can't easily test this leg with `curl` the way the rest of the backend is tested below —
you need a real Apple identity token, which only `ASAuthorizationAppleIDProvider` on a signed-in
device/Simulator can produce. Test it from the app itself once `Config.swift` is filled in
(next step): tap "Sign in with Apple", and watch each Lambda's CloudWatch log if anything 401s.

## 8. Fill in the app's config

Open `ThatWay/Config.swift` and fill in: the User Pool ID, App Client ID, region, and the API
Gateway Invoke URL **with `/Dev` appended** (e.g.
`https://abc123xyz.execute-api.ap-southeast-2.amazonaws.com/Dev`) — every call 404s without it.

## 9. Test the backend before touching the app

```bash
POOL_CLIENT_ID=<your app client id>
REGION=ap-southeast-2
API=<your invoke url>/Dev

# Sign up
curl -X POST "https://cognito-idp.$REGION.amazonaws.com/" \
  -H "Content-Type: application/x-amz-json-1.1" \
  -H "X-Amz-Target: AWSCognitoIdentityProviderService.SignUp" \
  -d "{\"ClientId\":\"$POOL_CLIENT_ID\",\"Username\":\"testuser1\",\"Password\":\"Passw0rd!23\",\"UserAttributes\":[{\"Name\":\"email\",\"Value\":\"you+1@example.com\"}]}"

# Confirm with the code emailed to you
curl -X POST "https://cognito-idp.$REGION.amazonaws.com/" \
  -H "Content-Type: application/x-amz-json-1.1" \
  -H "X-Amz-Target: AWSCognitoIdentityProviderService.ConfirmSignUp" \
  -d "{\"ClientId\":\"$POOL_CLIENT_ID\",\"Username\":\"testuser1\",\"ConfirmationCode\":\"123456\"}"

# Sign in — use AuthenticationResult.AccessToken as the Bearer token below, NOT IdToken
# (the JWT authorizer validates access tokens here). ExpiresIn is 3600 seconds (60 min).
curl -X POST "https://cognito-idp.$REGION.amazonaws.com/" \
  -H "Content-Type: application/x-amz-json-1.1" \
  -H "X-Amz-Target: AWSCognitoIdentityProviderService.InitiateAuth" \
  -d "{\"AuthFlow\":\"USER_PASSWORD_AUTH\",\"ClientId\":\"$POOL_CLIENT_ID\",\"AuthParameters\":{\"USERNAME\":\"testuser1\",\"PASSWORD\":\"Passw0rd!23\"}}"

ACCESS_TOKEN=<paste AccessToken here>

curl "$API/friends?status=ACCEPTED" -H "Authorization: Bearer $ACCESS_TOKEN"
curl "$API/friends/search?username=testuser2" -H "Authorization: Bearer $ACCESS_TOKEN"
```

Repeat sign-up/confirm once more for `testuser2`, then from `testuser1`'s access token:
`POST $API/friends/request -d '{"friendId":"<testuser2 sub>"}'`, then from `testuser2`'s access
token: `curl "$API/friends?status=INCOMING"` to find the request, then
`POST $API/friends/respond -d '{"requesterId":"<testuser1 sub>","action":"accept"}'`, then
`GET $API/friends?status=ACCEPTED` from either side should show the other as a friend.
`DELETE $API/friends/<their sub>` removes it (or cancels a still-pending request).

A call that comes back `{"message":"Unauthorized"}` almost always means the access token
expired (60 minutes) — sign in again, or use `REFRESH_TOKEN_AUTH` with the refresh token from
the sign-in response. Errors from the Lambdas themselves come back as `{"error": "..."}`,
a different shape from the authorizer's `{"message": "Unauthorized"}` — the client checks both.

## 10. CI/CD: let GitHub Actions deploy Lambda code changes

This is the actual DevOps piece: once the functions exist (above), pushing a change to
`backend/lambda/**` on `main` should redeploy them without you touching the console again.
`.github/workflows/deploy-backend.yml` is already written for this — it just needs an IAM role
GitHub is allowed to assume, so no long-lived AWS access keys have to live in GitHub.

1. IAM → **Identity providers** → **Add provider** → **OpenID Connect**:
   - Provider URL: `https://token.actions.githubusercontent.com`
   - Audience: `sts.amazonaws.com`
2. IAM → **Roles** → **Create role** → **Web identity** → pick the provider you just made,
   audience `sts.amazonaws.com`. Restrict the trust policy's condition to your repo, e.g.
   `token.actions.githubusercontent.com:sub` = `repo:<your-github-username>/ThatWay:ref:refs/heads/main`.
3. Attach a policy allowing just `lambda:UpdateFunctionCode` on the six live function ARNs
   (least privilege — this role should never be able to touch DynamoDB or IAM itself; add the
   Apple ones here too only once they're actually deployed).
4. Name it `thatway-github-deploy-role`, copy its ARN.
5. In the GitHub repo → **Settings → Secrets and variables → Actions** → new repository
   secret `AWS_DEPLOY_ROLE_ARN` = that ARN.
6. Push a trivial change under `backend/lambda/` to `main` and watch the **Actions** tab —
   that's your first real CI/CD pipeline running.

## 11. Where to go next

Once this is comfortable, the natural next step for more DevOps practice is importing what
you clicked through above into **Terraform** (`terraform import` for each resource, or just
rewrite it from scratch and `terraform apply` into a fresh set of resources) so the whole stack
becomes reproducible and destroyable in one command — the thing console-first setup doesn't
give you. That's a separate exercise from this one; nothing here needs to change for it.


## 12. Proximity (UWB "find a friend"): the `nearby` function

Two phones ranging each other with Apple's Nearby Interaction need each other's *discovery token* first. The backend's
only job is to hand a token from one **accepted friend** to the other, briefly. It stores no location: an offer is an
opaque token plus who it is for, expires after 120 seconds, and is never logged.

1. **DynamoDB** → create table `NearbyOffers`: partition key `userId` (String), sort key `fromUserId` (String),
   on-demand. Then **Additional settings → Time to Live** → attribute name `expiresAt` (a number of epoch seconds).
   TTL deletion can lag by hours, so the function also checks `expiresAt` on every read.
2. **IAM**: add `NearbyOffers` to `thatway-dynamodb-access` (`GetItem`, `Query`, `PutItem`, `DeleteItem`) and make sure
   `Friends` allows `GetItem` (it already does).
3. **Lambda**: create `nearby` (Node.js 24.x, role `thatway-lambda-role`, handler `index.handler`). Upload a zip of
   `backend/lambda/nearby/index.mjs` **and** `core.mjs` (the inline editor can hold both files too). Create it before
   merging, or the deploy workflow fails on its last step.
4. **API Gateway** (same `ThatWay-api`, same `cognito-auth` authorizer), three routes to `nearby`:
   - `PUT /nearby/offers` — body `{"friendId": "...", "token": "<base64>", "kind": "uwb"}`
   - `GET /nearby/offers` — returns the offers addressed to me from accepted friends
   - `DELETE /nearby/offers/{friendId}` — ends a session (clears both directions)
   Then **Deploy** to the `Dev` stage.
5. Test: `backend/scripts/smoke.sh` (below) exercises sign-in, friends and nearby with a confirmed test account.

Not built yet: push notification ("Sam wants to find you"), which belongs to v1.1's push work. Until then the app polls
`GET /nearby/offers` every 2 s, only while the Find screen is open.

## 13. Confirmation email troubleshooting (the code never arrives)

The app side is correct (sign-up, confirm, **Send a new code**, and sign-in with an unconfirmed account all work against
Cognito's public API), so a missing email is Cognito or the mailbox. In order:

1. **Did sign-up reach the pool?** Console → Cognito → your user pool → **Users**. The new user should be listed with
   status `Unconfirmed`. If it is not there, the app is pointing at a different pool (check `Config.cognitoUserPoolId`).
2. **Unblock yourself now**: select that user → **Actions → Confirm account**. Then sign in normally. Use this to keep
   testing while the email is sorted out.
3. **Spam / junk.** Cognito's default sender is `no-reply@verificationemail.com`; Gmail and Outlook often junk it.
   The confirm screen says so and offers **Send a new code**.
4. **Daily cap.** "Send email with Cognito" is limited to **50 emails a day per account/region**, and the limit is
   shared by every sign-up and resend. After a day of testing the pool can silently stop sending (Cognito answers
   `LimitExceededException` to a *resend*, which the app now shows as "Too many attempts").
5. **Message settings.** Cognito → pool → **Authentication → Sign-up** (or **Messaging**): the verification type must be
   **code**, not link, and "Verify email" attribute verification must be on. The message template must contain `{####}`.
6. **Move to SES for real use.** Messaging → Email → **Edit** → *Send email with Amazon SES*: verify a sender address
   (or your own domain) in SES (Sydney, `ap-southeast-2`), and request production access so mail reaches addresses
   you have not verified (in the SES sandbox only verified recipients receive mail). Cost is about US$0.10 per 1,000.
7. **Check SES evidence** once on SES: SES → **Account dashboard → Sending statistics** shows sends, bounces and
   complaints; a bounce or suppression-list entry explains one address that never receives anything.

## 14. Smoke test

```bash
CLIENT_ID=<app client id> API=<invoke url>/Dev backend/scripts/smoke.sh <confirmed username>
```
Prompts for the password (not echoed, not stored). Signs in, then calls `GET /friends`, `GET /nearby/offers` and
checks the API rejects a call with no token. Exit code 0 means the wiring works.
