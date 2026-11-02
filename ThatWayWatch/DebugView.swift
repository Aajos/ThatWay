//
//  DebugView.swift
//  ThatWayWatch
//
//  The Test 2 overlay: which source is in use, every raw value and the filtered heading, plus live
//  threshold tuning and the buttons that set up the test route.
//

import SwiftUI
import ThatWayUI
import ThatWayCore

struct DebugView: View {
    @EnvironmentObject var model: WatchModel
    @State private var courseEnter = 1.5
    @State private var magEnter = 0.8

    private func f(_ v: Double?, _ digits: Int = 0) -> String {
        guard let v, v >= 0 || digits > 0 else { return "–" }
        return String(format: "%.\(digits)f", v)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 3) {
                Text("SOURCE  \(model.source.rawValue.uppercased())").font(.nunito(13, .black))
                    .foregroundStyle(model.source == .gps ? .green : .orange)
                row("speed m/s", f(model.speed, 2))
                row("course °", "\(f(model.course)) ±\(f(model.courseAccuracy))")
                row("magnet °", "\(f(model.magnetometer)) ±\(f(model.magnetometerAccuracy))")
                row("filtered °", f(model.heading, 0))
                if let h = model.heading, model.course >= 0, model.speed >= 1.5 {
                    row("err vs course", String(format: "%+.0f°", AngleMath.signedDifference(h, from: model.course)))
                }
                Divider()
                tuner("GPS ≥", $courseEnter, 0.8...4) { model.blender.config.courseEnterSpeed = $0 }
                tuner("Mag <", $magEnter, 0.2...2) { model.blender.config.magnetometerEnterSpeed = $0 }
                Divider()
                Button("Set test route") { model.setTestRoute() }
                Button("Clear route") { model.clearRoute() }
                Text(model.message).font(.nunito(10, .semibold)).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 4)
        }
    }

    /// A compact − value + control (the system Stepper is far too big for this screen).
    private func tuner(_ title: String, _ value: Binding<Double>, _ range: ClosedRange<Double>, apply: @escaping (Double) -> Void) -> some View {
        HStack(spacing: 4) {
            Text("\(title) \(String(format: "%.1f", value.wrappedValue))").font(.nunito(12, .semibold)).monospacedDigit()
            Spacer(minLength: 0)
            Button("−") { value.wrappedValue = max(range.lowerBound, (value.wrappedValue - 0.1 * 1).rounded(toPlaces: 1)); apply(value.wrappedValue) }
                .frame(width: 34)
            Button("+") { value.wrappedValue = min(range.upperBound, (value.wrappedValue + 0.1).rounded(toPlaces: 1)); apply(value.wrappedValue) }
                .frame(width: 34)
        }
    }

    private func row(_ k: String, _ v: String) -> some View {
        HStack { Text(k).foregroundStyle(.secondary); Spacer(); Text(v).monospacedDigit() }.font(.nunito(12, .semibold))
    }
}

private extension Double {
    func rounded(toPlaces places: Int) -> Double { let m = pow(10.0, Double(places)); return (self * m).rounded() / m }
}
