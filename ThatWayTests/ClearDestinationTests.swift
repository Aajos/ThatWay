//
//  ClearDestinationTests.swift
//  ThatWayTests
//
//  Clearing a destination (or finishing a trip) must return the compass to idle, whatever state the trip was in.
//

import Testing
import CoreLocation
import ThatWayCore
@testable import ThatWay

@MainActor
struct ClearDestinationTests {
    private func makeApp() -> AppModel {
        let app = AppModel(routingManager: RoutingManager(provider: MockRoutingProvider(alwaysSucceedingWith: TestRoutes.trivial)))
        app.clearDestination()
        return app
    }

    private func pickDestination(_ app: AppModel) {
        app.dest = "Somewhere"
        app.destKind = .place
        app.destinationCoordinate = CLLocationCoordinate2D(latitude: 0.001, longitude: 0.001)
    }

    @Test func clearingInPointModeReturnsToIdle() {
        let app = makeApp()
        pickDestination(app)
        #expect(app.isIdle == false)
        app.clearDestination()
        #expect(app.isIdle)
        #expect(app.destinationCoordinate == nil)
        #expect(app.dest.isEmpty)
    }

    @Test func clearingWhileGuidingEndsTheTripAndReturnsToIdle() {
        let app = makeApp()
        pickDestination(app)
        app.mode = .guidance
        #expect(app.guiding)
        app.clearDestination()
        #expect(app.guiding == false, "the trip must be ended, not left running with no destination")
        #expect(app.isIdle)
        #expect(app.destinationCoordinate == nil)
    }

    @Test func clearingAfterArrivalReturnsToIdle() {
        let app = makeApp()
        pickDestination(app)
        app.mode = .guidance
        app.arrived = true
        app.clearDestination()
        #expect(app.arrived == false)
        #expect(app.isIdle)
    }

    @Test func doneOnTheArrivalScreenReturnsToIdleNotToPointingAtTheOldPlace() {
        let app = makeApp()
        pickDestination(app)
        app.mode = .guidance
        app.arrived = true
        app.finishArrival()
        #expect(app.isIdle)
        #expect(app.destinationCoordinate == nil)
        #expect(app.guiding == false && app.arrived == false)
    }

    @Test func endingARouteKeepsTheDestinationInPointMode() {
        let app = makeApp()
        pickDestination(app)
        app.mode = .guidance
        app.endGuidance()
        #expect(app.guiding == false)
        #expect(app.destinationCoordinate != nil, "END keeps the place so the compass keeps pointing at it")
        #expect(app.isIdle == false)
    }
}
