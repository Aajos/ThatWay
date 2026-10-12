//
//  TracePill.swift
//  ThatWay
//
//  The temporary pill that takes the friends row's place while a trace is going on:
//
//    asking    you  ->  Request pending  ->  them
//    incoming  them ->  Accept / Decline ->  you
//    active    you  ->  arrow + distance ->  them
//
//  It is direction and distance only: no map, no coordinates, ever. The arrow follows the phone's heading (GPS range)
//  or the radio (Ultra Wideband, the last stretch). The pill is always visible while sharing, on purpose.
//

import SwiftUI
import ThatWayCore
import ThatWayUI

/// Shows the pill while a trace exists, otherwise the friends row it replaces. Observes only the trace manager, so the
/// friends row is not redrawn at heading rate.
struct TraceSlot<Row: View>: View {
    @ObservedObject var trace: TraceManager
    let app: AppModel
    let theme: AppTheme
    let myName: String
    /// The screen's side margin (the friends row brings its own, the pill needs it added).
    var inset: CGFloat = 0
    @ViewBuilder var row: () -> Row

    var body: some View {
        if let state = trace.state {
            TracePill(state: state, reading: trace.reading, following: trace.following, app: app, theme: theme, myName: myName,
                      accept: { Task { await trace.accept() } },
                      decline: { Task { await trace.decline() } },
                      end: { Task { await trace.end() } },
                      follow: { guide in trace.follow(guide: guide) },
                      stopFollowing: { trace.stopFollowing() })
                .padding(.horizontal, inset)
                .transition(.opacity.combined(with: .scale(scale: 0.96)))
        } else {
            row()
        }
    }
}

struct TracePill: View {
    let state: TraceState
    let reading: TraceReading?
    let following: String?
    let app: AppModel
    let theme: AppTheme
    let myName: String
    let accept: () -> Void
    let decline: () -> Void
    let end: () -> Void
    let follow: (Bool) -> Void
    let stopFollowing: () -> Void

