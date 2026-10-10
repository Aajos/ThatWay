//
//  CompassHealth.swift
//  ThatWay
//
//  Notices when the phone's compass has gone wrong (it occasionally flips 180° or drifts, and iOS
//  gives apps no way to ask it to recalibrate silently) by comparing it with something independent:
//  the direction the traveller is actually moving, from GPS.
//
//  The check only runs on a clean sample — moving at a real pace along a steady course — and is
//  deliberately slow and sceptical, because a phone held a little sideways also disagrees with the
//  direction of travel:
//    - agreement lengthens the gap to the next check: 1 min, then 3, then 5;
//    - a disagreement is re-checked 10 s later, and only a second one marks the compass suspect;
//    - while suspect it keeps checking every 10 s, and two agreements in a row clear it;
//    - a heading iOS itself reports as poorly calibrated (accuracy worse than 30°) is suspect at once.
//
//  Pure value type with an injected clock, so every rule is unit-tested.
//

import Foundation
import CoreLocation
import ThatWayCore

struct CompassHealth {
    enum Status: Equatable { case unknown, ok, suspect }

    static let tolerance: CLLocationDirection = 20
    static let minimumSpeed: CLLocationSpeed = 1.0
    static let checkIntervals: [TimeInterval] = [60, 180, 300]
    static let recheckDelay: TimeInterval = 10
    static let poorAccuracy: CLLocationDirection = 30
    /// How long the course must hold steady (and the traveller keep moving) to count as a clean sample.
    static let steadyWindow: TimeInterval = 6
    static let steadySpread: CLLocationDirection = 20

    private(set) var status: Status = .unknown
    /// The GPS direction of travel at the last clean sample — what the compass *should* read when the
    /// phone points the way you're walking. Drawn as the ghost compass while suspect.
    private(set) var predictedHeading: CLLocationDirection?
    private(set) var intervalIndex = 0
    private(set) var nextCheckAt = Date.distantPast
    private var disagreements = 0
    private var agreementsWhileSuspect = 0
    private var samples: [(at: Date, course: CLLocationDirection)] = []

    // MARK: Samples

    /// Feed once a second with the latest fix. Gaps, slow movement or an unknown course reset the window.
    mutating func observe(course: CLLocationDirection, speed: CLLocationSpeed, at now: Date) {
        guard course >= 0, speed >= Self.minimumSpeed else { samples.removeAll(); return }
        samples.append((now, course))
        samples.removeAll { now.timeIntervalSince($0.at) > Self.steadyWindow + 1 }
    }

    /// The mean course of the window, if it spans `steadyWindow` and never wandered more than `steadySpread`.
    func steadyCourse(at now: Date) -> CLLocationDirection? {
        guard let first = samples.first, now.timeIntervalSince(first.at) >= Self.steadyWindow - 1 else { return nil }
        // Circular mean.
        let x = samples.reduce(0.0) { $0 + cos($1.course * .pi / 180) }
        let y = samples.reduce(0.0) { $0 + sin($1.course * .pi / 180) }
        let mean = (atan2(y, x) * 180 / .pi + 360).truncatingRemainder(dividingBy: 360)
        guard samples.allSatisfy({ Self.difference($0.course, mean) <= Self.steadySpread }) else { return nil }
        return mean
    }

    // MARK: Checks

    /// Runs a check if one is due. `heading` is the compass reading, `headingAccuracy` its reported
    /// uncertainty in degrees (negative = no valid reading, in which case nothing is judged).
    @discardableResult
    mutating func evaluate(heading: CLLocationDirection, headingAccuracy: CLLocationDirection, at now: Date) -> Status {
        guard headingAccuracy >= 0 else { return status }

        if headingAccuracy > Self.poorAccuracy {
            // iOS itself says the compass can't be trusted: no need to wait for a comparison.
            markSuspect(at: now)
            return status
        }
        guard now >= nextCheckAt, let course = steadyCourse(at: now) else { return status }
        predictedHeading = course

        if Self.difference(heading, course) <= Self.tolerance {
            disagreements = 0
            if status == .suspect {
                agreementsWhileSuspect += 1
                if agreementsWhileSuspect >= 2 {
                    status = .ok
                    intervalIndex = 0
                    agreementsWhileSuspect = 0
                    nextCheckAt = now.addingTimeInterval(Self.checkIntervals[0])
                } else {
                    nextCheckAt = now.addingTimeInterval(Self.recheckDelay)
                }
            } else {
                status = .ok
                nextCheckAt = now.addingTimeInterval(Self.checkIntervals[intervalIndex])
                intervalIndex = min(intervalIndex + 1, Self.checkIntervals.count - 1)
            }
        } else {
            agreementsWhileSuspect = 0
            disagreements += 1
            if disagreements >= 2 || status == .suspect {
                markSuspect(at: now)
            } else {
                nextCheckAt = now.addingTimeInterval(Self.recheckDelay)   // could just be how the phone is held
            }
        }
        return status
    }

    /// After the user taps "recalibrate": keep the warning up until the compass has proved itself
    /// (two agreeing checks), starting soon.
    mutating func noteRecalibrating(at now: Date) {
        agreementsWhileSuspect = 0
        disagreements = 0
        status = .suspect
        nextCheckAt = now.addingTimeInterval(8)
    }

    mutating func reset() { self = CompassHealth() }

    private mutating func markSuspect(at now: Date) {
        status = .suspect
        intervalIndex = 0
        agreementsWhileSuspect = 0
        nextCheckAt = now.addingTimeInterval(Self.recheckDelay)
    }

    /// Signed turn from `b` to `a` in degrees, -180...180 (positive = clockwise).
    static func signedDifference(_ a: CLLocationDirection, from b: CLLocationDirection) -> Double { AngleMath.signedDifference(a, from: b) }

    /// Smallest angle between two bearings, 0...180.
    static func difference(_ a: CLLocationDirection, _ b: CLLocationDirection) -> CLLocationDirection { AngleMath.difference(a, b) }
}
