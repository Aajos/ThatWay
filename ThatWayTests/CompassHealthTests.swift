//
//  CompassHealthTests.swift
//  ThatWayTests
//

import Testing
import Foundation
@testable import ThatWay

struct CompassHealthTests {
    private let t0 = Date(timeIntervalSinceReferenceDate: 1_000_000)

    /// Walks steadily on `course` for `seconds`, feeding one sample a second starting at `start`.
    private func walk(_ h: inout CompassHealth, course: Double, from start: Date, seconds: Int = 8, speed: Double = 1.4) -> Date {
        var now = start
        for _ in 0..<seconds { h.observe(course: course, speed: speed, at: now); now = now.addingTimeInterval(1) }
        return now
    }

    @Test func agreementLengthensTheCheckInterval() {
        var h = CompassHealth()
        var now = walk(&h, course: 90, from: t0)
        #expect(h.evaluate(heading: 95, headingAccuracy: 10, at: now) == .ok)
        #expect(h.nextCheckAt.timeIntervalSince(now) == 60)

        now = walk(&h, course: 90, from: h.nextCheckAt)
        h.evaluate(heading: 88, headingAccuracy: 10, at: now)
        #expect(h.nextCheckAt.timeIntervalSince(now) == 180)

        now = walk(&h, course: 90, from: h.nextCheckAt)
        h.evaluate(heading: 92, headingAccuracy: 10, at: now)
        #expect(h.nextCheckAt.timeIntervalSince(now) == 300)

        now = walk(&h, course: 90, from: h.nextCheckAt)
        h.evaluate(heading: 90, headingAccuracy: 10, at: now)
        #expect(h.nextCheckAt.timeIntervalSince(now) == 300, "capped at five minutes")
    }

    @Test func noCheckBeforeItIsDue() {
        var h = CompassHealth()
        let now = walk(&h, course: 90, from: t0)
        h.evaluate(heading: 90, headingAccuracy: 10, at: now)
        let early = walk(&h, course: 90, from: now, seconds: 8)
        h.evaluate(heading: 270, headingAccuracy: 10, at: early)   // a flip, but not yet due
        #expect(h.status == .ok)
    }

    @Test func aSingleDisagreementOnlyTriggersARecheck() {
        var h = CompassHealth()
        let now = walk(&h, course: 90, from: t0)
        #expect(h.evaluate(heading: 135, headingAccuracy: 10, at: now) == .unknown, "could be how the phone is held")
        #expect(h.nextCheckAt.timeIntervalSince(now) == 10)
    }

    @Test func twoDisagreementsMarkItSuspectAndPredictTheCourse() {
        var h = CompassHealth()
        var now = walk(&h, course: 90, from: t0)
        h.evaluate(heading: 270, headingAccuracy: 10, at: now)          // flipped 180°
        now = walk(&h, course: 90, from: h.nextCheckAt)
        #expect(h.evaluate(heading: 272, headingAccuracy: 10, at: now) == .suspect)
        #expect(abs((h.predictedHeading ?? 0) - 90) < 0.5)
        #expect(h.intervalIndex == 0)
    }

    @Test func recoveryNeedsTwoAgreements() {
        var h = CompassHealth()
        var now = walk(&h, course: 90, from: t0)
        h.evaluate(heading: 270, headingAccuracy: 10, at: now)
        now = walk(&h, course: 90, from: h.nextCheckAt)
        h.evaluate(heading: 270, headingAccuracy: 10, at: now)
        #expect(h.status == .suspect)

        now = walk(&h, course: 90, from: h.nextCheckAt)
        #expect(h.evaluate(heading: 91, headingAccuracy: 10, at: now) == .suspect)
        now = walk(&h, course: 90, from: h.nextCheckAt)
        #expect(h.evaluate(heading: 89, headingAccuracy: 10, at: now) == .ok)
        #expect(h.nextCheckAt.timeIntervalSince(now) == 60, "back to the one-minute rhythm")
    }

    @Test func slowOrWanderingMovementIsNotASample() {
        var h = CompassHealth()
        var now = walk(&h, course: 90, from: t0, speed: 0.4)             // too slow
        #expect(h.evaluate(heading: 270, headingAccuracy: 10, at: now) == .unknown)

        var wander = CompassHealth()
        now = t0
        for i in 0..<8 { wander.observe(course: Double(i * 20), speed: 1.4, at: now); now = now.addingTimeInterval(1) }   // turning a corner
        #expect(wander.steadyCourse(at: now) == nil)
        #expect(wander.evaluate(heading: 270, headingAccuracy: 10, at: now) == .unknown)
    }

