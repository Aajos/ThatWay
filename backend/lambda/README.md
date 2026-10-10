# Lambda functions

**Deployed and live** — each is its own directory containing `index.mjs`, matching exactly
what's pasted into the Lambda console's inline code editor (Node.js 24.x, ES modules, handler
`index.handler`). The AWS SDK v3 clients they `import` are provided by the runtime — no
`package.json`/`node_modules`/layer needed for these six:
- `postConfirmation/`, `friendsList/`, `friendsSearch/`, `friendsRequest/`, `friendsRespond/`,
  `friendsRemove/`

**Written and tested, not yet created in AWS** — `nearby/` (proximity token exchange for the UWB "find a friend"
feature). It is the one function with two files: `index.mjs` (the handler, wires DynamoDB) and `core.mjs` (the logic).
Zip both. Tests run without AWS or Node: `jsc -m backend/lambda/nearby/test.mjs` (macOS's own JavaScriptCore, at
`/System/Library/Frameworks/JavaScriptCore.framework/Versions/A/Helpers/jsc`) or `node test.mjs`. Setup: SETUP.md
section 12.

**Not deployed yet** — written ahead of time for Sign in with Apple (parked — see
`Config.appleSignInEnabled` in the iOS app — Apple's Sign In With Apple capability needs a paid
Apple Developer Program membership, which this project doesn't have yet). These five files
*do* need the bundled `node_modules/` + `package.json` in this directory (they use `jose` and
the Cognito Identity Provider SDK, which aren't runtime-provided) if you ever zip them up:
- `defineAuthChallenge.js`, `createAuthChallenge.js`, `verifyAuthChallengeResponse.js`,
  `authAppleRegister.js`, `shared/appleVerify.js`, `shared/dynamo.js`

Don't deploy the "not deployed yet" group until Sign in with Apple is actually being built —
`.github/workflows/deploy-backend.yml` only targets the six live functions for exactly this
reason.
