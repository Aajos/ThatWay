//
//  SearchView.swift
//  ThatWayWatch
//
//  Swipe right on the main screen: say where you want to go. The big button opens the system dictation sheet
//  (watchOS only lets the wearer start dictation with a tap); the answer is looked up near you and a tap on a
//  result sets it as the destination and fetches a route for the current travel mode.
//

import SwiftUI
import ThatWayCore
import ThatWayUI

struct SearchView: View {
    @EnvironmentObject var model: WatchModel
    @StateObject private var search = DestinationSearch()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let theme = model.theme
        ScrollView {
            VStack(spacing: 8) {
                TextFieldLink(prompt: Text("Where to?")) {
                    HStack(spacing: 6) {
                        Image(systemName: "mic.fill").font(.system(size: 16, weight: .black))
                        Text(search.places.isEmpty && search.state == .idle ? "Say where to" : "Say another").font(.nunito(15, .black))
                    }
                    .frame(maxWidth: .infinity, minHeight: 40)
                    .foregroundStyle(theme.onAccent)
                    .background(Capsule().fill(theme.accent))
                    .glow(theme.accent.opacity(0.5), radius: 6, theme: theme)
                } onSubmit: { text in
                    Task { await search.search(text, near: model.lastFix) }
                }
                .buttonStyle(.plain)

                switch search.state {
                case .searching:
                    ProgressView().padding(.top, 6)
                case .empty:
                    note("Nothing found for \"\(search.heard)\"", theme)
                case .failed:
                    note("Search needs a connection", theme)
                case .idle:
                    if search.places.isEmpty { note("Walk, run or cycle. Swipe up or down any time to change how.", theme) }
                }

                ForEach(search.places) { place in
                    Button {
                        model.setDestination(name: place.name, coordinate: place.coordinate)
                        dismiss()
                    } label: {
                        HStack(spacing: 8) {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(place.name).font(.nunito(14, .extraBold)).foregroundStyle(theme.ink).lineLimit(2)
                                if !place.detail.isEmpty { Text(place.detail).font(.nunito(11, .semibold)).foregroundStyle(theme.textSecondary).lineLimit(1) }
                            }
                            Spacer(minLength: 2)
                            if let d = place.distance {
                                Text(CompassManager.formattedDistance(d)).font(.nunito(12, .black)).foregroundStyle(theme.accent)
                            }
                        }
                        .padding(.horizontal, 10).padding(.vertical, 7)
                        .background(RoundedRectangle(cornerRadius: 14).fill(theme.surface(0.08)))
                        .overlay(RoundedRectangle(cornerRadius: 14).stroke(theme.outline(0.35)))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 8)
        }
        .onAppear { search.reset() }
    }

    private func note(_ text: String, _ theme: AppTheme) -> some View {
        Text(text).font(.nunito(12, .semibold)).foregroundStyle(theme.textSecondary).multilineTextAlignment(.center).padding(.top, 4)
    }
}
