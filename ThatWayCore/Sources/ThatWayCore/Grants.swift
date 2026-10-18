//
//  Grants.swift
//  ThatWayCore
//
//  Trace permissions ("grants"): the wire types for `GET /grants`, the limits the product promises, and the plain-language
//  formatting of times. Pure and deterministic, so the promises can be tested without a server or a screen.
//
//  The model, in one paragraph: the person being TRACED grants a permission to ONE tracer, one-way, for a length of time they
//  choose (15 minutes to 24 hours, never more than was asked, never more than 24 hours). The tracer sees only "waiting",
//  "accepted" and "User cannot be traced". Only the traced person ever sees how long a permission lasts. Nothing here holds
//  or draws a coordinate.
//

import Foundation

/// A one-off ends the moment the tracer switches to someone else; a window survives a switch until its time is up.
public enum GrantKind: String, Codable, Sendable, CaseIterable {
    case oneoff
    case window
}

public enum TraceWindow {
    /// 15 minutes to 24 hours, for every kind of permission, for everyone, always.
    public static let minHours = 0.25
    public static let maxHours = 24.0
    /// An unanswered request disappears after this long.
    public static let requestLifetime: TimeInterval = 30 * 60
    /// The tracer may ask for a new location this often at most (the server enforces it too).
    public static let locateInterval: TimeInterval = 120
    /// The traced person is told "still tracing you" this often at most.
    public static let noticeInterval: TimeInterval = 30 * 60
    /// A tracer holds at most this many permissions at once (they look at one at a time), and this many unanswered requests.
    public static let maxHeldTraces = 10
    public static let maxWaitingRequests = 5
    /// What the pickers offer first. (The traced person's slider moves in 5-minute steps between the ends.)
    public static let presets: [Double] = [0.25, 0.5, 1, 3, 8, 24]
    public static let sliderStepHours = 5.0 / 60.0

    public static func clamp(_ hours: Double) -> Double { min(maxHours, max(minHours, hours)) }

    /// "15 min", "45 min", "1 h", "1 h 30 min", "24 h".
    public static func label(hours: Double) -> String {
        let minutes = Int((clamp(hours) * 60).rounded())
        let h = minutes / 60, m = minutes % 60
        if h == 0 { return "\(m) min" }
        return m == 0 ? "\(h) h" : "\(h) h \(m) min"
    }

    /// How long until `date`, as a person would say it: "2 h 10 min", "14 min", "under a minute". Never negative.
    public static func remaining(until date: Date, now: Date) -> String {
        let seconds = date.timeIntervalSince(now)
        if seconds < 60 { return "under a minute" }
        let minutes = Int(seconds / 60)
        let h = minutes / 60, m = minutes % 60
        if h == 0 { return "\(m) min" }
        return m == 0 ? "\(h) h" : "\(h) h \(m) min"
    }

    /// "1:45": a countdown for the "request a new location" button.
    public static func countdown(seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded(.up)))
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

/// One row of what the traced person sees: someone asking, or someone who may trace them now.
public struct TracedEntry: Codable, Equatable, Identifiable, Sendable {
    public var tracerId: String
    /// "REQUESTED" (asking, not yet answered) or "ACTIVE" (may trace now).
    public var status: String
    public var kind: GrantKind
    public var requestedHours: Double?
    public var requestedAt: Double?
    public var requestExpiresAt: Double?
    /// Only the traced person is ever told when a permission ends.
    public var until: Double?
    public var lastLookedAt: Double?
    /// How far the tracer was when they last looked, as a band ("under 200 m", "about 2 km"), never a number.
    public var band: String?
    /// True once per 30 minutes while they keep looking: "sam is still tracing you. Stop?"
    public var stillTracing: Bool?

    public var id: String { tracerId }
    public var isRequest: Bool { status == "REQUESTED" }
    public var isActive: Bool { status == "ACTIVE" }

    public init(tracerId: String, status: String, kind: GrantKind, requestedHours: Double? = nil, requestedAt: Double? = nil,
                requestExpiresAt: Double? = nil, until: Double? = nil, lastLookedAt: Double? = nil, band: String? = nil, stillTracing: Bool? = nil) {
        self.tracerId = tracerId; self.status = status; self.kind = kind; self.requestedHours = requestedHours
        self.requestedAt = requestedAt; self.requestExpiresAt = requestExpiresAt; self.until = until
        self.lastLookedAt = lastLookedAt; self.band = band; self.stillTracing = stillTracing
    }
}

/// One row of what the tracer sees: only "waiting" or "active". Never a time, never a reason.
public struct TracerEntry: Codable, Equatable, Identifiable, Sendable {
    public var traceeId: String
    public var status: String
    public var kind: GrantKind
    /// When a request that is still waiting disappears.
    public var expiresAt: Double?

    public var id: String { traceeId }
    public var isWaiting: Bool { status == "waiting" }
    public var isActive: Bool { status == "active" }

    public init(traceeId: String, status: String, kind: GrantKind, expiresAt: Double? = nil) {
        self.traceeId = traceeId; self.status = status; self.kind = kind; self.expiresAt = expiresAt
    }
}

public struct PlanInfo: Codable, Equatable, Sendable {
    /// When the tracer's own plan ends (epoch seconds); nil when the server is not checking or the plan never ends.
    public var until: Double?
    public var active: Bool

    public init(until: Double?, active: Bool) { self.until = until; self.active = active }
}

/// The whole of `GET /grants`: one periodic sync that serves both roles.
public struct GrantsSnapshot: Codable, Equatable, Sendable {
    public var asTraced: [TracedEntry]
    public var asTracer: [TracerEntry]
    public var plan: PlanInfo?

    public init(asTraced: [TracedEntry] = [], asTracer: [TracerEntry] = [], plan: PlanInfo? = nil) {
        self.asTraced = asTraced; self.asTracer = asTracer; self.plan = plan
    }
}

/// The answer to "request a new location": the last position the traced phone uploaded, with its age (nil if there is none),
/// and how many seconds until another request is allowed.
public struct LocateResult: Codable, Equatable, Sendable {
    public var position: TracePeerPosition?
    public var retryAfter: Double?

    public init(position: TracePeerPosition?, retryAfter: Double? = nil) { self.position = position; self.retryAfter = retryAfter }
}

/// Which number the phone's dialler is offered in an emergency. ThatWay is not an emergency service: this only opens the
/// dialler with a number in it, and the person presses call. Where the region is unknown, 112 (which GSM phones in most
/// countries route to the local emergency service).
public enum EmergencyNumber {
    public static func forRegion(_ code: String?) -> String {
        switch code?.uppercased() {
        case "US", "CA", "MX", "PH", "AR", "PR": return "911"
        case "AU": return "000"
        case "NZ": return "111"
        case "GB", "SG", "HK", "MY": return "999"
        case "JP", "CN": return "110"
        case "BR": return "190"
        default: return "112"
        }
    }
}
