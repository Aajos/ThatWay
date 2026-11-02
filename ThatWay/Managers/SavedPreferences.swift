//
//  SavedPreferences.swift
//  ThatWay
//
//  The choices a person makes in Settings, remembered between launches: how the compass looks (theme, skin), the tilt and the
//  units. Nothing here is personal data. Anything missing or unrecognised falls back to the default, so a renamed option or an
//  older save can never leave the app in a state nobody chose.
//

import Foundation
import ThatWayUI

struct SavedPreferences: Equatable {
    static let tiltChoices = ["Off", "Slight", "Hard"]
    static let unitChoices = ["Kilometres", "Miles"]

    var theme: ThemeID = .tide
    var lastDark: ThemeID = .tide
    var skin: SkinID = .needle
    var tilt = "Hard"
    var units = "Kilometres"

    private enum Key {
        static let theme = "prefs.theme.v1", lastDark = "prefs.lastDark.v1", skin = "prefs.skin.v1", tilt = "prefs.tilt.v1", units = "prefs.units.v1"
    }

    /// `owned` is the set of skins this person may use: a saved skin they no longer have falls back to the default.
    static func load(from defaults: UserDefaults = .standard, owned: Set<SkinID>) -> SavedPreferences {
        var p = SavedPreferences()
        if let v = defaults.string(forKey: Key.theme).flatMap(ThemeID.init(rawValue:)) { p.theme = v }
        if let v = defaults.string(forKey: Key.lastDark).flatMap(ThemeID.init(rawValue:)), !AppTheme.byId(v).light { p.lastDark = v }
        if let v = defaults.string(forKey: Key.skin).flatMap(SkinID.init(rawValue:)), owned.contains(v) { p.skin = v }
        if let v = defaults.string(forKey: Key.tilt), tiltChoices.contains(v) { p.tilt = v }
        if let v = defaults.string(forKey: Key.units), unitChoices.contains(v) { p.units = v }
        return p
    }

    func save(to defaults: UserDefaults = .standard) {
        defaults.set(theme.rawValue, forKey: Key.theme)
        defaults.set(lastDark.rawValue, forKey: Key.lastDark)
        defaults.set(skin.rawValue, forKey: Key.skin)
        defaults.set(tilt, forKey: Key.tilt)
        defaults.set(units, forKey: Key.units)
    }
}
