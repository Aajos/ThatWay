//
//  SessionView.swift
//  ThatWayWatch
//
//  Test 1: pick A (background location) or B (workout session), start, put the wrist down.
//

import SwiftUI
import ThatWayUI

struct SessionView: View {
    @EnvironmentObject var model: WatchModel
    @EnvironmentObject var session: SessionController

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 6) {
                Picker("Session", selection: $session.kind) {
                    ForEach(SessionController.Kind.allCases) { Text($0.rawValue).tag($0) }
                }
                .disabled(session.isRunning)
                .frame(height: 50)

                Button(session.isRunning ? "Stop session" : "Start session") {
                    if session.isRunning { session.stop() } else { Task { await session.start(model: model) } }
                }
                .tint(session.isRunning ? .red : .green)

                Toggle("Tap each minute", isOn: $session.heartbeat).font(.nunito(12, .semibold))

                Text(session.status).font(.nunito(12, .bold))
                Text("elapsed \(Int(session.elapsed) / 60) min \(Int(session.elapsed) % 60) s").font(.nunito(11, .semibold))
                Text("battery \(session.batteryStart)% → \(session.batteryNow)%").font(.nunito(11, .semibold)).monospacedDigit()
                Text("loc \(model.locationUpdates)  head \(model.headingUpdates)").font(.nunito(11, .semibold)).monospacedDigit()
                Text("Logs: Documents/SpikeLogs").font(.nunito(9, .semibold)).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 4)
        }
    }
}
