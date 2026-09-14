//
//  StoreScreen.swift
//  ThatWay
//

import SwiftUI

struct StoreScreen: View {
    @EnvironmentObject var app: AppModel

    var body: some View {
        let theme = app.currentTheme

        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Store").font(.system(size: 24, weight: .black))
                Text(blurb).font(.system(size: 13, weight: .semibold)).foregroundStyle(theme.ink.opacity(0.68))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.top, 10)

            HStack(spacing: 6) {
                ForEach(StoreTab.allCases) { tab in
                    Button {
                        app.storeTab = tab
                    } label: {
                        Text(tab.label)
                            .font(.system(size: 13, weight: .heavy))
                            .foregroundStyle(theme.ink)
                            .opacity(app.storeTab == tab ? 1 : 0.5)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(RoundedRectangle(cornerRadius: 14).fill(app.storeTab == tab ? theme.accent.opacity(0.2) : theme.ink.opacity(0.04)))
                            .overlay(RoundedRectangle(cornerRadius: 14).stroke(app.storeTab == tab ? theme.accent.opacity(0.45) : theme.ink.opacity(0.09)))
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)

            ScrollView {
                switch app.storeTab {
                case .themes: themesList(theme: theme)
                case .skins: skinsGrid(theme: theme)
                case .donate: donateList(theme: theme)
                }
            }
            .padding(.bottom, 94)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(.top, 62)
        .background(theme.screen)
    }

    private var blurb: String {
        switch app.storeTab {
        case .donate: return "Optional, always. Prices in AUD."
        case .themes: return "Every theme is free and repaints the whole app."
        case .skins: return "Three skins free, the rest a few dollars in AUD."
        }
    }

    @ViewBuilder
    private func themesList(theme: AppTheme) -> some View {
        VStack(spacing: 12) {
            ForEach(AppTheme.all) { th in
                Button { app.setTheme(th.id) } label: {
                    HStack(spacing: 14) {
                        HStack(spacing: 5) {
                            ForEach(th.swatches.indices, id: \.self) { i in
                                RoundedRectangle(cornerRadius: 7).fill(th.swatches[i]).frame(width: 22, height: 44)
                            }
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            Text(th.name).font(.system(size: 15, weight: .heavy)).foregroundStyle(theme.ink)
                            Text(th.note).font(.system(size: 12, weight: .semibold)).foregroundStyle(theme.ink.opacity(0.68))
                        }
                        Spacer()
                        Text(app.theme == th.id ? "ACTIVE" : "FREE")
                            .font(.system(size: 11, weight: .heavy)).tracking(0.7)
                            .foregroundStyle(app.theme == th.id ? theme.accent : theme.ink.opacity(0.45))
                    }
                    .padding(16)
                    .background(RoundedRectangle(cornerRadius: 20).fill(theme.ink.opacity(0.05)))
                    .overlay(RoundedRectangle(cornerRadius: 20).stroke(app.theme == th.id ? theme.accent.opacity(0.4) : theme.ink.opacity(0.09)))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
    }

    @ViewBuilder
    private func skinsGrid(theme: AppTheme) -> some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            ForEach(Skin.all) { sk in
                let owned = app.ownedSkins.contains(sk.id)
                let equipped = app.skin == sk.id
                Button { app.pickSkin(sk.id) } label: {
                    VStack(spacing: 12) {
                        ZStack {
                            Circle()
                                .fill(RadialGradient(colors: [theme.dialA, theme.dialB], center: .init(x: 0.5, y: 0.3), startRadius: 0, endRadius: 44))
                                .overlay(Circle().stroke(theme.ink.opacity(0.12)))
                            if sk.hasArt, let glyph = sk.glyph {
                                Text(glyph).font(.system(size: 30, weight: .heavy)).foregroundStyle(theme.accent)
                            } else {
                                ZStack {
                                    DiagonalHatch(color: theme.ink.opacity(0.08))
                                    Text("3D asset\nplaceholder")
                                        .font(.system(size: 9, design: .monospaced))
                                        .foregroundStyle(theme.ink.opacity(0.68))
                                        .multilineTextAlignment(.center)
                                }
                                .clipShape(Circle())
                            }
                        }
                        .frame(width: 88, height: 88)

                        VStack(spacing: 6) {
                            Text(sk.name).font(.system(size: 14, weight: .heavy)).foregroundStyle(theme.ink)
                            Text(equipped ? "EQUIPPED" : owned ? (sk.price > 0 ? "OWNED" : "FREE") : app.aud(sk.price))
                                .font(.system(size: 11, weight: .heavy)).tracking(0.5)
                                .foregroundStyle(equipped ? theme.accent : owned ? theme.ink.opacity(0.45) : theme.accent)
                        }
                    }
                    .padding(.horizontal, 14).padding(.vertical, 16)
                    .frame(maxWidth: .infinity)
                    .background(RoundedRectangle(cornerRadius: 20).fill(theme.ink.opacity(0.05)))
                    .overlay(RoundedRectangle(cornerRadius: 20).stroke(equipped ? theme.accent.opacity(0.4) : theme.ink.opacity(0.09)))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
    }

    @ViewBuilder
    private func donateList(theme: AppTheme) -> some View {
        VStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Navigation is free, forever, no ads").font(.system(size: 15, weight: .heavy)).foregroundStyle(theme.accent)
                Text("Every theme is free too. Tips and a few paid skins cover map tiles and the server bill.")
                    .font(.system(size: 13, weight: .semibold)).foregroundStyle(theme.ink.opacity(0.76))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(18)
            .background(RoundedRectangle(cornerRadius: 20).fill(theme.accent.opacity(0.12)))
            .overlay(RoundedRectangle(cornerRadius: 20).stroke(theme.accent.opacity(0.32)))

            ForEach(tips, id: \.amount) { tip in
                HStack(spacing: 14) {
                    Text(tip.amount)
                        .font(.system(size: 14, weight: .heavy)).foregroundStyle(theme.accent)
                        .frame(width: 54, height: 44)
                        .background(RoundedRectangle(cornerRadius: 14).fill(theme.accent.opacity(0.16)))
                    VStack(alignment: .leading, spacing: 3) {
                        Text(tip.name).font(.system(size: 14, weight: .heavy)).foregroundStyle(theme.ink)
                        Text(tip.note).font(.system(size: 12, weight: .semibold)).foregroundStyle(theme.ink.opacity(0.68))
                    }
                    Spacer()
                }
                .padding(16)
                .background(RoundedRectangle(cornerRadius: 18).fill(theme.ink.opacity(0.05)))
                .overlay(RoundedRectangle(cornerRadius: 18).stroke(theme.ink.opacity(0.1)))
            }

            Text("All prices in AUD. Tips are one-off and unlock nothing — the app is the same either way.")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(theme.ink.opacity(0.6))
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(16)
    }

    private let tips: [(amount: String, name: String, note: String)] = [
        ("$5", "A flat white", "One-off, no strings."),
        ("$15", "A month of tiles", "Covers map data for a while."),
        ("$40", "Patron", "Your name on the About page, if you want it."),
    ]
}

private struct DiagonalHatch: View {
    let color: Color
    var body: some View {
        Canvas { ctx, size in
            let step: CGFloat = 10
            var x: CGFloat = -size.height
            while x < size.width {
                var p = Path()
                p.move(to: CGPoint(x: x, y: 0))
                p.addLine(to: CGPoint(x: x + size.height, y: size.height))
                ctx.stroke(p, with: .color(color), lineWidth: 4)
                x += step
            }
        }
    }
}
