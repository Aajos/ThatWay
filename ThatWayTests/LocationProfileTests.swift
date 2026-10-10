//
//  LocationProfileTests.swift
//  ThatWayTests
//

import Testing
import CoreLocation
@testable import ThatWay
import ThatWayCore

struct LocationProfileTests {
    private func make(_ mode: TravelMode, guiding: Bool = true, destination: Bool = true, toTurn: Double? = 1000, stationary: Bool = false, lowPower: Bool = false) -> LocationProfile {
        LocationProfile.make(mode: mode, guiding: guiding, hasDestination: destination, distanceToNextTurn: toTurn, stationary: stationary, lowPower: lowPower)
    }

    @Test func farFromTheTurnIsCoarseAndNearIsPrecise() {
        for mode in TravelMode.allCases {
            let t = mode.tuning
            let far = make(mode, toTurn: t.precisionRadius + 1)
            let near = make(mode, toTurn: t.precisionRadius)
            #expect(far.accuracy == kCLLocationAccuracyNearestTenMeters)
            #expect(far.distanceFilter == t.farDistanceFilter)
            #expect(near.accuracy == kCLLocationAccuracyBest)
            #expect(near.distanceFilter == t.nearDistanceFilter)
            #expect(near.distanceFilter < far.distanceFilter)
        }
    }

    @Test func fasterModesUseWiderFilters() {
        let filters = [TravelMode.walk, .run, .cycle, .drive].map { $0.tuning.farDistanceFilter }
        #expect(filters == filters.sorted())
        let precision = [TravelMode.walk, .run, .cycle, .drive].map { $0.tuning.precisionRadius }
        #expect(precision == precision.sorted())
    }

    @Test func standingStillRelaxesAndMovingRestores() {
        let still = make(.walk, toTurn: 30, stationary: true)
        #expect(still.accuracy == kCLLocationAccuracyHundredMeters)
        #expect(still.distanceFilter >= 25)
        #expect(make(.walk, toTurn: 30, stationary: false).accuracy == kCLLocationAccuracyBest)
    }

    @Test func pointModeAndIdleNeverAskForMoreThanTheyNeed() {
        let point = make(.walk, guiding: false, destination: true)
        #expect(point.accuracy == kCLLocationAccuracyNearestTenMeters)
        let idle = make(.walk, guiding: false, destination: false)
        #expect(idle.accuracy == kCLLocationAccuracyHundredMeters)
    }

    @Test func lowPowerModeWidensFiltersAndCapsAccuracy() {
        let normal = make(.walk, toTurn: 20)
        let saving = make(.walk, toTurn: 20, lowPower: true)
        #expect(saving.distanceFilter > normal.distanceFilter)
        #expect(saving.headingFilter > normal.headingFilter)
        #expect(saving.accuracy == kCLLocationAccuracyNearestTenMeters)
    }
}
