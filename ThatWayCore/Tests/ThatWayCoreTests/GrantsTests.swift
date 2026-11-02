//
//  GrantsTests.swift
//  ThatWayCoreTests
//
//  The promises of the trace permission model that can be checked without a server: the limits, how times are put in words,
//  and that the wire shapes decode the way `GET /grants` and `POST /grants/locate` actually answer.
//

import Testing
import Foundation
@testable import ThatWayCore

struct GrantsTests {
    // MARK: The limits

    @Test func everyKindOfTraceIsFifteenMinutesToTwentyFourHours() {
        #expect(TraceWindow.minHours == 0.25 && TraceWindow.maxHours == 24)
        #expect(TraceWindow.clamp(0) == 0.25)
        #expect(TraceWindow.clamp(0.1) == 0.25)
        #expect(TraceWindow.clamp(5) == 5)
        #expect(TraceWindow.clamp(24) == 24)
        #expect(TraceWindow.clamp(100) == 24, "nothing lasts past 24 hours, for anyone")
        #expect(TraceWindow.clamp(.infinity) == 24)
    }

    @Test func theNumbersTheProductPromises() {
        #expect(TraceWindow.requestLifetime == 1800, "a request waits 30 minutes")
        #expect(TraceWindow.locateInterval == 120, "a new location at most every 2 minutes")
        #expect(TraceWindow.noticeInterval == 1800, "'still tracing you' at most every 30 minutes")
        #expect(TraceWindow.maxHeldTraces == 10 && TraceWindow.maxWaitingRequests == 5)
        #expect(TraceWindow.presets.first == TraceWindow.minHours && TraceWindow.presets.last == TraceWindow.maxHours)
        #expect(TraceWindow.presets.allSatisfy { $0 >= TraceWindow.minHours && $0 <= TraceWindow.maxHours })
    }

    // MARK: Words

    @Test func lengthsAreSaidTheWayAPersonWouldSayThem() {
        #expect(TraceWindow.label(hours: 0.25) == "15 min")
        #expect(TraceWindow.label(hours: 0.5) == "30 min")
        #expect(TraceWindow.label(hours: 1) == "1 h")
        #expect(TraceWindow.label(hours: 1.5) == "1 h 30 min")
        #expect(TraceWindow.label(hours: 24) == "24 h")
        #expect(TraceWindow.label(hours: 99) == "24 h", "never claims more than the maximum")
        #expect(TraceWindow.label(hours: 0) == "15 min", "or less than the minimum")
    }

    @Test func timeLeftIsRoundedDownSoItNeverPromisesMore() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        #expect(TraceWindow.remaining(until: now.addingTimeInterval(30), now: now) == "under a minute")
        #expect(TraceWindow.remaining(until: now.addingTimeInterval(-500), now: now) == "under a minute", "never negative")
        #expect(TraceWindow.remaining(until: now.addingTimeInterval(14 * 60 + 59), now: now) == "14 min")
        #expect(TraceWindow.remaining(until: now.addingTimeInterval(3600), now: now) == "1 h")
        #expect(TraceWindow.remaining(until: now.addingTimeInterval(2 * 3600 + 10 * 60 + 40), now: now) == "2 h 10 min")
    }

    @Test func theLocateCountdown() {
        #expect(TraceWindow.countdown(seconds: 105) == "1:45")
        #expect(TraceWindow.countdown(seconds: 120) == "2:00")
        #expect(TraceWindow.countdown(seconds: 0.2) == "0:01", "rounds up so the button never enables early")
        #expect(TraceWindow.countdown(seconds: -5) == "0:00")
    }

    // MARK: The wire

    @Test func theSyncDecodesBothRoles() throws {
        let json = #"""
        {"asTraced":[
           {"tracerId":"t1","status":"REQUESTED","kind":"oneoff","requestedHours":2,"requestedAt":1800000000,"requestExpiresAt":1800001800},
           {"tracerId":"t2","status":"ACTIVE","kind":"window","until":1800003600,"lastLookedAt":1800000100,"band":"under 200 m","stillTracing":true}],
         "asTracer":[
           {"traceeId":"f1","status":"waiting","kind":"window","expiresAt":1800001800},
           {"traceeId":"f2","status":"active","kind":"oneoff"}],
         "plan":{"until":1800086400,"active":true}}
        """#.data(using: .utf8)!
        let s = try JSONDecoder().decode(GrantsSnapshot.self, from: json)
        #expect(s.asTraced.count == 2 && s.asTracer.count == 2)
        #expect(s.asTraced[0].isRequest && s.asTraced[0].kind == .oneoff && s.asTraced[0].requestedHours == 2)
        #expect(s.asTraced[1].isActive && s.asTraced[1].band == "under 200 m" && s.asTraced[1].stillTracing == true && s.asTraced[1].until == 1_800_003_600)
        #expect(s.asTracer[0].isWaiting && s.asTracer[1].isActive)
        #expect(s.plan == PlanInfo(until: 1_800_086_400, active: true))
    }

    @Test func theTracerSideCarriesNoTimeOtherThanAWaitingRequestsOwnExpiry() {
        let mirror = Mirror(reflecting: TracerEntry(traceeId: "x", status: "active", kind: .window)).children.compactMap(\.label)
        #expect(!mirror.contains("until") && !mirror.contains("grantedUntil") && !mirror.contains("hours"), "the tracer is never shown how long they have")
    }

    @Test func anEmptyPlanAndMissingOptionalsDecode() throws {
        let s = try JSONDecoder().decode(GrantsSnapshot.self, from: #"{"asTraced":[],"asTracer":[],"plan":{"until":null,"active":true}}"#.data(using: .utf8)!)
        #expect(s.asTraced.isEmpty && s.asTracer.isEmpty && s.plan?.until == nil && s.plan?.active == true)
        let bare = try JSONDecoder().decode(GrantsSnapshot.self, from: #"{"asTraced":[],"asTracer":[]}"#.data(using: .utf8)!)
        #expect(bare.plan == nil)
    }

    @Test func locateDecodesAPositionWithItsAgeOrNothing() throws {
        let with = try JSONDecoder().decode(LocateResult.self, from: #"{"position":{"lat":-37.8,"lon":145.2,"acc":8,"age":42},"retryAfter":120}"#.data(using: .utf8)!)
        #expect(with.position?.ageSeconds == 42 && with.position?.latitude == -37.8 && with.retryAfter == 120)
        let without = try JSONDecoder().decode(LocateResult.self, from: #"{"position":null,"retryAfter":120}"#.data(using: .utf8)!)
        #expect(without.position == nil)
    }

    // MARK: Emergency

    @Test func theDiallerIsOfferedTheRightNumberForTheRegion() {
        #expect(EmergencyNumber.forRegion("AU") == "000")
        #expect(EmergencyNumber.forRegion("us") == "911")
        #expect(EmergencyNumber.forRegion("GB") == "999")
        #expect(EmergencyNumber.forRegion("NZ") == "111")
        #expect(EmergencyNumber.forRegion("DE") == "112")
        #expect(EmergencyNumber.forRegion(nil) == "112", "unknown region: the number GSM phones route to the local service")
    }
}
