# ThatWay launch readiness report

Written 2026-11-02 (updated the same day after your decisions) from the code, the AWS account and the plan (`docs/thatway_execution_plan.html`), each item checked directly rather
than taken from older notes. "Done" means I saw it work; "built" means it exists and is tested but has not run in real conditions.
The plan page keeps your ticks in your browser only, so I could not read them: where a milestone's status depends on a tick, it says so.

## Bottom line

The product is further along than the plan says (the trace permissions, consent, push, background sharing, safety tools, plans and
account deletion were all planned for v1.1 in April and exist now), but **v1.0 is not ready to submit**. What stands in the way is
almost entirely outside the code: an email sender that will fail at launch, a routing service that is not allowed for a paid app,
the web pages and App Store Connect setup, and a handful of things that have never run on real hardware. None of it is large; most
of it is waiting on a decision or a login from you.

## What I did in this pass

| Item | Result |
|---|---|
| **Reports reach a person.** Every report now emails you (subject marks threats and unwanted tracing as URGENT; no locations in it). `backend/scripts/reports.sh` lists reports, shows one, and can disable an account (signs it out everywhere, ends its trace permissions, removes its shared position; reversible). Tested against real AWS, including `disable` on a throwaway account. | Done. **You must click the confirmation email** SNS sent to aadit2416@gmail.com or nothing is delivered. |
| **Backups.** Point-in-time recovery (35 days) on Users, Friends, Blocks, Reports and Entitlements. Before this there were no backups of anything. | Done |
| **Alarms.** An email when any of the 9 functions errors (5-minute window). There were none before. | Done (shares the same confirmation) |
| **Privacy manifests** for the app and the watch, declaring the APIs Apple requires reasons for and the data the privacy label lists. Confirmed they are in the built app. | Done |
| **Settings that did nothing** (Voice of directions, Haptics on turns, Share destination) removed. They promised features that do not exist, against your rule. | Done |
| **Settings reset on every launch.** Theme, skin, tilt and units are now remembered. | Done |
| **Search errors.** A failed search said "No matches"; it now says it could not search. | Done |
| **CI gate.** Every backend suite and the friends-copies check now run on every push and pull request. | Done |
| Privacy policy, terms, App Store product sheet (earlier today) | Drafted; need your input below |
| **Sign-in fixes** (second pass, from your report that the app forgets you and takes a minute to respond). Four causes, all fixed: the screen did not redraw when sign-in succeeded (it waited for something unrelated, which is the "minute or a restart"; reproduced and fixed, see below); a throttled or failing server signed people out; two refreshes at once could race and sign you out; and sign-ins only lasted 5 days on the server (now 90). | Done. Needs a sign-in on your phone: **anyone signed in before today still has the old 5-day token** |
| **Minimum age 18** (first set to 17, then changed to 18). Sign-up needs a tick for "I am 18 or older"; the terms and privacy policy say 18; `AgeRule` keeps the app and the pages agreeing (and `release_check.sh` checks they match). | Done |
| **Public username route deployed** and tested (fresh, taken, reserved and invalid names). It answers only available or not, rate limited to 5 a second. Sign-up no longer says "Couldn't check right now". | Done |
| **API cap**: 10 requests a second, bursts of 20, for the whole API. Sized for ten daily users (about 2 a second at the busiest, so five times headroom). It bounds the worst case an abusive account or a runaway loop can cost to roughly US$30 a month; normal use stays inside the free tier. Raise it in `aws.sh ops` when real users arrive. | Done |
| **Pre-submission gate**, `scripts/release_check.sh`: lists everything that is fine for testing and wrong for the public (test logs and file sharing, demo routing, test unlock, placeholders, sandbox purchases, email sender, unconfirmed alerts) and exits non-zero until fixed. Test logs stay for now and the gate will keep failing on them until they are removed. | Done. Run it before every archive |
| Test account `zz_itest_push` and the orphan duplicate `aadit` row | Deleted |
| Location-settings check before saying yes to a trace; "Sharing paused" banner | Done (needs a phone test) |
| Release build compiles; 291 app tests, all backend suites pass | Done |

## New focus (3 Nov): offline maps and tourism

