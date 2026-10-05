//
//  CompassTilt.swift
//  ThatWay
//
//  The compass tilt algorithm as pure functions, so it can be unit-tested and so the audio
//  cues can later share the same thresholds.
//
//  Front/back tilt: 5 discrete angles, max → none, by how much of the current leg (last turn
//  → next turn/destination) is still ahead. Max straight after a turn, none near the next one.
//
//  Sideways tilt: 2 angles per side, by distance to the next turn/destination:
//  beyond 500m none, 500m–200m mild, inside 200m strong. Straight/roundabout-straight/arrive
//  never tilt sideways. The two axes are independent and combine.
//

import Foundation
import ThatWayCore

enum CompassTilt {
    /// Fractions of the maximum front tilt for steps 0...4 (0 = just after a turn).
    static let frontFractions: [Double] = [1, 0.75, 0.5, 0.25, 0]
    static let frontStepCount = frontFractions.count

    /// Distance thresholds (metres to the next turn) for the sideways stages.
    static let mildSideDistance: Double = 500
    static let strongSideDistance: Double = 200

    enum SideStage: Int, Comparable {
        case none = 0, mild, strong
        static func < (a: SideStage, b: SideStage) -> Bool { a.rawValue < b.rawValue }
    }

    /// Angles in degrees for one "Compass tilt" setting.
    struct Angles: Equatable {
        let frontMax: Double
        let sideMild: Double
        let sideStrong: Double
        static let off = Angles(frontMax: 0, sideMild: 0, sideStrong: 0)
        static let slight = Angles(frontMax: 28, sideMild: 11.5, sideStrong: 27)
        static let hard = Angles(frontMax: 45, sideMild: 19, sideStrong: 43)

        static func forSetting(_ setting: String) -> Angles {
            switch setting {
            case "Off": return .off
            case "Slight": return .slight
            default: return .hard
            }
        }
    }

    /// Step 0 (max tilt) ... 4 (none) from the share of the leg still to go, 0...1.
    static func frontStep(legFraction: Double) -> Int {
        let f = max(0, min(1, legFraction))
        if f > 0.8 { return 0 }
        if f > 0.6 { return 1 }
        if f > 0.4 { return 2 }
        if f > 0.2 { return 3 }
        return 4
    }

    static func frontAngle(step: Int, angles: Angles) -> Double {
        angles.frontMax * frontFractions[max(0, min(frontStepCount - 1, step))]
    }

    static func sideStage(distance: Double) -> SideStage {
        if distance <= strongSideDistance { return .strong }
        if distance <= mildSideDistance { return .mild }
        return .none
    }

    /// Signed degrees: negative = lean left, positive = lean right. `side` is the turn's side;
    /// straight (or no turn) never leans.
    static func sideAngle(stage: SideStage, side: TurnSide?, angles: Angles) -> Double {
        guard let side, side != .straight else { return 0 }
        let sign: Double = side == .left ? -1 : 1
        switch stage {
        case .none: return 0
        case .mild: return sign * angles.sideMild
        case .strong: return sign * angles.sideStrong
        }
    }
}
