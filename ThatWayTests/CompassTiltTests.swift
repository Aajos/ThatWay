//
//  CompassTiltTests.swift
//  ThatWayTests
//

import Testing
@testable import ThatWay

struct CompassTiltTests {
    @Test func frontTiltHasFiveStepsFromMaxToNone() {
        let angles = CompassTilt.Angles.hard
        let steps = [1.0, 0.7, 0.5, 0.3, 0.1].map { CompassTilt.frontStep(legFraction: $0) }
        #expect(steps == [0, 1, 2, 3, 4])
        let degrees = steps.map { CompassTilt.frontAngle(step: $0, angles: angles) }
        #expect(degrees.first == angles.frontMax)
        #expect(degrees.last == 0)
        #expect(degrees == degrees.sorted(by: >), "tilt only ever decreases as the turn nears")
    }

    @Test func sidewaysStagesFollow500And200() {
        #expect(CompassTilt.sideStage(distance: 900) == .none)
        #expect(CompassTilt.sideStage(distance: 501) == .none)
        #expect(CompassTilt.sideStage(distance: 500) == .mild)
        #expect(CompassTilt.sideStage(distance: 201) == .mild)
        #expect(CompassTilt.sideStage(distance: 200) == .strong)
        #expect(CompassTilt.sideStage(distance: 0) == .strong)
    }

    @Test func sidewaysAngleIsSignedByTurnSideAndNeverForStraight() {
        let a = CompassTilt.Angles.hard
        #expect(CompassTilt.sideAngle(stage: .strong, side: .left, angles: a) == -a.sideStrong)
        #expect(CompassTilt.sideAngle(stage: .mild, side: .right, angles: a) == a.sideMild)
        #expect(CompassTilt.sideAngle(stage: .strong, side: .straight, angles: a) == 0)
        #expect(CompassTilt.sideAngle(stage: .strong, side: nil, angles: a) == 0)
        #expect(CompassTilt.sideAngle(stage: .none, side: .left, angles: a) == 0)
    }

    @Test func offSettingNeverTilts() {
        let a = CompassTilt.Angles.forSetting("Off")
        #expect(CompassTilt.frontAngle(step: 0, angles: a) == 0)
        #expect(CompassTilt.sideAngle(stage: .strong, side: .left, angles: a) == 0)
    }

    @Test func bothAxesCombineWithinFiveHundredMetres() {
        // 400m from a turn on a long leg: still some forward tilt AND a mild sideways lean.
        let a = CompassTilt.Angles.hard
        let front = CompassTilt.frontAngle(step: CompassTilt.frontStep(legFraction: 0.5), angles: a)
        let side = CompassTilt.sideAngle(stage: CompassTilt.sideStage(distance: 400), side: .right, angles: a)
        #expect(front > 0)
        #expect(side == a.sideMild)
    }
}
