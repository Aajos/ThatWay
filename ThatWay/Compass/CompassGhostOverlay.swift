//
//  CompassGhostOverlay.swift
//  ThatWay
//
//  Drawn over the dial while the phone's compass disagrees with the direction of travel (see
//  `CompassHealth`): a translucent "ghost" compass whose north marker sits where north would be if
//  the phone pointed the way you're walking, plus a button to restart the compass. Only exists
//  while the compass is suspect, so it costs nothing the rest of the time.
//

import SwiftUI
import ThatWayUI

struct CompassGhostOverlay: View {
    let theme: AppTheme
    /// GPS direction of travel, degrees clockwise from north.
    let predicted: Double?
    let recalibrating: Bool
    let size: CGFloat
    let onRecalibrate: () -> Void
    let onUseGPS: () -> Void

    var body: some View {
        let k = size / 286
        ZStack {
            Circle().fill(theme.screen.opacity(0.86))

            Circle()
                .strokeBorder(theme.accent.opacity(0.9), style: StrokeStyle(lineWidth: 3 * k, dash: [7 * k, 8 * k]))

            // Where north would be if the phone were pointing along your direction of travel.
            if let predicted {
                Text("N")
                    .font(.nunito(18 * k, .black))
                    .foregroundStyle(theme.onAccent)
                    .frame(width: 30 * k, height: 30 * k)
                    .background(Circle().fill(theme.accent))
                    .offset(y: -(size / 2 - 16 * k))
                    .rotationEffect(.degrees(-predicted))
            }

            VStack(spacing: 8 * k) {
                if recalibrating {
                    ProgressView().controlSize(.small)
                    Text("Wave your phone in a figure-8")
                        .font(.nunito(14 * k, .extraBold)).foregroundStyle(theme.ink)
                        .multilineTextAlignment(.center)
                } else {
                    Text("Compass may be off")
                        .font(.nunito(15 * k, .black)).foregroundStyle(theme.ink)
                    Text("It disagrees with the way you're moving. The cards are still right.")
                        .font(.nunito(11.5 * k, .semibold)).foregroundStyle(theme.textSecondary)
                        .multilineTextAlignment(.center)
                    Button(action: onRecalibrate) {
                        Text("RECALIBRATE COMPASS")
                            .font(.nunito(12 * k, .black)).tracking(0.5)
                            .foregroundStyle(theme.onAccent)
                            .padding(.horizontal, 14 * k).padding(.vertical, 9 * k)
                            .background(Capsule().fill(theme.accent))
                    }
                    .buttonStyle(.plain)
                    Button(action: onUseGPS) {
                        Text("USE GPS DIRECTION")
                            .font(.nunito(11 * k, .black)).tracking(0.5)
                            .foregroundStyle(theme.accent)
                            .padding(.horizontal, 12 * k).padding(.vertical, 7 * k)
                            .background(Capsule().fill(theme.tint(0.14)))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 34 * k)
        }
        .frame(width: size, height: size)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Compass may be off")
    }
}

/// Shown instead of the big overlay once the dial is being steered by GPS direction.
struct GPSDirectionChip: View {
    let theme: AppTheme
    let onUndo: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "location.north.line.fill").font(.system(size: 12, weight: .bold)).foregroundStyle(theme.accent)
            Text("Using GPS direction").font(.nunito(12, .extraBold)).foregroundStyle(theme.ink)
            Button(action: onUndo) {
                Text("UNDO").font(.nunito(11, .black)).tracking(0.5).foregroundStyle(theme.accent)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12).padding(.vertical, 7)
        .background(Capsule().fill(theme.screen.opacity(0.92)))
        .overlay(Capsule().stroke(theme.outline(0.5)))
    }
}
