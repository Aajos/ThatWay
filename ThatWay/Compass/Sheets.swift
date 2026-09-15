//
//  Sheets.swift
//  ThatWay
//
//  Full-screen avatar-picker overlay. (Search now lives directly on CompassScreen —
//  a persistent search bar plus a results-only panel — rather than a separate sheet.)
//

import SwiftUI

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
                    photoOption(icon: "camera", title: "Take a photo", subtitle: "Camera", theme: theme)
                    photoOption(icon: "photo.on.rectangle", title: "Choose a photo", subtitle: "From your library", theme: theme)
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
    private func photoOption(icon: String, title: String, subtitle: String, theme: AppTheme) -> some View {
        VStack(spacing: 5) {
            Image(systemName: icon).font(.system(size: 18, weight: .semibold)).foregroundStyle(theme.accent)
            Text(title).font(.system(size: 13, weight: .heavy)).foregroundStyle(theme.ink)
            Text(subtitle).font(.system(size: 11, weight: .semibold)).foregroundStyle(theme.ink.opacity(0.66))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(RoundedRectangle(cornerRadius: 18).fill(theme.ink.opacity(0.05)))
        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [4, 3])).foregroundStyle(theme.ink.opacity(0.2)))
    }
}
