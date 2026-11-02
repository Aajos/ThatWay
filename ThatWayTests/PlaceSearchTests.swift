//
//  PlaceSearchTests.swift
//  ThatWayTests
//
//  "No matches" blames the words someone typed. When the search itself failed (no connection, MapKit throttling) the app must
//  say that instead.
//

import Testing
import MapKit
@testable import ThatWay

struct PlaceSearchTests {
    @Test func mapKitsEmptyResultIsNoMatches() {
        #expect(PlaceSearch.isNoMatch(MKError(.placemarkNotFound)))
    }

    @Test func everyOtherErrorIsAFailureNotNoMatches() {
        #expect(!PlaceSearch.isNoMatch(MKError(.serverFailure)))
        #expect(!PlaceSearch.isNoMatch(MKError(.loadingThrottled)))
        #expect(!PlaceSearch.isNoMatch(URLError(.notConnectedToInternet)))
    }
}
