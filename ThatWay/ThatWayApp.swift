//
//  ThatWayApp.swift
//  ThatWay
//
//  Created by Aadit Joshi on 14/9/2026.
//

import SwiftUI
import ThatWayUI

@main
struct ThatWayApp: App {
    init() {
        // The Nunito font ships inside ThatWayUI (shared with the watch app) and is registered here, before any view asks for it.
        ThatWayFonts.register()
        // The performance harness can switch the soft shadows off (`-TW_OFF dialfx`); a no-op in normal builds.
        ThemeEffects.liftEnabled = { Perf.on("dialfx") }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