The algorithm that decides where and how much of a map to download is **built and tested** (44 tests, `ThatWayCore/.../MapPrefetch`), with a trip planner
for multi-stop routes and a place scorer. Nothing downloads yet. The research changed the plan: Apple's terms forbid caching MapKit tiles and
OpenStreetMap's tile servers forbid prefetching, so offline needs a self-hosted or offline-friendly map source, which is your decision.
Everything is in `docs/map-prefetch-design.md`: the algorithm, what it plans for real trips, privacy, fun ideas for tourists, and the eight decisions needed.

## Blockers: must be resolved before the App Store

| # | Problem | Why it matters | What it needs |
|---|---|---|---|
| 1 | **Sign-up emails use Cognito's default sender** (50 a day, often spam-filtered) and **SES is in sandbox** | Past 50 sign-ups a day, people never receive their verification code and cannot create an account | A domain you own (or a verified sender address), then an SES production-access request. I can prepare it once there is a website URL to give AWS |
| 2 | **Routing uses the public OSRM demo servers** (`Config.swift`), which allow only "reasonable, non-commercial use" with no uptime promise | A paid app can be cut off at any time, and this is the core feature. The privacy policy also names this provider | Your choice of provider: self-hosted (plan estimates about A$45/month) or a paid one. The code change is one table in ThatWayCore |
| 3 | **Privacy and terms pages are not hosted**, and the placeholders are not filled | The App Store requires a live privacy policy URL, and the consent screens should link to them | Your name or business name, contact email, governing law, and a place to host (needs the domain from #1). The minimum age is settled at 18 |
| 4 | **App Store Connect is not set up**: no products, no Paid Apps agreement confirmed, no app record or screenshots known | Nothing can be sold or uploaded for TestFlight | You, following `docs/app-store/products.md` (about ten minutes for the products) |
| 5 | **Export compliance is unanswered** (`ITSAppUsesNonExemptEncryption` is not set) | Apple asks on every upload until it is | Your attestation. The app uses only standard encryption (HTTPS), which normally qualifies for the exemption, but it is a legal declaration, so it is yours to make. Then I add one line |
| 6 | **UWB and the camera arrow have never run on real radios** | This is the headline paid feature | The field test on the 16 and 16 Pro with the debug readout |
| 7 | **Nobody has confirmed a real purchase end to end** (sandbox buy, server verification, plan ends, then `PLAN_CHECK=on`) | Until then the paywall cannot be turned on for real | Products from #4, then a sandbox tester |
| 8 | **Deployment target is iOS 26.5** (unchanged for now) | Only phones already on 26.5 or later can install the app, which may cut off a large share of the audience | Revisit before submission. Lowering it to 18 or 17 needs a check that nothing in the app requires 26 |

## Needs your decision (I did not make these)

| Decision | My lean, if you want one |
|---|---|
| Who reviews reports, and how fast (Apple expects timely action on user-to-user abuse) | You, same day for URGENT, via the email and `reports.sh` |
| What happens to **lifetrace** if ThatWay is ever shut down | A written notice period; the terms have a bracket for it |
| **Public username-availability route** (`aws.sh usernames --apply`). The app already calls it, and it does not exist, so every sign-up shows "Couldn't check right now". It creates a public, unauthenticated, rate-limited route that answers only available or not | Worth doing; dry-run reviewed. I will deploy it on your word |
| Production stage: the app talks to the stage named `Dev` (you said deployment stays as it is for now; `release_check.sh` keeps it as a warning) | Make a `Prod` stage before launch so test changes never touch real users |

### Decided on 2 Nov

| Decision | Outcome |
|---|---|
| Minimum age | **18.** In the app (sign-up tick), terms and privacy policy. It matches Apple's 18+ rating: see the age note in `docs/app-store/products.md` |
| Public username route | **Deployed** |
| Watch app in v1.0 | **Ships.** Still open risk: it quits itself with `exit(0)` when it detects driving, which App Review can reject. Worth replacing with a blocking notice before submission. Every device build also needs a signed watch profile |
| API cap | **10 requests a second, bursts of 20** (chosen for a free tier and ten daily users; see above) |
| Test logs | **Kept** for TestFlight. `scripts/release_check.sh` fails until they are removed (Files-app sharing, the TEST LOGS section) |
| Routing provider, deployment target | **Unchanged for now.** Both stay on the gate script's list |

## Should be done before launch, not blocking

- **Accessibility** (measured 2026-10-09, not yet fixed): text on the accent colour fails contrast on three themes (Paper 2.6:1, Ember 3.1:1, Arcade 3.5:1), VoiceOver cannot read the dial or cards, and Reduce Motion is honoured only by the carousel. The contrast fix changes the look, so it is your call.
- **Performance baselines** (milestone t02, due 14 Nov): none exist on a device. No feature has a measured memory or battery figure (0 of 68); CPU is measured for 5, all in the simulator. The plan's marketing claims depend on these.
- **Polyline on three real routes** (milestone t01, due 14 Oct, overdue): it was rebuilt on 18 Oct, but I have no record of a drive, a walk and a roundabout checked on real roads.
- **The biometric prompt** you reported missing is still not reproduced. Approving a request with the phone attached to the console will show the "TW owner check" logs.
- **The 16 Pro signing you out**: unconfirmed whether the keychain change fixed it; the "TW auth" logs will say.
- **App-level CI**: the app's tests do not run automatically anywhere (macOS runners cost minutes). The backend tests now do.
- **Deploy automation does not work**: the workflow expects an AWS role and a GitHub secret, and AWS has no GitHub OIDC provider or deploy role, so every deploy is currently `aws.sh` from your Mac. It works, but a deploy needs your `aws login`.
- **Leftovers from the old trace design**: the `trace` Lambda and the empty `TraceSessions` table (no routes point at them). The deploy workflow still lists `trace`. Safe to delete; I left them for you.
- **AWS Free Plan ends 24 Mar 2027**, a month before the paid tier is due. The account must be upgraded or the backend closes.
- **16 failure points nothing catches** and 27 features with no automated tests (lists in `docs/vault/_generated/Gaps.md`). The four high-risk ones without tests are `background-guidance`, `backend-config`, `watch-session` and `walkie-talkie` (the last is only a design).
- A flood of reports from one person triggers roughly one email a minute (the limit is per running server instance, so it is approximate). The reports themselves are always stored.
- Report emails contain the reporter's note, which sits in your inbox with no automatic deletion; the privacy policy's 12-month figure covers the database only.

## Plan versus reality (to 15 Jan 2027)

Plan dates are from `thatway_execution_plan.html`.

| Milestone | Date | Status |
|---|---|---|
| m01 App verified against the backend, polyline fixed | 15 Oct | Backend verified. Polyline rebuilt, not yet checked on 3 real routes |
| m02 Routing provider, host and skins | 31 Oct | **Overdue.** Provider seam and skins done; no production host (blocker #2) |
| m03 v1.0 feature complete | 15 Nov | Core done; blockers above remain |
| m04 Submit v1.0 | 15 Jan | At risk until blockers 1 to 5 are cleared |
| m05 Backend: push, entitlements, proximity tokens | 28 Feb | **Done early**, integration-tested |
| m06 v1.1: paid tier with tracking and proximity | 30 Apr | Built early; untested with real purchases or UWB |
| t01 Polyline on 3 routes | 14 Oct | Overdue, unverified |
| t02 Power and memory baselines | 14 Nov | Not started |
| t03 Internal TestFlight | 1 Dec | Needs App Store Connect (#4) and a build upload |
| t04 20 to 50 outside testers | 20 Dec | Not started |
| t05 App Store ready | 10 Jan | Privacy manifest done today; labels, URL, screenshots and review dry run remain |
| t06 Proximity field-tested | 31 Mar | Ready to start (needs the 16 and 16 Pro). The plan's "Bluetooth on the SE 2nd gen" is **not built**: the SE gets GPS direction and distance only |
| k01 Waitlist page and demo videos | 15 Dec | Not started (no website yet) |
| c01 Apple Developer Program | 15 Nov | Done (paid 17 Oct). Small Business Program enrolment: I cannot tell |
| c02 Website and privacy policy | 5 Jan | Policy drafted; website and hosting not started |

## What I need from you, in order

1. Click the confirmation email from AWS Notifications (sent to aadit2416@gmail.com) so report and error alerts are delivered.
2. Decide the domain and hosting, then fill in the brackets in `docs/legal/*.html` (name, email, law, lifetrace, report reviewer).
3. Create the App Store Connect app record, agreement and products from `docs/app-store/products.md`.
4. Choose a routing provider.
5. Sign in once on each phone after the new build is installed (older sign-ins still expire after 5 days).
6. Connect and unlock the 16 and 16 Pro for the field test.
7. Before every archive, run `scripts/release_check.sh` and clear what it fails on.
