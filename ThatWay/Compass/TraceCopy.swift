//
//  TraceCopy.swift
//  ThatWay
//
//  Every sentence a person is asked to agree to, in one place. The rule that governs all of it: never promise one thing and do
//  another, say every risk in plain words, and never let anything be agreed to by default. So:
//    - nothing here may claim something the app or server does not do (each claim below names where it is kept);
//    - the consent wording has a VERSION, and the server records which version was agreed to;
//    - a test pins the wording to its version, so editing a word without bumping the version fails the build.
//

import Foundation
import CryptoKit

enum ConsentCopy {
    /// Bump this whenever any consent sentence changes (the test `consentWordingIsPinnedToItsVersion` fails until you do).
    static let version = "2026-10-18.1"

    /// What the person is told before allowing, with `{name}` for the tracer. Each line states something that is true:
    ///  1 server: locate is limited to once per 2 minutes; the tracer sees direction and distance only (TracePill)
    ///  2 background location while a grant is live (AppModel.updateBackgroundTracking); TraceManager uploads on 25 m moves, every 2 min, on a look; force-quit stops it
    ///  3 server: grantedUntil, revoke, unfriend/block transactions, plan check in authorise()
    ///  4 TraceBanner (persistent), TracedByYouSection (band, last looked), notice at most every 30 minutes (poll, not push)
    ///  5 server: GET /grants for the tracer never includes a time
    ///  6 the safety paragraph; EmergencyNumber only opens the dialler
    ///  7 Entitlements: accepting is free
    static let points: [String] = [
        "{name} can ask for your location, at most once every 2 minutes. They see it as a direction and a distance on their compass.",
        "While this is on, your phone keeps sharing your location with {name}, even when ThatWay is in the background, and iOS shows its blue location indicator. It updates when you move, every couple of minutes, and when {name} asks. If you swipe ThatWay away completely, sharing pauses and {name} sees where you were last and how long ago.",
        "It ends by itself at the time you choose, even if you forget. It also ends if you stop it, unfriend {name}, or block them, or if their plan runs out.",
        "You will see a banner in ThatWay for as long as it is on, and a notification when {name} looks (at most every 30 minutes) or comes close looking for you. You can also see roughly how far away they were when they last looked.",
        "{name} is never told how long you have allowed. They only see that you said yes.",
        "Only allow people you trust. Anyone you allow could use this to find you. If you ever feel unsafe, stop it, block them, and call your local emergency number. ThatWay is not an emergency service and cannot send help.",
        "Saying yes is free. {name} needs a trace plan to use it.",
    ]

    static let tick = "I understand {name} will be able to see where I am until {time}, and that I can stop it at any time."

    /// Everything that is agreed to, as one string (what the pin is computed from).
    static var allText: String { (points + [tick]).joined(separator: "\n") }

    /// A short fingerprint of the wording; it changes whenever a word does.
    static var fingerprint: String {
        SHA256.hash(data: Data(allText.utf8)).prefix(6).map { String(format: "%02x", $0) }.joined()
    }

    static func fill(_ template: String, name: String, time: String? = nil) -> String {
        template.replacingOccurrences(of: "{name}", with: name).replacingOccurrences(of: "{time}", with: time ?? "")
    }
}

enum TraceCopy {
    /// The one thing a tracer is ever told when a trace is not possible, whatever the reason (declined, expired, unfriended, blocked).
    static let cannotTrace = "User cannot be traced, error has occurred"
    static let accepted = "Accepted"
    static let planEnded = "Your trace plan has ended"

    // What a tracer reads before sending a request.
    static func requestIntro(name: String) -> String {
        "\(name) will be asked first. Nothing is shared unless they say yes."
    }
    static let requestDisclosure: [String] = [
        "They choose how long to allow (up to what you ask) and whether it is a one-off or ongoing. You will not be told exactly how long you have.",
        "They will see that you are tracing them, when you last looked, and roughly how far away you were (for example “under 200 m” or “about 2 km”).",
        "You can ask for a new location once every 2 minutes. You see their location as a direction and a distance, never on a map.",
        "This request will expire in 30 minutes.",
    ]
    /// Shown to the TRACED person, who decides.
    static func kindExplanation(_ kind: GrantKindChoice, name: String) -> String {
        switch kind {
        case .once: return "Ends when \(name) switches to someone else, or when the time is up."
        case .keep: return "Stays on while \(name) looks at other friends, until the time is up."
        }
    }

    // The traced person's reminder.
    static func stillTracing(name: String) -> String { "\(name) is still tracing you." }

    // Blocking and reporting.
    static func blockExplanation(name: String) -> String {
        "Blocking removes \(name) as a friend, ends any tracing in both directions, and hides you from each other. They are not told. You can unblock them later, but you will not be friends again unless one of you sends a new request."
    }
    static let reportDisclosure = "Reports are stored for our team to read. We can’t promise a reply time, and we can’t see where anyone is. Reporting does not call for help."
    static let emergencyDisclosure = "ThatWay is not an emergency service. This only opens your phone’s dialler; you press call. If this isn’t the emergency number where you are, dial the local one."

    // Closing an account.
    static let deleteWarning = "This permanently deletes your account and everything linked to it: your sign-in, your friends and requests, who can trace you and who you can trace, your last shared location, your blocks, and your plan record on our servers. It can’t be undone.\n\nPurchases belong to your Apple ID and are handled by Apple. Deleting your account does not cancel a subscription (do that in your Apple ID settings), and refunds are decided by Apple.\n\nReports made by you or about you can be kept for up to a year so we can look after other people. They never contain locations."
    static let deactivateWarning = "Deactivating keeps your sign-in and your plan, and removes everything social now: your friends and requests, who can trace you and who you can trace, and your last shared location. You are hidden from search.\n\nYou can come back by signing in and choosing Reactivate. Your friends will not be restored. If you don’t come back within 12 months, your account is deleted completely."
}

/// What the tracer picks in the request sheet (kept apart from `GrantKind` so the wording can differ from the wire value).
enum GrantKindChoice: String, CaseIterable, Identifiable {
    case once, keep
    var id: String { rawValue }
    var allowTitle: String { self == .once ? "Just this once" : "Keep allowing" }
}