    @Test func aStopResetsTheWindow() {
        var h = CompassHealth()
        var now = walk(&h, course: 90, from: t0, seconds: 5)
        h.observe(course: 90, speed: 0, at: now)
        now = now.addingTimeInterval(1)
        h.observe(course: 90, speed: 1.4, at: now)
        #expect(h.steadyCourse(at: now) == nil)
    }

    @Test func poorReportedAccuracyIsSuspectImmediately() {
        var h = CompassHealth()
        #expect(h.evaluate(heading: 10, headingAccuracy: 45, at: t0) == .suspect)
        #expect(h.evaluate(heading: 10, headingAccuracy: -1, at: t0) == .suspect, "no reading: nothing judged, status kept")
    }

    @Test func noValidReadingJudgesNothing() {
        var h = CompassHealth()
        let now = walk(&h, course: 90, from: t0)
        #expect(h.evaluate(heading: 270, headingAccuracy: -1, at: now) == .unknown)
    }

    @Test func wrapsAcrossNorth() {
        var h = CompassHealth()
        let now = walk(&h, course: 355, from: t0)
        #expect(h.evaluate(heading: 8, headingAccuracy: 10, at: now) == .ok)   // 13° apart
        #expect(abs(CompassHealth.difference(350, 10) - 20) < 0.001)
    }

    @Test func recalibratingKeepsTheWarningUntilProven() {
        var h = CompassHealth()
        var now = walk(&h, course: 90, from: t0)
        h.evaluate(heading: 270, headingAccuracy: 10, at: now)
        now = walk(&h, course: 90, from: h.nextCheckAt)
        h.evaluate(heading: 270, headingAccuracy: 10, at: now)
        h.noteRecalibrating(at: now)
        #expect(h.status == .suspect)
        #expect(h.nextCheckAt.timeIntervalSince(now) == 8)
    }

    @Test func signedDifferenceTakesTheShortWay() {
        #expect(CompassHealth.signedDifference(10, from: 350) == 20)
        #expect(CompassHealth.signedDifference(350, from: 10) == -20)
        #expect(CompassHealth.signedDifference(90, from: 270) == 180)
        #expect(CompassHealth.signedDifference(270, from: 90) == 180)
        #expect(CompassHealth.signedDifference(45, from: 45) == 0)
    }

    @Test func continuousAngleTakesTheShortWayAcrossTheWrapPoint() {
        var a = ContinuousAngle(170)
        var seen: [Double] = []
        for wrapped in [175.0, 179.0, -179.0, -175.0, -170.0, -175.0, 179.0, 170.0] {
            a.update(to: wrapped)
            seen.append(a.value)
        }
        // Never a jump bigger than the real change (9° at most in this sequence), in either direction.
        let all = [170.0] + seen
        for (x, y) in zip(all, all.dropFirst()) { #expect(abs(y - x) <= 9.001) }
        #expect(abs(seen[3] - 185) < 0.001)
        #expect(abs(seen.last! - 170) < 0.001)
    }

    @Test func continuousAngleIsIdempotentAndHandlesNorth() {
        var a = ContinuousAngle(350)
        a.update(to: 350); a.update(to: 350)
        #expect(a.value == 350)
        a.update(to: 10)
        #expect(abs(a.value - 370) < 0.001)
        a.update(to: 350)
        #expect(abs(a.value - 350) < 0.001)
    }
}

@MainActor
struct CompassCheckScopeTests {
    @Test func theCompassCheckOnlyAppliesWhileGuidingATripThatHasNotEnded() {
        let app = AppModel(routingManager: RoutingManager(provider: MockRoutingProvider(alwaysSucceedingWith: TestRoutes.trivial)))
        app.mode = .point
        app.arrived = false
        #expect(app.compassHealthApplies == false, "idle or just pointing: no destination guidance")
        app.mode = .guidance
        #expect(app.compassHealthApplies == true)
        app.arrived = true
        #expect(app.compassHealthApplies == false, "the trip has ended")
        app.mode = .point
        app.arrived = false
    }
}