    var body: some View {
        content
            .padding(.horizontal, 12).padding(.vertical, 10)
            .frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: 22).fill(theme.surface(0.07)))
            .overlay(RoundedRectangle(cornerRadius: 22).stroke(theme.accent.opacity(0.55)))
            .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var content: some View {
        switch state {
        case .asking(let friend):
            HStack(spacing: 8) {
                avatar(initials: initials(myName), color: theme.accent, label: "You")
                link
                VStack(spacing: 3) {
                    ProgressView().tint(theme.accent)
                    Text("Request pending").font(.nunito(12, .extraBold)).foregroundStyle(theme.ink).lineLimit(2).multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                link
                avatar(initials: friend.initials, color: friend.color, label: friend.username)
                closeButton(label: "Cancel request", action: end)
            }
            .accessibilityLabel("Waiting for \(friend.username) to accept your request")

        case .incoming(let friend):
            HStack(spacing: 8) {
                avatar(initials: friend.initials, color: friend.color, label: friend.username)
                link
                VStack(spacing: 6) {
                    Text("\(friend.username) wants to trace you")
                        .font(.nunito(12, .extraBold)).foregroundStyle(theme.ink)
                        .lineLimit(2).multilineTextAlignment(.center).minimumScaleFactor(0.8)
                    HStack(spacing: 8) {
                        Button(action: decline) {
                            Text("Decline").font(.nunito(12, .extraBold)).foregroundStyle(theme.ink)
                                .padding(.horizontal, 12).padding(.vertical, 7)
                                .background(Capsule().fill(theme.ink.opacity(0.1)))
                        }
                        Button(action: accept) {
                            Text("Accept").font(.nunito(12, .black)).foregroundStyle(theme.onAccent)
                                .padding(.horizontal, 14).padding(.vertical, 7)
                                .background(Capsule().fill(theme.accent))
                        }
                    }
                    .buttonStyle(.plain)
                }
                .frame(maxWidth: .infinity)
                link
                avatar(initials: initials(myName), color: theme.accent, label: "You")
            }

        case .active(let friend):
            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    avatar(initials: initials(myName), color: theme.accent, label: "You")
                    VStack(spacing: 2) {
                        if let reading {
                            TraceArrow(app: app, location: app.locationManager, reading: reading, theme: theme)
                            Text(reading.distanceText).font(.nunito(15, .black)).foregroundStyle(theme.ink).lineLimit(1).minimumScaleFactor(0.7)
                            Text(subtitle(reading)).font(.nunito(10, .semibold)).foregroundStyle(theme.textSecondary).lineLimit(1)
                        } else {
                            ProgressView().tint(theme.accent)
                            Text("Finding \(friend.username)…").font(.nunito(11, .semibold)).foregroundStyle(theme.textSecondary).lineLimit(2).multilineTextAlignment(.center)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    avatar(initials: friend.initials, color: friend.color, label: friend.username)
                    closeButton(label: "Stop tracing \(friend.username)", action: end)
                }
                if reading != nil {
                    HStack(spacing: 8) {
                        if following == friend.id {
                            chip("Following \(friend.username)", icon: "scope", filled: true) {}
                                .allowsHitTesting(false)
                            chip("Stop", icon: "xmark", filled: false, action: stopFollowing)
                        } else {
                            chip("Point me", icon: "location.north.line", filled: false) { follow(false) }
                            chip("Guide me", icon: "arrowshape.turn.up.right", filled: true) { follow(true) }
                        }
                    }
                }
            }
            .accessibilityLabel(activeLabel(friend: friend))

        case .notice(let text):
            HStack(spacing: 8) {
                Image(systemName: "info.circle.fill").foregroundStyle(theme.accent)
                Text(text).font(.nunito(13, .extraBold)).foregroundStyle(theme.ink).lineLimit(2)
            }
        }
    }

    // MARK: Pieces

    private func chip(_ title: String, icon: String, filled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon).font(.system(size: 11, weight: .bold))
                Text(title).font(.nunito(12, .extraBold)).lineLimit(1).minimumScaleFactor(0.8)
            }
            .foregroundStyle(filled ? theme.onAccent : theme.ink)
            .padding(.horizontal, 12).padding(.vertical, 7)
            .frame(maxWidth: .infinity)
            .background(Capsule().fill(filled ? theme.accent : theme.ink.opacity(0.1)))
        }
        .buttonStyle(.plain)
    }

    private var link: some View {
        Image(systemName: "arrow.right")
            .font(.system(size: 12, weight: .black))
            .foregroundStyle(theme.accent)
            .accessibilityHidden(true)
    }

    private func avatar(initials: String, color: Color, label: String) -> some View {
        ZStack {
            Circle().fill(LinearGradient(colors: [theme.accent, Color(hex: "34D6A5")], startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: 44, height: 44)
            Circle().fill(theme.screen).frame(width: 40, height: 40)
            Circle().fill(color).frame(width: 34, height: 34)
            Text(initials).font(.nunito(13, .extraBold)).foregroundStyle(Color(hex: "241A14"))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
    }

    private func closeButton(label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 22))
                .foregroundStyle(theme.textSecondary.opacity(0.7))
                .frame(minWidth: 44, minHeight: 44)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private func initials(_ name: String) -> String { String(name.prefix(2)).uppercased() }

    private func subtitle(_ r: TraceReading) -> String {
        switch r.source {
        case .uwb: return "Precise (Ultra Wideband)"
        case .gps: return r.isStale ? "Last seen \(Int(r.peerAgeSeconds ?? 0)) s ago" : "By GPS"
        }
    }

    private func activeLabel(friend: Friend) -> String {
        guard let reading else { return "Finding \(friend.username)" }
        return "Tracing \(friend.username), \(reading.distanceText) away"
    }
}

/// The arrow. Its own view so that only it observes the location manager and redraws at heading rate.
private struct TraceArrow: View {
    let app: AppModel
    @ObservedObject var location: LocationManager
    let reading: TraceReading
    let theme: AppTheme

    private final class Angle { var value = ContinuousAngle() }
    @State private var angle = Angle()

    var body: some View {
        // GPS needs a trustworthy heading to be relative to; UWB brings its own angle.
        let usable = reading.source == .uwb || location.hasReliableHeading
        let raw = usable ? reading.arrowAngle(heading: app.currentHeading) : nil
        let _ = angle.value.update(to: raw ?? 0)
        Image(systemName: "location.north.fill")
            .font(.system(size: 22, weight: .bold))
            .foregroundStyle(raw == nil ? theme.textSecondary.opacity(0.5) : theme.accent)
            .rotationEffect(.degrees(angle.value.value))
            .animation(.easeOut(duration: 0.2), value: angle.value.value)
            .accessibilityHidden(true)
    }
}
