//
//  SavedPreferencesTests.swift
//  ThatWayTests
//
//  A setting that resets on every launch, or a saved value nobody can choose any more, are both promises the app breaks.
//

import Testing
import Foundation
import ThatWayUI
@testable import ThatWay

struct SavedPreferencesTests {
    private func freshDefaults() -> UserDefaults {
        let name = "prefs-test-\(UUID().uuidString)"
        let d = UserDefaults(suiteName: name)!
        d.removePersistentDomain(forName: name)
        return d
    }
    private let owned: Set<SkinID> = [.needle, .wheel, .clock]

    @Test func nothingSavedMeansTheDefaults() {
        #expect(SavedPreferences.load(from: freshDefaults(), owned: owned) == SavedPreferences())
    }

    @Test func choicesSurviveARelaunch() {
        let d = freshDefaults()
        SavedPreferences(theme: .paper, lastDark: .ember, skin: .wheel, tilt: "Slight", units: "Miles").save(to: d)
        let back = SavedPreferences.load(from: d, owned: owned)
        #expect(back == SavedPreferences(theme: .paper, lastDark: .ember, skin: .wheel, tilt: "Slight", units: "Miles"))
    }

    @Test func aSkinThePersonNoLongerOwnsFallsBackToTheDefault() {
        let d = freshDefaults()
        SavedPreferences(skin: .moon).save(to: d)
        #expect(SavedPreferences.load(from: d, owned: owned).skin == .needle)
        #expect(SavedPreferences.load(from: d, owned: owned.union([.moon])).skin == .moon)
    }

    @Test func unrecognisedValuesFallBackInsteadOfBreakingTheApp() {
        let d = freshDefaults()
        d.set("neon", forKey: "prefs.theme.v1"); d.set("nope", forKey: "prefs.skin.v1")
        d.set("Extreme", forKey: "prefs.tilt.v1"); d.set("Furlongs", forKey: "prefs.units.v1")
        #expect(SavedPreferences.load(from: d, owned: owned) == SavedPreferences())
    }

    @Test func theRememberedDarkThemeIsNeverALightOne() {
        let d = freshDefaults()
        d.set(ThemeID.paper.rawValue, forKey: "prefs.lastDark.v1")
        #expect(!AppTheme.byId(SavedPreferences.load(from: d, owned: owned).lastDark).light)
    }
}
