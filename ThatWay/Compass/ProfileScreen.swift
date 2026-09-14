//
//  ProfileScreen.swift
//  ThatWay
//

import SwiftUI

struct ProfileScreen: View {
    @EnvironmentObject var app: AppModel

    var body: some View {
        let theme = app.currentTheme

        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header(theme: theme)
                visibilitySection(theme: theme)
                achievementsSection(theme: theme)
                settingsSection(theme: theme)
                donateBanner(theme: theme)
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 100)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(.top, 62)
        .background(theme.screen)
    }

    @ViewBuilder
    private func header(theme: AppTheme) -> some View {
        HStack(spacing: 14) {
            Button { app.avatarSheet = true } label: {
                ZStack(alignment: .bottomTrailing) {
                    Circle()
                        .fill(app.currentAvatar.bg)
                        .frame(width: 64, height: 64)
                        .overlay(Text(app.currentAvatar.glyph).font(.system(size: 22, weight: .black)).foregroundStyle(Color(hex: "241A14")))
                    ZStack {
                        Circle().fill(theme.accent).frame(width: 24, height: 24)
                            .overlay(Circle().stroke(theme.screen, lineWidth: 2))
                        Text("+").font(.system(size: 13, weight: .black)).foregroundStyle(theme.onAccent)
                    }
                }
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 4) {
                Text("You").font(.system(size: 20, weight: .black))
                Text(visLine).font(.system(size: 13, weight: .semibold)).foregroundStyle(theme.ink.opacity(0.68))
                Button { app.avatarSheet = true } label: {
                    Text("EDIT PICTURE & AVATARS")
                        .font(.system(size: 11, weight: .heavy)).tracking(0.6)
                        .foregroundStyle(theme.accent)
                }
                .padding(.top, 4)
            }
        }
    }

    private var visLine: String {
        switch app.vis {
        case .nobody: return "Invisible on the map"
        case .close: return "Visible to close ones within \(Int(app.closeKm)) km"
        case .friends: return "Visible to friends"
        }
    }

    @ViewBuilder
    private func visibilitySection(theme: AppTheme) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("VISIBLE TO").font(.system(size: 10, weight: .heavy)).tracking(1.8).foregroundStyle(theme.ink.opacity(0.68))
            HStack(spacing: 6) {
                ForEach(Visibility.allCases) { v in
                    Button { app.vis = v } label: {
                        Text(v.rawValue)
                            .font(.system(size: 13, weight: .heavy))
                            .foregroundStyle(theme.ink)
                            .opacity(app.vis == v ? 1 : 0.45)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 9)
                            .background(RoundedRectangle(cornerRadius: 12).fill(app.vis == v ? theme.accent.opacity(0.22) : .clear))
                    }
                }
            }
            .padding(4)
            .background(RoundedRectangle(cornerRadius: 16).fill(theme.ink.opacity(0.05)))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(theme.ink.opacity(0.09)))

            if app.vis == .close {
                VStack(spacing: 12) {
                    HStack {
                        Text("Close ones within").font(.system(size: 12, weight: .semibold)).foregroundStyle(theme.ink.opacity(0.7))
                        Spacer()
                        Text("\(Int(app.closeKm)) km").font(.system(size: 15, weight: .black)).foregroundStyle(theme.accent)
                    }
                    Slider(value: $app.closeKm, in: 2...20, step: 1).tint(theme.accent)
                    HStack {
                        Text("2 km").font(.system(size: 10, weight: .semibold)).foregroundStyle(theme.ink.opacity(0.6))
                        Spacer()
                        Text("20 km").font(.system(size: 10, weight: .semibold)).foregroundStyle(theme.ink.opacity(0.6))
                    }
                }
                .padding(14)
                .background(RoundedRectangle(cornerRadius: 18).fill(theme.ink.opacity(0.05)))
                .overlay(RoundedRectangle(cornerRadius: 18).stroke(theme.ink.opacity(0.09)))
            }
        }
    }

    @ViewBuilder
    private func achievementsSection(theme: AppTheme) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("ACHIEVEMENTS").font(.system(size: 10, weight: .heavy)).tracking(1.8).foregroundStyle(theme.ink.opacity(0.68))
            HStack(spacing: 10) {
                badge("✦", "First 10 km", 1, theme: theme)
                badge("◔", "Dawn run", 1, theme: theme)
                badge("◇", "No wrong turns", 0.4, theme: theme)
            }
        }
    }

    @ViewBuilder
    private func badge(_ glyph: String, _ name: String, _ op: Double, theme: AppTheme) -> some View {
        VStack(spacing: 8) {
            Circle()
                .strokeBorder(theme.accent, lineWidth: 2)
                .frame(width: 34, height: 34)
                .overlay(Text(glyph).font(.system(size: 14, weight: .heavy)).foregroundStyle(theme.accent))
            Text(name).font(.system(size: 10, weight: .semibold)).foregroundStyle(theme.ink.opacity(0.78)).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14).padding(.horizontal, 10)
        .background(RoundedRectangle(cornerRadius: 18).fill(theme.ink.opacity(0.05)))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(theme.ink.opacity(0.09)))
        .opacity(op)
    }

    @ViewBuilder
    private func settingsSection(theme: AppTheme) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("SETTINGS").font(.system(size: 10, weight: .heavy)).tracking(1.8).foregroundStyle(theme.ink.opacity(0.68))
            VStack(spacing: 0) {
                settingsRow("Compass skin", value: app.currentSkin.name,
                            options: Skin.all.filter { app.ownedSkins.contains($0.id) }.map(\.name), theme: theme) { v in
                    if let id = Skin.all.first(where: { $0.name == v })?.id { app.skin = id }
                }
                settingsRow("Theme", value: theme.name, options: AppTheme.all.map(\.name), theme: theme) { v in
                    if let id = AppTheme.all.first(where: { $0.name == v })?.id { app.setTheme(id) }
                }
                settingsRow("Voice of directions", value: app.opts.voice, options: ["Friendly", "Terse", "Cheeky"], theme: theme) { app.opts.voice = $0 }
                settingsRow("Activity detection", value: app.opts.activity, options: ["Automatic", "Walking", "Running", "Driving"], theme: theme) { app.opts.activity = $0 }
                settingsRow("Haptics on turns", value: app.opts.haptics, options: ["Off", "Light", "Strong"], theme: theme) { app.opts.haptics = $0 }
                settingsRow("Share destination", value: app.opts.share, options: ["Off", "Friends only", "Everyone"], theme: theme) { app.opts.share = $0 }
                settingsRow("Units", value: app.opts.units, options: ["Kilometres", "Miles"], theme: theme, isLast: true) { app.opts.units = $0 }
            }
            .background(RoundedRectangle(cornerRadius: 20).fill(theme.ink.opacity(0.05)))
            .overlay(RoundedRectangle(cornerRadius: 20).stroke(theme.ink.opacity(0.09)))
        }
    }

    @ViewBuilder
    private func settingsRow(_ label: String, value: String, options: [String], theme: AppTheme, isLast: Bool = false, onChange: @escaping (String) -> Void) -> some View {
        VStack(spacing: 0) {
            HStack {
                Text(label).font(.system(size: 15, weight: .semibold)).foregroundStyle(theme.ink)
                Spacer()
                Menu {
                    ForEach(options, id: \.self) { opt in
                        Button(opt) { onChange(opt) }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Text(value).font(.system(size: 13, weight: .bold)).foregroundStyle(theme.ink)
                        Image(systemName: "chevron.down").font(.system(size: 9, weight: .bold)).foregroundStyle(theme.ink.opacity(0.5))
                    }
                    .padding(.horizontal, 12).padding(.vertical, 9)
                    .background(RoundedRectangle(cornerRadius: 11).fill(theme.ink.opacity(0.08)))
                    .overlay(RoundedRectangle(cornerRadius: 11).stroke(theme.ink.opacity(0.12)))
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 13)
            if !isLast {
                Divider().background(theme.ink.opacity(0.07)).padding(.leading, 16)
            }
        }
    }

    @ViewBuilder
    private func donateBanner(theme: AppTheme) -> some View {
        Button { app.goDonate() } label: {
            VStack(alignment: .leading, spacing: 6) {
                Text("Free forever, no ads").font(.system(size: 15, weight: .heavy)).foregroundStyle(theme.accent)
                Text("If the compass made a commute better, you can throw a few dollars at it.")
                    .font(.system(size: 13, weight: .semibold)).foregroundStyle(theme.ink.opacity(0.76))
                Text("LEAVE A TIP")
                    .font(.system(size: 12, weight: .black)).tracking(0.6)
                    .foregroundStyle(theme.onAccent)
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    .background(RoundedRectangle(cornerRadius: 13).fill(theme.accent))
                    .padding(.top, 8)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(18)
            .background(RoundedRectangle(cornerRadius: 20).fill(theme.accent.opacity(0.12)))
            .overlay(RoundedRectangle(cornerRadius: 20).stroke(theme.accent.opacity(0.32)))
        }
        .buttonStyle(.plain)
    }
}
