import Testing
import Foundation
@testable import ThatWayCore

struct AngleMathTests {
    @Test func signedDifferenceTakesTheShortWay() {
        #expect(AngleMath.signedDifference(10, from: 350) == 20)
        #expect(AngleMath.signedDifference(350, from: 10) == -20)
        #expect(AngleMath.signedDifference(270, from: 90) == 180)
        #expect(AngleMath.difference(359, 1) == 2)
    }
    @Test func circularMeanAcrossNorth() throws {
        let mean = try #require(AngleMath.circularMean([350, 10]))
        #expect(AngleMath.difference(mean, 0) < 0.001)
        #expect(AngleMath.circularMean([]) == nil)
    }
    @Test func normalized() {
        #expect(AngleMath.normalized(-10) == 350)
        #expect(AngleMath.normalized(370) == 10)
    }
}

struct HeadingBlenderTests {
    private func sample(speed: Double, course: Double = 90, mag: Double? = 90, t: Double, accuracy: Double = 5, fixAge: Double = 0) -> HeadingSample {
        HeadingSample(speed: speed, course: course, courseAccuracy: accuracy, fixAge: fixAge, magnetometer: mag, time: t)
    }

    /// Runs the blender at 1 Hz with the given constant inputs and returns the final output.
    @discardableResult
    private func run(_ b: inout HeadingBlender, from t0: Double, seconds: Int, speed: Double, course: Double = 90, mag: Double? = 90) -> HeadingOutput {
        var out = HeadingOutput(heading: nil, source: .none, raw: nil, switched: false)
        for i in 0..<seconds { out = b.update(sample(speed: speed, course: course, mag: mag, t: t0 + Double(i))) }
        return out
    }

    @Test func startsOnMagnetometerWhenStandingStill() {
        var b = HeadingBlender()
        let out = b.update(sample(speed: 0, mag: 200, t: 0))
        #expect(out.source == .magnetometer)
        #expect(out.heading == 200)
    }

    @Test func movesToGPSCourseAboveTheThreshold() {
        var b = HeadingBlender()
        run(&b, from: 0, seconds: 3, speed: 0, course: 90, mag: 200)
        let out = run(&b, from: 3, seconds: 4, speed: 2.0, course: 90, mag: 200)
        #expect(out.source == .gps)
        #expect(AngleMath.difference(out.heading!, 90) < 5, "settles on the course, not the magnetometer")
    }

    @Test func speedHoveringAroundTheThresholdDoesNotFlap() {
        var b = HeadingBlender()
        run(&b, from: 0, seconds: 5, speed: 2.0)
        #expect(b.source == .gps)
        var switches = 0
        // Speed wobbles between 1.0 and 1.6 m/s — below the 1.5 entry speed but above the 0.8 exit speed.
        for i in 0..<60 {
            let speed = i % 2 == 0 ? 1.0 : 1.6
            if b.update(sample(speed: speed, mag: 270, t: 5 + Double(i))).switched { switches += 1 }
        }
        #expect(switches == 0)
        #expect(b.source == .gps)
    }

    @Test func slowingBelowTheExitSpeedHandsBackToTheMagnetometer() {
        var b = HeadingBlender()
        run(&b, from: 0, seconds: 5, speed: 2.0)
        let out = run(&b, from: 5, seconds: 5, speed: 0.3, mag: 120)
        #expect(out.source == .magnetometer)
    }

    @Test func aSingleSpeedSpikeDoesNotSwitchSource() {
        var b = HeadingBlender()
        run(&b, from: 0, seconds: 5, speed: 0.2)
        let spike = b.update(sample(speed: 3.0, t: 5))
        #expect(spike.source == .magnetometer, "needs the dwell time before switching")
        let back = b.update(sample(speed: 0.2, t: 6))
        #expect(back.source == .magnetometer)
        #expect(b.update(sample(speed: 0.2, t: 7)).source == .magnetometer)
    }

    @Test func wraparoundSmoothingNeverSwingsTheLongWay() {
        var b = HeadingBlender()
        b.update(sample(speed: 3, course: 358, mag: nil, t: 0))
        var previous = b.filtered!
        for i in 1...20 {
            let course = i % 2 == 0 ? 358.0 : 2.0           // jitter across north
            let out = b.update(sample(speed: 3, course: course, mag: nil, t: Double(i) * 0.5))
            let step = AngleMath.difference(out.heading!, previous)
            #expect(step < 5, "step \(step) at \(i) — never a swing across the dial")
            previous = out.heading!
        }
        #expect(AngleMath.difference(previous, 0) < 3)
    }

    @Test func filterConvergesWithoutOvershootingAcrossNorth() {
        var b = HeadingBlender()
        b.update(sample(speed: 3, course: 350, mag: nil, t: 0))
        var out = b.update(sample(speed: 3, course: 20, mag: nil, t: 0.25))
        // 30° apart across north: first step moves toward 20 (through 0), not the long way round via 180.
        #expect(AngleMath.difference(out.heading!, 350) < 30)
        for i in 2...30 { out = b.update(sample(speed: 3, course: 20, mag: nil, t: Double(i) * 0.25)) }
        #expect(AngleMath.difference(out.heading!, 20) < 1)
    }

    @Test func aHugeJumpSnapsInsteadOfCrawling() {
        var b = HeadingBlender()
        b.update(sample(speed: 0, mag: 10, t: 0))
        let out = b.update(sample(speed: 0, mag: 190, t: 0.1))   // a flipped magnetometer
        #expect(out.heading == 190)
    }

    @Test func invalidOrStaleOrInaccurateCourseFallsBackToTheMagnetometer() {
        var b = HeadingBlender()
        run(&b, from: 0, seconds: 5, speed: 2.0)
        #expect(b.source == .gps)
        #expect(b.update(sample(speed: 2.0, course: -1, mag: 150, t: 5)).source == .magnetometer, "invalid course")

        var stale = HeadingBlender()
        run(&stale, from: 0, seconds: 5, speed: 2.0)
        #expect(stale.update(sample(speed: 2.0, mag: 150, t: 5, fixAge: 10)).source == .magnetometer, "stale fix")

        var poor = HeadingBlender()
        run(&poor, from: 0, seconds: 5, speed: 2.0)
        #expect(poor.update(sample(speed: 2.0, mag: 150, t: 5, accuracy: 60)).source == .magnetometer, "inaccurate course")
    }

    @Test func noSourceAtAllGivesNoHeading() {
        var b = HeadingBlender()
        let out = b.update(sample(speed: -1, course: -1, mag: nil, t: 0))
        #expect(out.source == .none)
        #expect(out.heading == nil)
    }

    @Test func gpsOnlyWhenNoMagnetometerEvenIfSlow() {
        var b = HeadingBlender()
        let out = b.update(sample(speed: 0.5, course: 45, mag: nil, t: 0))
        #expect(out.source == .gps)
        #expect(out.heading == 45)
    }
}
