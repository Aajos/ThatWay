//
//  ThatWayWatchApp.swift
//  ThatWayWatch
//
//  THROWAWAY SPIKE UI. Answers four questions on a real watch: what keeps guidance alive wrist-down,
//  how to blend GPS course with the magnetometer while moving, and which haptic patterns can be told
//  apart on a run. No maps, polylines, audio or third-party packages.
//
//  Safety rule: if the paired iPhone is in Drive mode the watch refuses to guide and closes (see `DriveNoticeView`).
//
//  Simulator launch flags (testing aids only): `-spike-autoroute`, `-spike-autostart`, `-spike-kind <label>`,
//  `-spike-phone-mode <mode>`, `-spike-searchtext <words>` (searches and picks the first result), `-spike-open search|tools`.
//

import SwiftUI
import ThatWayCore
import ThatWayUI

@main
struct ThatWayWatchApp: App {
    @StateObject private var model = WatchModel()
    @StateObject private var session = SessionController()
    @StateObject private var tester = HapticTester()
    @StateObject private var phone = PhoneLink()
    @Environment(\.scenePhase) private var phase

    init() { ThatWayFonts.register() }

    private static func arg(_ name: String) -> String? {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: name), i + 1 < args.count else { return nil }
        return args[i + 1]
    }

    var body: some Scene {
        WindowGroup {
            ZStack {
                RadialGradient(colors: [model.theme.worldA, model.theme.worldB], center: .init(x: 0.5, y: 0.54), startRadius: 0, endRadius: 160)
                    .ignoresSafeArea()
                MainView()
                if model.blockedByDriving {
                    DriveNoticeView(theme: model.theme).transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.3), value: model.blockedByDriving)
            .foregroundStyle(model.theme.ink)
            .tint(model.theme.accent)
            .environmentObject(model)
            .environmentObject(session)
            .environmentObject(tester)
            .onAppear { launch() }
            .onChange(of: phase) { _, new in session.notePhase(new) }
            .onChange(of: model.blockedByDriving) { _, blocked in if blocked { session.stop() } }
        }
    }

    private func launch() {
        phone.onMode = { model.applyPhoneMode($0) }
        phone.start()
        model.start()
        if let raw = Self.arg("-spike-phone-mode"), let mode = TravelMode(rawValue: raw) {
            Task { try? await Task.sleep(for: .seconds(2)); model.applyPhoneMode(mode) }
        }
        if let label = Self.arg("-spike-kind"), let kind = SessionController.Kind.allCases.first(where: { $0.logLabel == label }) {
            session.kind = kind
        }
        if ProcessInfo.processInfo.arguments.contains("-spike-autostart") {
            Task { try? await Task.sleep(for: .seconds(3)); await session.start(model: model) }
        }
        if let words = Self.arg("-spike-searchtext") {
            Task {
                for _ in 0..<20 where model.lastFix == nil { try? await Task.sleep(for: .seconds(1)) }
                let search = DestinationSearch()
                await search.search(words, near: model.lastFix)
                if let first = search.places.first { model.setDestination(name: first.name, coordinate: first.coordinate) }
            }
        }
    }
}
