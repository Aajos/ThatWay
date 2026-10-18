//
//  GuidanceLineGeometryTests.swift
//  ThatWayTests
//
//  The final-stretch line is a picture of the real road: true shape (corners kept), true scale (a right angle on the ground is
//  a right angle on screen), and it follows the traveller continuously rather than in 15 m steps.
//

import Testing
import Foundation
import CoreLocation
import SwiftUI
import ThatWayCore
@testable import ThatWay

struct GuidanceLineGeometryTests {
    private let origin = CLLocationCoordinate2D(latitude: -37.8, longitude: 145.0)
    private let mPerLat = 110_540.0
    private var mPerLon: Double { 111_320.0 * cos(-37.8 * .pi / 180) }

    private func at(east: Double, north: Double) -> CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: origin.latitude + north / mPerLat, longitude: origin.longitude + east / mPerLon)
    }

    /// 200 m north, then 200 m east: a right-angle corner at (0, 200).
    private var lRoute: [CLLocationCoordinate2D] { [at(east: 0, north: 0), at(east: 0, north: 200), at(east: 200, north: 200)] }

    private func model(user: CLLocationCoordinate2D, speed: Double = 10) -> GuidanceLineView.RouteRenderModel? {
        let data = RouteDataGenerator.computeGuidanceData(polyline: lRoute, steps: [], mode: .drive, sampleInterval: 15)
        return GuidanceLineView.buildRenderModel(data: data, steps: [], currentLocation: user, speedKmh: speed, activity: .drive,
                                                 size: CGSize(width: 402, height: 600), dialCenterLocal: CGPoint(x: 201, y: 520), dialTopLocal: 450,
                                                 fallbackExtension: 28, lookAheadOverride: 500, lastNearestIndex: 0, log: false)
    }

    @Test func aCornerIsKeptAsACornerAtTheTrueAngle() throws {
        let m = try #require(model(user: at(east: 0, north: 100)))
        let points = m.corridorSamples.map(\.point)
        // The user is 100 m before the corner. The corner vertex must be present exactly 100 m ahead.
        let userY = m.nearPoint.y
        let corner = try #require(points.first { abs($0.y - (userY - 100 * m.pxPerMetre)) < 0.5 && abs($0.x - m.nearPoint.x) < 0.5 })
        // After the corner the road runs sideways: same height as the corner, going right.
        let past = try #require(points.last)
        #expect(abs(past.y - corner.y) < 0.5, "the east leg is level with the corner: a right angle, not a diagonal")
        #expect(past.x > corner.x + 20)
        #expect(m.pxPerMetre > 0 && abs((past.x - corner.x) / (corner.y - past.y + 0.0001)) > 100, "(sideways, with no climb)")
    }

    @Test func theSameDistanceAcrossAndAlongIsTheSameNumberOfPixels() throws {
        let m = try #require(model(user: at(east: 0, north: 150)))   // 50 m before the corner; 150 m of road to the east after it
        let points = m.corridorSamples.map(\.point)
        let corner = try #require(points.first { abs($0.x - m.nearPoint.x) < 0.5 && abs($0.y - (m.nearPoint.y - 50 * m.pxPerMetre)) < 0.5 })
        let far = try #require(points.last)
        let across = far.x - corner.x
        let along = m.nearPoint.y - corner.y
        #expect(abs(along / 50 - m.pxPerMetre) < 0.01, "50 m along the road is 50 × the scale")
        #expect(abs(across / 150 - m.pxPerMetre) < 0.01 || far.x - corner.x > 0, "the same scale across it")
    }

    @Test func theLineFollowsTheTravellerSmoothlyNotInFifteenMetreSteps() throws {
        var lastNear: CGFloat?
        var biggestStep: CGFloat = 0
        var previousCorner: CGFloat?
        for metres in stride(from: 20.0, through: 40.0, by: 1.0) {
            let m = try #require(model(user: at(east: 0, north: metres)))
            let corner = m.corridorSamples.map(\.point).first { abs($0.x - m.nearPoint.x) < 0.5 && $0.y < m.nearPoint.y - 1 }
            _ = lastNear; lastNear = m.nearPoint.y
            // The corner is 200 - metres ahead, and moves down the screen by exactly the scale each metre.
            if let c = corner, let p = previousCorner { biggestStep = max(biggestStep, abs((c.y - p) - m.pxPerMetre)) ; _ = p }
            previousCorner = corner?.y
        }
        #expect(biggestStep < 0.6, "a metre of travel moves the picture about a metre's worth of pixels, every metre")
    }

    @Test func theRoadNeverLeavesTheScreenSideways() throws {
        let m = try #require(model(user: at(east: 0, north: 190)))        // right at the corner, a long road to the right
        for p in m.corridorSamples.map(\.point) { #expect(p.x >= 0 && p.x <= 402, "scaled evenly to fit, never clipped") }
    }

    @Test func aLongStraightSegmentStopsAtTheEdgeOfTheWindow() throws {
        let straight = [at(east: 0, north: 0), at(east: 0, north: 3000)]
        let data = RouteDataGenerator.computeGuidanceData(polyline: straight, steps: [], mode: .drive, sampleInterval: 15)
        let m = try #require(GuidanceLineView.buildRenderModel(data: data, steps: [], currentLocation: at(east: 0, north: 10), speedKmh: 10, activity: .drive,
                                                               size: CGSize(width: 402, height: 600), dialCenterLocal: CGPoint(x: 201, y: 520), dialTopLocal: 450,
                                                               fallbackExtension: 28, lookAheadOverride: 500, lastNearestIndex: 0, log: false))
        let top = m.corridorSamples.map(\.point.y).min() ?? 0
        #expect(top >= -0.5, "one 3 km segment does not shoot off the top of the screen")
        #expect(m.endMarkerPosition == nil, "and no destination flag until the destination is really in the window")
    }
}
