# App Store Connect: what to create

Everything here must match the app, the server and `StoreKit/Plans.storekit` exactly, or purchases will not load or will be refused.
Bundle ID `com.thatway.app`. The product IDs below are what the code and the server use. They cannot be changed after creation.

## Before the products (once)
1. **Agreements, Tax, and Banking**: accept the *Paid Apps* agreement and add bank and tax details. Products cannot be sold until this shows *Active*.
2. App Store Connect, My Apps, ThatWay (create the app record if it does not exist), bundle ID `com.thatway.app`.

## In-app purchases (Monetization, In-App Purchases, +)

| Reference name | Product ID | Type | Price (AUD tier) | Display name | Description |
|---|---|---|---|---|---|
| trace3 | `com.thatway.trace3` | **Consumable** | 0.99 | trace3 | 3 hours of tracing. Buy again to add more time. |
| trace24 | `com.thatway.trace24` | **Consumable** | 2.99 | trace24 | 24 hours of tracing. Buy again to add more time. |
| lifetrace | `com.thatway.lifetrace` | **Non-Consumable** | 499.00 | lifetrace | Pay once. Tracing for as long as ThatWay exists. |

The prices in `Plans.storekit` are 0.99, 2.99, 7.99 and 499.00; choose the nearest price point in your storefront (Apple sets other currencies from it).
Each product also needs: availability (all territories), a **review screenshot** of the paywall, and (optional) review notes.

## Subscription (Monetization, Subscriptions)
1. Create a **subscription group** named `trace`.
2. Add a subscription:

| Reference name | Product ID | Duration | Price | Display name | Description |
|---|---|---|---|---|---|
| trace+ | `com.thatway.traceplus` | **1 month** | 7.99 | trace+ | Monthly. Renews automatically until you cancel. |

3. Localisation for the group (display name `trace`) and for the subscription, as above.

## App Privacy ("nutrition label")
Answer from `docs/legal/privacy.html`. Data used to track you across other companies' apps or sites: **none**.

| Data type | Linked to you | Used for |
|---|---|---|
| Email address | Yes | App functionality (account) |
| User ID / username | Yes | App functionality |
| Precise location | Yes | App functionality (shared with a friend you allowed) |
| Purchases | Yes | App functionality |
| Device ID (push token) | Yes | App functionality |
| Other user content (report details) | Yes | App functionality / safety |

No advertising data, no analytics, no tracking.

## Age
ThatWay's minimum age is **18**: the terms and privacy policy say so, and sign-up needs a tick for "I am 18 or older" (`AgeRule` in the app). Apple's highest rating is 18+, so choose **18+** in the age rating questionnaire (answer it honestly: user-to-user location sharing and reporting, no mature content). If the questionnaire computes a lower rating, use App Store Connect's option to set a higher one, so the store listing never invites younger users than the terms allow.

## URLs to fill in
- **Privacy Policy URL** (required): where `docs/legal/privacy.html` is hosted.
- **Terms of Use URL**: where `docs/legal/terms.html` is hosted. Also add it as a link in the app description if you use Apple's standard licence.
- **Support URL** (required) and a **contact email**.

## Review notes (App Review will ask how to test)
- Provide a demo account (two, since tracing needs two phones, or explain the flow) and note that tracing needs a second account that has accepted a friend request and allowed a trace.
- Explain that background location is used **only** while a friend has been allowed to trace the person (blue indicator shown), and that the app never needs "Always".
- Mention the camera is used only after the person taps "Show direction", for Nearby Interaction camera assistance.

## After the products exist: switching the server on
1. Test with a **sandbox tester** on a real phone: buy `trace3`, check the plan shows "ends in 3 h".
2. Set `PLAN_CHECK=on` on the `grants` and `nearby` functions and set `Entitlements.serverIsAuthoritative = true` in the app (they go together).
3. Set `ALLOW_SANDBOX=off` on the `plan` function only when the app is live to the public.

## Blockers I found while checking (not about products)
- **Route provider.** `Config.swift` points at the FOSSGIS demo OSRM servers, which are for "reasonable, non-commercial use", with no uptime guarantee. A paid app should use its own or a paid routing provider before launch. The privacy page names FOSSGIS, so update it when this changes.
- **Privacy manifest.** The app has no `PrivacyInfo.xcprivacy`. Apple requires one that declares the "required reason" APIs the app uses (for example UserDefaults). I can add it.
