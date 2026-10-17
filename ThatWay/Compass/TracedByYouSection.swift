//
//  TracedByYouSection.swift
//  ThatWay
//
//  The "who can trace you" row on the You tab: a horizontal strip with one card per person, saying who they are, how long they
//  may trace you, when they last looked and roughly how far away they were, and a Stop button that always works at once.
//  Requests waiting for an answer sit in the same strip, first.
//
//  Only the traced person ever sees this. The tracer is never shown how long they have.
//

import SwiftUI
import ThatWayCore
import ThatWayUI

struct TracedByYouSection: View {
    @ObservedObject var trace: TraceManager
    let theme: AppTheme
    let review: (IncomingTrace) -> Void
    let safety: (Friend) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("WHO CAN TRACE YOU").font(.nunito(10, .extraBold)).tracking(1.8).foregroundStyle(theme.ink.opacity(0.68))
            if trace.incoming.isEmpty && trace.watchers.isEmpty {
                Text("Nobody can trace you right now. If a friend asks, you decide: how long, and whether at all.")
                    .font(.nunito(12, .semibold)).foregroundStyle(theme.textSecondary)
                    .padding(14).frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 16).fill(theme.ink.opacity(0.05)))
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 10) {
                        ForEach(trace.incoming) { request in requestCard(request) }
                        ForEach(trace.watchers) { watcher in watcherCard(watcher) }
                    }
                    .padding(.vertical, 2)
                }
                .scrollClipDisabled()
                if trace.watchers.count > 1 {
                    Button { Task { await trace.revokeAll() } } label: {
                        Text("STOP EVERYONE").font(.nunito(11, .black)).tracking(0.6).foregroundStyle(theme.needleRed)
                            .padding(.horizontal, 14).padding(.vertical, 8)
                            .background(Capsule().fill(theme.needleRed.opacity(0.1)))
                    }
                    .buttonStyle(.plain)
                }
            }
            if let message = trace.errorMessage {
                Text(message).font(.nunito(12, .extraBold)).foregroundStyle(theme.needleRed)
            }
        }
    }

    // MARK: Cards

    private func requestCard(_ request: IncomingTrace) -> some View {
        card {
            header(request.friend)
            Text("Wants to trace you")
                .font(.nunito(12, .extraBold)).foregroundStyle(theme.ink).fixedSize(horizontal: false, vertical: true)
            Text("Up to \(TraceWindow.label(hours: request.requestedHours))").font(.nunito(12, .semibold)).foregroundStyle(theme.textSecondary)
            if let expires = request.expiresAt {
                Text("Asked you; goes away in \(TraceWindow.remaining(until: expires, now: Date()))").font(.nunito(11, .semibold)).foregroundStyle(theme.textSecondary)
            }
            Spacer(minLength: 4)
            Button { review(request) } label: {
                Text("REVIEW").font(.nunito(12, .black)).tracking(0.6).foregroundStyle(theme.onAccent)
                    .frame(maxWidth: .infinity).padding(.vertical, 9)
                    .background(Capsule().fill(theme.accent))
            }
            .buttonStyle(.plain)
        }
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(theme.accent.opacity(0.7), lineWidth: 1.5))
    }

    private func watcherCard(_ watcher: Watcher) -> some View {
        card {
            HStack(alignment: .top) {
                header(watcher.friend)
                Spacer(minLength: 0)
                Menu {
                    Button("Block or report \(watcher.friend.username)…", role: .destructive) { safety(watcher.friend) }
                } label: {
                    Image(systemName: "ellipsis.circle").font(.system(size: 18)).foregroundStyle(theme.ink.opacity(0.6)).frame(width: 30, height: 30)
                }
                .accessibilityLabel("More about \(watcher.friend.username)")
            }
            Text("Can trace you until \(watcher.until.formatted(date: .omitted, time: .shortened))")
                .font(.nunito(12, .extraBold)).foregroundStyle(theme.ink).fixedSize(horizontal: false, vertical: true)
            Text("\(TraceWindow.remaining(until: watcher.until, now: Date())) left · \(watcher.kind == .oneoff ? "just this once" : "keeps tracing")")
                .font(.nunito(11, .semibold)).foregroundStyle(theme.textSecondary)
            if let looked = watcher.lastLookedAt {
                Text("Last looked \(TraceWindow.remaining(until: Date(), now: looked)) ago" + (watcher.band.map { ", \($0)" } ?? ""))
                    .font(.nunito(11, .semibold)).foregroundStyle(theme.textSecondary)
            } else {
                Text("Hasn’t looked yet").font(.nunito(11, .semibold)).foregroundStyle(theme.textSecondary)
            }
            Spacer(minLength: 4)
            Button { Task { await trace.revoke(watcher) } } label: {
                Text("STOP").font(.nunito(12, .black)).tracking(0.6).foregroundStyle(theme.needleRed)
                    .frame(maxWidth: .infinity).padding(.vertical, 9)
                    .background(Capsule().fill(theme.needleRed.opacity(0.12)))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Stop \(watcher.friend.username) tracing you")
        }
    }

    private func header(_ friend: Friend) -> some View {
        HStack(spacing: 8) {
            ZStack {
                Circle().fill(friend.color).frame(width: 34, height: 34)
                Text(friend.initials).font(.nunito(12, .extraBold)).foregroundStyle(Color(hex: "241A14"))
            }
            Text(friend.username).font(.nunito(14, .extraBold)).foregroundStyle(theme.ink).lineLimit(1)
        }
    }

    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) { content() }
            .padding(12)
            .frame(width: 214, height: 176, alignment: .topLeading)
            .background(RoundedRectangle(cornerRadius: 18).fill(theme.ink.opacity(0.05)))
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(theme.ink.opacity(0.09)))
    }
}
