//
//  Sheets.swift
//  ThatWay
//
//  Full-screen search and avatar-picker overlays.
//

import SwiftUI

struct SearchSheet: View {
    @EnvironmentObject var app: AppModel

    private let results: [(name: String, sub: String, kind: String, dist: String)] = [
        ("Sunrise Bakery", "Open until 9", "✦", "1.2 km"),
        ("Bakerman & Co.", "Closes soon", "✦", "2.4 km"),
        ("Baker Street Lot", "Parking", "P", "3.1 km"),
        ("Home", "Saved", "⌂", "6.8 km"),
    ]

    var body: some View {
        let theme = app.currentTheme
        VStack(spacing: 16) {
            HStack(spacing: 10) {
                Circle().strokeBorder(theme.accent, lineWidth: 1.5).frame(width: 13, height: 13)
                Text("bak|").font(.system(size: 15, weight: .semibold)).foregroundStyle(theme.ink)
                Spacer()
                Button("Cancel") { app.searchOpen = false }
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(theme.ink.opacity(0.72))
            }
            .padding(.horizontal, 16)
            .frame(height: 46)
            .background(Capsule().fill(theme.ink.opacity(0.08)))
            .overlay(Capsule().stroke(theme.accent.opacity(0.5)))

            VStack(spacing: 0) {
                ForEach(results, id: \.name) { r in
                    Button { app.pickPlace(r.name) } label: {
                        HStack(spacing: 14) {
                            Text(r.kind)
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(theme.ink.opacity(0.76))
                                .frame(width: 34, height: 34)
                                .background(RoundedRectangle(cornerRadius: 11).fill(theme.ink.opacity(0.08)))
                            VStack(alignment: .leading, spacing: 3) {
                                Text(r.name).font(.system(size: 15, weight: .heavy)).foregroundStyle(theme.ink)
                                Text(r.sub).font(.system(size: 12, weight: .semibold)).foregroundStyle(theme.ink.opacity(0.66))
                            }
                            Spacer()
                            Text(r.dist).font(.system(size: 12, weight: .bold)).foregroundStyle(theme.ink.opacity(0.66))
                        }
                        .padding(.vertical, 15).padding(.horizontal, 8)
                        .overlay(Divider().background(theme.ink.opacity(0.08)), alignment: .bottom)
                    }
                    .buttonStyle(.plain)
                }
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.top, 62)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(theme.screen)
    }
}

struct AvatarSheet: View {
    @EnvironmentObject var app: AppModel

    var body: some View {
        let theme = app.currentTheme
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("Your picture").font(.system(size: 20, weight: .black))
                    Spacer()
                    Button("Done") { app.avatarSheet = false }
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(theme.ink.opacity(0.72))
                }

                HStack(spacing: 10) {
                    photoOption(title: "Take a photo", subtitle: "Camera", theme: theme)
                    photoOption(title: "Choose a photo", subtitle: "From your library", theme: theme)
                }

                Text("AVATARS").font(.system(size: 10, weight: .heavy)).tracking(1.8).foregroundStyle(theme.ink.opacity(0.68))

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    ForEach(AvatarOption.all) { a in
                        let owned = app.ownedAvatars.contains(a.id)
                        let inUse = app.avatar == a.id
                        Button { app.pickAvatar(a.id) } label: {
                            VStack(spacing: 9) {
                                Circle().fill(a.bg).frame(width: 52, height: 52)
                                    .overlay(Text(a.glyph).font(.system(size: 18, weight: .black)).foregroundStyle(Color(hex: "241A14")))
                                VStack(spacing: 4) {
                                    Text(a.name).font(.system(size: 11, weight: .bold)).foregroundStyle(theme.ink)
                                    Text(inUse ? "IN USE" : owned ? (a.price > 0 ? "OWNED" : "FREE") : app.aud(a.price))
                                        .font(.system(size: 10, weight: .heavy))
                                        .foregroundStyle(inUse ? theme.accent : owned ? theme.ink.opacity(0.42) : theme.accent)
                                }
                            }
                            .padding(.vertical, 12).padding(.horizontal, 8)
                            .frame(maxWidth: .infinity)
                            .background(RoundedRectangle(cornerRadius: 18).fill(theme.ink.opacity(0.05)))
                            .overlay(RoundedRectangle(cornerRadius: 18).stroke(inUse ? theme.accent.opacity(0.45) : theme.ink.opacity(0.09)))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.bottom, 100)
            }
            .padding(.horizontal, 16)
            .padding(.top, 62)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(theme.screen)
    }

    @ViewBuilder
    private func photoOption(title: String, subtitle: String, theme: AppTheme) -> some View {
        VStack(spacing: 5) {
            Text(title).font(.system(size: 13, weight: .heavy)).foregroundStyle(theme.ink)
            Text(subtitle).font(.system(size: 11, weight: .semibold)).foregroundStyle(theme.ink.opacity(0.66))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(RoundedRectangle(cornerRadius: 18).fill(theme.ink.opacity(0.05)))
        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [4, 3])).foregroundStyle(theme.ink.opacity(0.2)))
    }
}
