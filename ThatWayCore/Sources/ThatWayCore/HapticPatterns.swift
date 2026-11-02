//
//  HapticPatterns.swift
//  ThatWayCore
//
//  Distinct tap patterns for the wrist, described in platform-neutral terms. The watch app maps each
//  `HapticKind` onto a `WKHapticType` preset (the only haptic vocabulary watchOS offers apps), so the
//  patterns themselves — and the rule that they must all differ — can be unit-tested anywhere.
//

import Foundation

/// The watchOS presets available to apps, by name.
public enum HapticKind: String, CaseIterable, Codable {
    case notification, directionUp, directionDown, success, failure, retry, start, stop, click
}

public struct HapticBeat: Equatable {
    public var kind: HapticKind
    /// Seconds to wait after this beat before the next one.
    public var gapAfter: TimeInterval
    public init(_ kind: HapticKind, gapAfter: TimeInterval = 0) { self.kind = kind; self.gapAfter = gapAfter }
}

public enum HapticEvent: String, CaseIterable, Codable { case left, right, arrive, offRoute }

public struct HapticPattern: Equatable {
    public var event: HapticEvent
    public var beats: [HapticBeat]
    public var duration: TimeInterval { beats.dropLast().reduce(0) { $0 + $1.gapAfter } }
}

public enum HapticLibrary {
    public struct PatternSet: Equatable {
        public var name: String
        public var patterns: [HapticPattern]
        public func pattern(_ event: HapticEvent) -> HapticPattern { patterns.first { $0.event == event }! }
    }

    /// Candidate A — "count": the number of taps carries the meaning (left 2, right 3), with the same
    /// plain tap, so it relies on rhythm rather than on telling presets apart through a moving wrist.
    public static let count = PatternSet(name: "count", patterns: [
        HapticPattern(event: .left, beats: [HapticBeat(.click, gapAfter: 0.30), HapticBeat(.click)]),
        HapticPattern(event: .right, beats: [HapticBeat(.click, gapAfter: 0.30), HapticBeat(.click, gapAfter: 0.30), HapticBeat(.click)]),
        HapticPattern(event: .arrive, beats: [HapticBeat(.success)]),
        HapticPattern(event: .offRoute, beats: [HapticBeat(.failure, gapAfter: 0.70), HapticBeat(.failure)]),
    ])

    /// Candidate B — "direction": the presets' own up/down feel carries left/right.
    public static let direction = PatternSet(name: "direction", patterns: [
        HapticPattern(event: .left, beats: [HapticBeat(.directionDown, gapAfter: 0.35), HapticBeat(.directionDown)]),
        HapticPattern(event: .right, beats: [HapticBeat(.directionUp, gapAfter: 0.35), HapticBeat(.directionUp)]),
        HapticPattern(event: .arrive, beats: [HapticBeat(.success)]),
        HapticPattern(event: .offRoute, beats: [HapticBeat(.retry, gapAfter: 0.70), HapticBeat(.retry), HapticBeat(.failure)]),
    ])

    public static let all: [PatternSet] = [count, direction]
}
