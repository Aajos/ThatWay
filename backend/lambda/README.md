# Lambda functions

**Deployed and live** — each is its own directory containing `index.mjs`, matching exactly
what's pasted into the Lambda console's inline code editor (Node.js 24.x, ES modules, handler
`index.handler`). The AWS SDK v3 clients they `import` are provided by the runtime — no
`package.json`/`node_modules`/layer needed for these six:
- `postConfirmation/`, `friendsList/`, `friendsSearch/`, `friendsRequest/`, `friendsRespond/`,
  `friendsRemove/`

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
