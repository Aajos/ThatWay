//
//  SharingReadinessTests.swift
//  ThatWayTests
//
//  Saying yes to a trace must never be possible with settings that would quietly stop the phone from sharing.
//

import Testing
import CoreLocation
@testable import ThatWay

struct SharingReadinessTests {
    @Test func whileUsingWithPreciseIsEnough() {
        #expect(SharingReadiness.from(status: .authorizedWhenInUse, reducedAccuracy: false) == .ready)
        #expect(SharingReadiness.from(status: .authorizedAlways, reducedAccuracy: false) == .ready)
    }

    @Test func preciseOffIsNotReady() {
        #expect(SharingReadiness.from(status: .authorizedWhenInUse, reducedAccuracy: true) == .imprecise)
        #expect(SharingReadiness.from(status: .authorizedAlways, reducedAccuracy: true) == .imprecise)
    }

    @Test func neverAskedOrLapsedOnceAsksAgain() {
        #expect(SharingReadiness.from(status: .notDetermined, reducedAccuracy: false) == .notAsked)
        #expect(SharingReadiness.notAsked.buttonTitle == "Allow location")
    }

    @Test func deniedOrRestrictedGoesToSettings() {
        #expect(SharingReadiness.from(status: .denied, reducedAccuracy: false) == .off)
        #expect(SharingReadiness.from(status: .restricted, reducedAccuracy: false) == .off)
        #expect(SharingReadiness.off.buttonTitle == "Open Settings")
        #expect(SharingReadiness.imprecise.buttonTitle == "Open Settings")
    }

    @Test func everyProblemSaysWhatToDoAndNamesTheFriend() {
        for r in [SharingReadiness.notAsked, .off, .imprecise] {
            #expect(r.explanation(name: "sam").contains("sam"))
            #expect(!r.bannerText.isEmpty)
        }
        #expect(SharingReadiness.off.explanation(name: "sam").contains("While Using the App"))
        #expect(SharingReadiness.imprecise.explanation(name: "sam").contains("Precise Location"))
        #expect(SharingReadiness.ready.explanation(name: "sam").isEmpty)
    }
}
