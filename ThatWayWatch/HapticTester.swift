//
//  HapticTester.swift
//  ThatWayWatch
//
//  Test 3: blind identification of the haptic patterns. A pattern plays after a random pause; the
//  wearer says which one it was by tapping a button. Only the set name, the event played, the answer
//  and the reaction time are logged.
//

import SwiftUI
import ThatWayCore
import WatchKit

@MainActor
final class HapticTester: ObservableObject {
    struct Trial: Identifiable {
        let id = UUID()
        let played: HapticEvent
        let answer: HapticEvent?
        let reactionMs: Int?
        var correct: Bool { answer == played }
    }

    @Published private(set) var running = false
    @Published private(set) var awaitingAnswer = false
    @Published private(set) var status = ""
    @Published private(set) var trials: [Trial] = []
    @Published private(set) var options: [HapticEvent] = []

    private var task: Task<Void, Never>?
    private var playedAt = Date()
    private var current: HapticEvent?
    private var set = HapticLibrary.count
    private var answered: HapticEvent??     // .some(nil) = timed out

    var correctCount: Int { trials.filter(\.correct).count }

    func start(set: HapticLibrary.PatternSet, events: [HapticEvent], trialCount: Int) {
        cancel()
        self.set = set
        options = events
        trials = []
        running = true
        // Balanced plan, shuffled.
        var plan: [HapticEvent] = []
        while plan.count < trialCount { plan += events }
        plan = Array(plan.prefix(trialCount)).shuffled()
        SpikeLog.shared.write(["type": "hapticTestStart", "set": set.name, "trials": trialCount, "events": events.map(\.rawValue)])
        task = Task { @MainActor in
            status = "Start moving. First tap in 10 s"
            try? await Task.sleep(for: .seconds(10))
            for (i, event) in plan.enumerated() {
                if Task.isCancelled { return }
                status = "Trial \(i + 1)/\(plan.count)"
                current = event
                answered = nil
                playedAt = Date()
                awaitingAnswer = true
                HapticPlayer.play(set.pattern(event))
                // Wait up to 8 s for an answer.
                var waited = 0.0
                while answered == nil, waited < 8, !Task.isCancelled { try? await Task.sleep(for: .milliseconds(100)); waited += 0.1 }
                awaitingAnswer = false
                let answer: HapticEvent? = answered ?? nil
                let reaction = answer == nil ? nil : Int(Date().timeIntervalSince(playedAt) * 1000)
                let trial = Trial(played: event, answer: answer, reactionMs: reaction)
                trials.append(trial)
                SpikeLog.shared.write(["type": "hapticTrial", "set": set.name, "played": event.rawValue,
                                       "answer": answer?.rawValue ?? "none", "correct": trial.correct, "reactionMs": reaction ?? -1])
                try? await Task.sleep(for: .seconds(Double.random(in: 6...10)))
            }
            running = false
            status = "Done: \(correctCount)/\(trials.count) correct"
            SpikeLog.shared.write(["type": "hapticTestEnd", "set": set.name, "correct": correctCount, "total": trials.count])
        }
    }

    func answer(_ event: HapticEvent) {
        guard awaitingAnswer, answered == nil else { return }
        answered = .some(event)
        // Reaction time is measured when the loop resumes — within 100 ms, close enough.
    }

    func cancel() {
        task?.cancel(); task = nil
        running = false; awaitingAnswer = false
    }

    func perEvent() -> [(HapticEvent, Int, Int)] {
        HapticEvent.allCases.compactMap { e in
            let t = trials.filter { $0.played == e }
            return t.isEmpty ? nil : (e, t.filter(\.correct).count, t.count)
        }
    }
}
