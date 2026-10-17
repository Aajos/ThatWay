//
//  TracePill.swift
//  ThatWay
//
//  The temporary pill that takes the friends row's place while YOU are tracing someone:
//
//    waiting   you  ->  waiting for them  ->  them
//    active    you  ->  arrow + distance  ->  them      "Accepted", how old their location is, request a new one
//
//  It is direction and distance only: no map, no coordinates, ever. The arrow follows the phone's heading (GPS range)
//  or the radio (Ultra Wideband, the last stretch). A tracer is never told how long they have: only "Accepted" and, when
//  anything goes wrong for any reason, "User cannot be traced, error has occurred".
//  (Requests made to YOU appear in the banner and on the You tab, not here.)
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
    var compact = false
    @ViewBuilder var row: () -> Row

    var body: some View {
        if let state = trace.state {
            TracePill(state: state, trace: trace, app: app, theme: theme, myName: myName,
                      end: { Task { await trace.end() } },
                      locate: { Task { await trace.locate(manual: true) } },
                      precise: { trace.findPrecisely() },
                      follow: { guide in trace.follow(guide: guide) },
                      stopFollowing: { trace.stopFollowing() }, compact: compact)
                .padding(.horizontal, inset)
                .transition(.opacity.combined(with: .scale(scale: 0.96)))
        } else {
            row()
        }
    }
}

struct TracePill: View {
    let state: TraceState
    @ObservedObject var trace: TraceManager
    let app: AppModel
    let theme: AppTheme
    let myName: String
    let end: () -> Void
    let locate: () -> Void
    let precise: () -> Void
    let follow: (Bool) -> Void
    let stopFollowing: () -> Void
    /// A short screen (iPhone SE): one row of small buttons instead of two, so the compass still fits under the pill.
    var compact = false

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
        case .waiting(let friend):
            HStack(spacing: 8) {
                avatar(initials: initials(myName), color: theme.accent, label: "You")
                link
                VStack(spacing: 3) {
                    ProgressView().tint(theme.accent)
                    Text("Waiting for \(friend.username) to say yes").font(.nunito(12, .extraBold)).foregroundStyle(theme.ink).lineLimit(3).multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                link
                avatar(initials: friend.initials, color: friend.color, label: friend.username)
                closeButton(label: "Cancel request", action: end)
            }
            .accessibilityLabel("Waiting for \(friend.username) to say yes to your request")

        case .active(let friend):
            let reading = trace.reading
            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    avatar(initials: initials(myName), color: theme.accent, label: "You")
                    VStack(spacing: 2) {
                        if let reading {
                            TraceArrow(app: app, location: app.locationManager, reading: reading, theme: theme)
                            Text(reading.distanceText).font(.nunito(15, .black)).foregroundStyle(theme.ink).lineLimit(1).minimumScaleFactor(0.7)
                            Text(subtitle(reading)).font(.nunito(10, .semibold)).foregroundStyle(theme.textSecondary).lineLimit(1)
                        } else if trace.noLocationYet {
                            Image(systemName: "location.slash").font(.system(size: 20, weight: .bold)).foregroundStyle(theme.textSecondary)
                            Text("\(TraceCopy.accepted). \(friend.username)’s phone hasn’t shared a location yet.")
                                .font(.nunito(11, .semibold)).foregroundStyle(theme.textSecondary).lineLimit(3).multilineTextAlignment(.center)
                        } else {
                            ProgressView().tint(theme.accent)
                            Text("\(TraceCopy.accepted). Finding \(friend.username)…").font(.nunito(11, .semibold)).foregroundStyle(theme.textSecondary).lineLimit(2).multilineTextAlignment(.center)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    avatar(initials: friend.initials, color: friend.color, label: friend.username)
                    closeButton(label: "Stop looking at \(friend.username)", action: end)
                }
                HStack(spacing: 8) {
                    if reading != nil {
                        if trace.following == friend.id {
                            chip(compact ? "Following" : "Following \(friend.username)", icon: "scope", filled: true) {}
                                .allowsHitTesting(false)
                            chip("Stop", icon: "xmark", filled: false, action: stopFollowing)
                        } else {
                            chip(compact ? "Point" : "Point me", icon: "location.north.line", filled: false) { follow(false) }
                            chip(compact ? "Guide" : "Guide me", icon: "arrowshape.turn.up.right", filled: true) { follow(true) }
                        }
                    }
                    if !compact { EmptyView() } else { locateChip }
                }
                if !compact {
                    HStack(spacing: 8) {
                        locateChip
                        if app.nearbyManager.capability.canRange, reading?.source != .uwb {
                            chip("Find precisely", icon: "dot.radiowaves.left.and.right", filled: false, action: precise)
                        }
                    }
                }
                if let ends = planLine { Text(ends).font(.nunito(10, .semibold)).foregroundStyle(theme.textSecondary) }
            }
            .accessibilityLabel(activeLabel(friend: friend, reading: reading))

        case .notice(let text):
            HStack(spacing: 8) {
                Image(systemName: "info.circle.fill").foregroundStyle(theme.accent)
                Text(text).font(.nunito(13, .extraBold)).foregroundStyle(theme.ink).lineLimit(3)
            }
        }
    }

    /// "Request new location", counting down the 2 minutes the server makes the tracer wait.
    private var locateChip: some View {
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            let wait = trace.locateCountdown()
            Button(action: locate) {
                HStack(spacing: 5) {
                    Image(systemName: "arrow.clockwise").font(.system(size: 11, weight: .bold))
                    Text(wait > 0 ? (compact ? TraceWindow.countdown(seconds: wait) : "New location in \(TraceWindow.countdown(seconds: wait))") : (compact ? "Refresh" : "Request new location"))
                        .font(.nunito(12, .extraBold)).lineLimit(1).minimumScaleFactor(0.75)
                }
                .foregroundStyle(wait > 0 ? theme.textSecondary : theme.ink)
                .padding(.horizontal, 12).padding(.vertical, 7)
                .frame(maxWidth: .infinity)
                .background(Capsule().fill(theme.ink.opacity(wait > 0 ? 0.05 : 0.1)))
            }
            .buttonStyle(.plain)
            .disabled(wait > 0)
        }
    }

    /// The tracer's own plan, when it ends within a day: the only time they are ever shown.
    private var planLine: String? {
        guard let ends = trace.planEnds, ends.timeIntervalSinceNow > 0, ends.timeIntervalSinceNow < 24 * 3600 else { return nil }
        return "Your plan ends in \(TraceWindow.remaining(until: ends, now: Date()))"
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
        case .gps:
            let age = Int(r.peerAgeSeconds ?? 0)
            let seen = age < 60 ? "just now" : age < 3600 ? "\(age / 60) min ago" : "\(age / 3600) h ago"
            return trace.justAccepted ? "\(TraceCopy.accepted) · seen \(seen)" : "Seen \(seen)"
        }
    }

    private func activeLabel(friend: Friend, reading: TraceReading?) -> String {
        guard let reading else { return "Tracing \(friend.username), finding their location" }
        return "Tracing \(friend.username), \(reading.distanceText) away, \(subtitle(reading))"
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
