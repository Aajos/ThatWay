//
//  NearbySheet.swift
//  ThatWay
//
//  Opened by tapping a friend on the compass screen. Shows how far away the friend is and, on phones that can tell,
//  which way: the same job as the dial, at arm's length instead of across a city. Needs both phones to have this open.
//

import SwiftUI
import ThatWayCore
import ThatWayUI

struct NearbySheet: View {
    let friend: Friend
    @EnvironmentObject var app: AppModel
    @ObservedObject var nearby: NearbyManager
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let theme = app.currentTheme
        ScrollView {
            VStack(spacing: 22) {
                Text("Find \(friend.username)")
                    .font(.nunito(22, .black)).foregroundStyle(theme.ink)
                    .multilineTextAlignment(.center)
                    .padding(.top, 28)

                content(theme: theme)

                Button { nearby.stop(); dismiss() } label: {
                    Text(isLive ? "STOP" : "CLOSE")
                        .font(.nunito(14, .black)).tracking(0.8)
                        .foregroundStyle(theme.onAccent)
                        .frame(maxWidth: .infinity).frame(height: 50)
                        .background(RoundedRectangle(cornerRadius: 16).fill(theme.accent))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 28).padding(.bottom, 40)
            .frame(maxWidth: .infinity)
        }
        .background(theme.screen.ignoresSafeArea())
        .foregroundStyle(theme.ink)
        .onAppear { if !nearby.isActive { nearby.start(with: friend) } }
        .onDisappear { nearby.stop() }
        .sensoryFeedback(.impact(weight: .medium), trigger: bandForFeedback)
    }

    private var isLive: Bool {
        switch nearby.state {
        case .connecting, .waiting, .ranging: return true
        default: return false
        }
    }

    private var bandForFeedback: Int {
        if case .ranging(let reading) = nearby.state { return reading.band.rawValue }
        return -1
    }

    @ViewBuilder
    private func content(theme: AppTheme) -> some View {
        switch nearby.state {
        case .idle, .connecting:
            status("Getting ready…", detail: "Setting up a private link with \(friend.username)’s phone.", theme: theme, spinner: true)
        case .waiting:
            status("Waiting for \(friend.username)", detail: "They need to open ThatWay and tap your picture on their compass screen. You'll connect automatically.", theme: theme, spinner: true)
        case .ranging(let reading):
            ranging(reading, theme: theme)
        case .lost:
            VStack(spacing: 14) {
                status("Connection ended", detail: "\(friend.username) left, or went out of range.", theme: theme)
                Button("Try again") { nearby.start(with: friend) }
                    .font(.nunito(14, .extraBold)).foregroundStyle(theme.accent)
            }
        case .unsupported:
            status("Not on this iPhone", detail: "Finding a friend by distance uses Ultra Wideband, which this iPhone doesn't have (iPhone 11 and later do, except the SE). A Bluetooth version for other phones is planned.", theme: theme)
        case .failed(let message):
            VStack(spacing: 14) {
                status("Couldn't connect", detail: message, theme: theme)
                Button("Try again") { nearby.start(with: friend) }
                    .font(.nunito(14, .extraBold)).foregroundStyle(theme.accent)
            }
        }
    }

    @ViewBuilder
    private func ranging(_ reading: ProximityReading, theme: AppTheme) -> some View {
        VStack(spacing: 14) {
            if let bearing = reading.relativeBearing {
                Image(systemName: "location.north.fill")
                    .font(.system(size: 84, weight: .bold))
                    .foregroundStyle(theme.accent)
                    .rotationEffect(.degrees(bearing))
                    .animation(.easeOut(duration: 0.25), value: bearing)
                    .dynamicTypeSize(...DynamicTypeSize.xxLarge)
                    .accessibilityLabel("Direction to \(friend.username)")
            }
            Text(reading.distanceText)
                .font(.nunito(48, .black)).foregroundStyle(theme.ink)
                .minimumScaleFactor(0.5).lineLimit(1)
            Text(reading.band.label)
                .font(.nunito(15, .semibold)).foregroundStyle(theme.textSecondary)
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func status(_ title: String, detail: String, theme: AppTheme, spinner: Bool = false) -> some View {
        VStack(spacing: 10) {
            if spinner { ProgressView().tint(theme.accent) }
            Text(title).font(.nunito(17, .extraBold)).foregroundStyle(theme.ink).multilineTextAlignment(.center)
            Text(detail).font(.nunito(13, .semibold)).foregroundStyle(theme.textSecondary).multilineTextAlignment(.center)
        }
    }
}
