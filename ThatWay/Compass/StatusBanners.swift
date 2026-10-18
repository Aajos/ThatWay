//
//  StatusBanners.swift
//  ThatWay
//
//  Two banners that stay on screen, on every tab, for as long as they are true. Neither blocks anything.
//
//    TracedByBanner      "sam can trace you" / "sam is asking to trace you". Sharing your location is never invisible.
//    SharingPausedBanner "Sharing paused: location is off for ThatWay". Someone may trace you but your settings stop the phone
//                        from sharing; one tap fixes it (iOS's prompt, or Settings).
//    NoScreenLockBanner  "Your phone has no screen lock". An app passcode is a weaker protection than a phone lock, and the
//                        app keeps saying so until the person turns a real lock on.
//

import SwiftUI
import ThatWayCore
import ThatWayUI

struct StatusBanners: View {
    @ObservedObject var trace: TraceManager
    @ObservedObject var lock: ScreenLockStatus
    @ObservedObject var location: LocationManager
    let theme: AppTheme
    let openTraced: () -> Void
    let openLockHelp: () -> Void

    var body: some View {
        VStack(spacing: 6) {
            if !trace.incoming.isEmpty || !trace.watchers.isEmpty {
                TracedByBanner(trace: trace, theme: theme, action: openTraced)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
            if !trace.watchers.isEmpty, location.sharingReadiness != .ready {
                SharingPausedBanner(readiness: location.sharingReadiness, theme: theme) { location.sharingReadiness.fix(using: location) }
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
            if lock.phoneHasNoLock {
                NoScreenLockBanner(theme: theme, action: openLockHelp)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .padding(.horizontal, 12)
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: trace.incoming.count)
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: trace.watchers.count)
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: lock.phoneHasNoLock)
    }
}

struct TracedByBanner: View {
    @ObservedObject var trace: TraceManager
    let theme: AppTheme
    let action: () -> Void

    static func summary(requests: [IncomingTrace], watchers: [Watcher]) -> (text: String, urgent: Bool) {
        if let first = requests.first {
            let more = requests.count > 1 ? " and \(requests.count - 1) more are" : " is"
            return ("\(first.friend.username)\(more) asking to trace you", true)
        }
        switch watchers.count {
        case 0: return ("", false)
        case 1: return ("\(watchers[0].friend.username) can trace you", false)
        default: return ("\(watchers.count) people can trace you", false)
        }
    }

    var body: some View {
        let s = Self.summary(requests: trace.incoming, watchers: trace.watchers)
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: s.urgent ? "person.badge.clock.fill" : "location.fill.viewfinder")
                    .font(.system(size: 13, weight: .bold))
                Text(s.text).font(.nunito(12, .extraBold)).lineLimit(1).minimumScaleFactor(0.8)
                Spacer(minLength: 4)
                Text(s.urgent ? "REVIEW" : "MANAGE").font(.nunito(10, .black)).tracking(0.8)
                Image(systemName: "chevron.right").font(.system(size: 10, weight: .bold))
            }
            .foregroundStyle(s.urgent ? theme.onAccent : theme.ink)
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(Capsule().fill(s.urgent ? theme.accent : theme.needleRed.opacity(0.16)))
            .overlay(Capsule().stroke(s.urgent ? theme.accent : theme.needleRed.opacity(0.45), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(s.text + (s.urgent ? ". Review" : ". Manage who can trace you"))
    }
}

struct SharingPausedBanner: View {
    let readiness: SharingReadiness
    let theme: AppTheme
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: "location.slash.fill").font(.system(size: 13, weight: .bold))
                Text(readiness.bannerText).font(.nunito(12, .extraBold)).lineLimit(1).minimumScaleFactor(0.8)
                Spacer(minLength: 4)
                Text("FIX").font(.nunito(10, .black)).tracking(0.8)
                Image(systemName: "chevron.right").font(.system(size: 10, weight: .bold))
            }
            .foregroundStyle(theme.onAccent)
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(Capsule().fill(theme.needleRed))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(readiness.bannerText + ". " + readiness.buttonTitle)
    }
}

struct NoScreenLockBanner: View {
    let theme: AppTheme
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: "lock.open.trianglebadge.exclamationmark.fill").font(.system(size: 13, weight: .bold))
                Text("Your phone has no screen lock").font(.nunito(12, .extraBold)).lineLimit(1).minimumScaleFactor(0.8)
                Spacer(minLength: 4)
                Text("WHY").font(.nunito(10, .black)).tracking(0.8)
                Image(systemName: "chevron.right").font(.system(size: 10, weight: .bold))
            }
            .foregroundStyle(theme.ink)
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(Capsule().fill(theme.ink.opacity(0.08)))
            .overlay(Capsule().stroke(theme.ink.opacity(0.25), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Your phone has no screen lock. Tap to learn why this matters.")
    }
}

/// The explanation behind the banner: what is at stake and what to do, in order of how good each lock is.
struct ScreenLockHelpSheet: View {
    let theme: AppTheme
    let hasAppPasscode: Bool
    let close: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Image(systemName: "lock.shield.fill").font(.system(size: 34, weight: .bold)).foregroundStyle(theme.accent).accessibilityHidden(true)
                Text("Why a screen lock matters here").font(.nunito(22, .black)).foregroundStyle(theme.ink)
                Text("ThatWay lets you decide who can see where you are. Without a lock, anyone who picks up your phone could let someone trace you, or open ThatWay as you.")
                    .font(.nunito(14, .semibold)).foregroundStyle(theme.ink)
                VStack(alignment: .leading, spacing: 10) {
                    row("1", "Face ID or Touch ID", "The best protection. Turn it on in Settings, under Face ID & Passcode (or Touch ID & Passcode).")
                    row("2", "Your phone’s passcode", "Next best. Settings, Face ID & Passcode, Turn Passcode On.")
                    row("3", "A ThatWay passcode", hasAppPasscode ? "You have one set. It only guards ThatWay, not your phone, so a phone lock is still better." : "The last resort. When you allow someone to trace you, ThatWay can set one up after checking your email address. It only guards ThatWay, not your phone.")
                }
                Text("ThatWay keeps working without a lock. This reminder stays until you turn one on.")
                    .font(.nunito(12, .semibold)).foregroundStyle(theme.textSecondary)
                Button(action: close) {
                    Text("OK").font(.nunito(14, .black)).foregroundStyle(theme.onAccent)
                        .frame(maxWidth: .infinity).frame(height: 50)
                        .background(RoundedRectangle(cornerRadius: 16).fill(theme.accent))
                }
                .buttonStyle(.plain)
            }
            .padding(24)
        }
        .background(theme.screen.ignoresSafeArea())
        .presentationDetents([.large])
    }

    private func row(_ number: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(number).font(.nunito(13, .black)).foregroundStyle(theme.onAccent)
                .frame(width: 26, height: 26).background(Circle().fill(theme.accent))
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.nunito(14, .extraBold)).foregroundStyle(theme.ink)
                Text(detail).font(.nunito(13, .semibold)).foregroundStyle(theme.textSecondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
