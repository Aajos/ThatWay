//
//  Config.swift
//  ThatWay
//
//  Endpoints for the AWS backend (see backend/SETUP.md). None of these values are secret —
//  a Cognito app client ID and an API Gateway URL don't authenticate anything by themselves.
//

import Foundation
import ThatWayCore

enum Config {
    /// Kill switch for everything that depends on the AWS backend (Cognito + API Gateway +
    /// DynamoDB) from `backend/SETUP.md` not being provisioned yet. While `false`: RootView
    /// skips the sign-in gate entirely, and ProfileScreen hides the account/friends UI instead
    /// of showing controls that would just fail against the placeholder URLs below. Flip back
    /// to `true` once `backend/SETUP.md` is done and the four values below are filled in.
    static let backendEnabled = true

    /// Kill switch for the "Sign in with Apple" button. Apple's own Personal (free)
    /// development teams cannot use the Sign In with Apple capability at all — Xcode fails to
    /// provision the app for a real device with "Personal development teams... do not support
    /// the Sign In with Apple capability" until either (a) you enroll in the paid Apple
    /// Developer Program ($99/yr), or (b) the entitlement is removed, which is what's done here.
    /// Flip back to `true` and re-add `CODE_SIGN_ENTITLEMENTS = ThatWay/ThatWay.entitlements;`
    /// to both build configs in project.pbxproj once you're on a paid team.
    static let appleSignInEnabled = false

    static let awsRegion = "ap-southeast-2"
    static let cognitoUserPoolId = "ap-southeast-2_I6w74AQkj"
    static let cognitoAppClientId = "2ute5p0mqgufhech5u59sn1is7"
    /// Must include the stage (e.g. `/Dev`), no trailing slash — every call 404s without it.
    static let apiBaseURL = "https://REPLACE_WITH_API_ID.execute-api.ap-southeast-2.amazonaws.com/Dev"

    /// False while `apiBaseURL` is still the placeholder from the template: friends and nearby calls then say so plainly
    /// instead of failing against a host that does not exist.
    static var apiConfigured: Bool { !apiBaseURL.contains("REPLACE_WITH") }

    static var cognitoEndpoint: String { "https://cognito-idp.\(awsRegion).amazonaws.com/" }

    // MARK: - Routing

    /// Per-profile OSRM base URLs. `router.project-osrm.org`'s `/route/v1/<profile>/` path does
    /// **not** actually differentiate by profile — verified with curl: driving, walking, cycling
    /// and foot all returned byte-identical distance/duration for the same coordinates. These
    /// three instead point at `routing.openstreetmap.de`'s separate `routed-car`/`routed-foot`/
    /// `routed-bike` backends, confirmed genuinely distinct (different distance *and* duration
    /// for the same two points, each matching that mode's real-world pace). Both hostnames are
    /// the same FOSSGIS-sponsored demo service per OSRM's own wiki: "restricted to reasonable,
    /// non-commercial use-cases. Do not exceed 1 request per second. No guarantees wrt. uptime,
    /// latency, or data updates." None of this is a production host — swap these, not the code
    /// that reads them, when a real one is chosen.
    // The host table itself lives in ThatWayCore (`OSRMHosts`) so the watch routes against the same hosts.

    /// Every profile above has been empirically verified to return genuinely different results
    /// from the others (see the comment on `osrmBaseURLs`) — flipping this to `false` for a
    /// profile is how a future host swap documents "not verified yet" instead of silently
    /// shipping driving data under another name.
    private static let verifiedProfiles: Set<TravelProfile> = [.driving, .walking, .cycling]

    static func osrmBaseURL(for profile: TravelProfile) -> String {
        OSRMHosts.baseURL(for: profile)
    }

    static func profileVerified(_ profile: TravelProfile) -> Bool {
        verifiedProfiles.contains(profile)
    }

    static let userAgent = "ThatWay/1.0 (\(Bundle.main.bundleIdentifier ?? "com.aadittesting.ThatWay.ThatWay"))"
}
