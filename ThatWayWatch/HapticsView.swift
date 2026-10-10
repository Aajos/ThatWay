//
//  HapticsView.swift
//  ThatWayWatch
//
//  Test 3: feel each pattern, then take the blind test while moving.
//

import SwiftUI
import ThatWayUI
import ThatWayCore

struct HapticsView: View {
    @EnvironmentObject var model: WatchModel
    @EnvironmentObject var tester: HapticTester
    @State private var setIndex = 0

    private var set: HapticLibrary.PatternSet { HapticLibrary.all[setIndex] }

    var body: some View {
        ScrollView {
            VStack(spacing: 6) {
                if tester.running {
                    Text(tester.status).font(.nunito(12, .bold))
                    if tester.awaitingAnswer {
                        Text("Which was it?").font(.nunito(13, .semibold))
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 6) {
                            ForEach(tester.options, id: \.self) { e in
                                Button(label(e)) { tester.answer(e) }.font(.nunito(14, .bold))
                            }
                        }
                    }
                    Button("Stop test") { tester.cancel() }.tint(.red)
                } else {
                    Picker("Set", selection: $setIndex) {
                        ForEach(HapticLibrary.all.indices, id: \.self) { Text(HapticLibrary.all[$0].name).tag($0) }
                    }
                    .frame(height: 50)
                    .onChange(of: setIndex) { _, _ in model.hapticSet = set }

                    Text("Feel them first").font(.nunito(11, .semibold)).foregroundStyle(.secondary)
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 6) {
                        ForEach(HapticEvent.allCases, id: \.self) { e in
                            Button(label(e)) { HapticPlayer.play(set.pattern(e)) }.font(.nunito(13, .semibold))
                        }
                    }
                    Button("Blind test L/R ×10") {
                        model.hapticSet = set
                        if !SpikeLog.shared.isOpen { SpikeLog.shared.open(label: "haptics") }
                        tester.start(set: set, events: [.left, .right], trialCount: 10)
                    }
                    Button("Blind test all ×20") {
                        model.hapticSet = set
                        if !SpikeLog.shared.isOpen { SpikeLog.shared.open(label: "haptics") }
                        tester.start(set: set, events: HapticEvent.allCases, trialCount: 20)
                    }
                    if !tester.trials.isEmpty {
                        Text("\(tester.correctCount)/\(tester.trials.count) correct").font(.nunito(14, .black))
                        ForEach(tester.perEvent(), id: \.0) { e, ok, total in
                            Text("\(label(e)): \(ok)/\(total)").font(.nunito(11, .semibold)).monospacedDigit()
                        }
                    }
                }
            }
            .padding(.horizontal, 4)
        }
    }

    private func label(_ e: HapticEvent) -> String {
        switch e { case .left: return "Left"; case .right: return "Right"; case .arrive: return "Arrive"; case .offRoute: return "Off" }
    }
}
