//
//  StoreScreen.swift
//  ThatWay
//

import SwiftUI
import ThatWayUI

struct StoreScreen: View {
    @EnvironmentObject var app: AppModel
    @State private var customAmount = ""
    @State private var showAllSkins = false
    @FocusState private var customFocused: Bool

    private let tips: [(amount: String, name: String)] = [
        ("$5", "A flat white"),
        ("$15", "A month of tiles"),
        ("$40", "Patron"),
    ]

    var body: some View {
        let theme = app.currentTheme

        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Store").font(.nunito(24, .black))
                Text("Navigation is free, forever, no ads. Prices in AUD.")
                    .font(.nunito(13, .semibold)).foregroundStyle(theme.ink.opacity(0.68))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.top, 10)

            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    donateSection(theme: theme)
                    themesSection(theme: theme)
                    skinsSection(theme: theme)
                }
                .padding(.horizontal, 16)
                .padding(.top, 18)
                .padding(.bottom, 100)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(.top, 8)
        .background(theme.screen)
        .sheet(isPresented: $showAllSkins) { allSkinsSheet }
    }

    private func sectionLabel(_ text: String, theme: AppTheme) -> some View {
        Text(text).font(.nunito(10, .extraBold)).tracking(1.8).foregroundStyle(theme.ink.opacity(0.68))
    }

    // MARK: Donate

    @ViewBuilder
    private func donateSection(theme: AppTheme) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionLabel("DONATE", theme: theme)
            HStack(spacing: 10) {
                ForEach(tips, id: \.amount) { tip in
                    Button {} label: {
                        VStack(spacing: 4) {
                            Text(tip.amount).font(.nunito(20, .black)).foregroundStyle(theme.accent)
                            Text(tip.name).font(.nunito(11, .semibold)).foregroundStyle(theme.ink.opacity(0.7))
                                .lineLimit(1).minimumScaleFactor(0.8)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(RoundedRectangle(cornerRadius: 18).fill(theme.accent.opacity(0.12)))
                        .overlay(RoundedRectangle(cornerRadius: 18).stroke(theme.accent.opacity(0.32)))
                    }
                    .buttonStyle(.plain)
                }
            }
            HStack(spacing: 10) {
                HStack(spacing: 6) {
                    Text("$").font(.nunito(16, .extraBold)).foregroundStyle(theme.ink.opacity(0.6))
                    TextField("Custom amount", text: $customAmount)
                        .keyboardType(.decimalPad)
                        .focused($customFocused)
                        .font(.nunito(15, .semibold))
                }
                .padding(.horizontal, 14).frame(height: 46)
                .background(RoundedRectangle(cornerRadius: 14).fill(theme.ink.opacity(0.05)))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(theme.ink.opacity(0.1)))

                Button { customFocused = false } label: {
                    Text("DONATE")
                        .font(.nunito(12, .black)).tracking(0.6)
                        .foregroundStyle(theme.onAccent)
                        .padding(.horizontal, 18).frame(height: 46)
                        .background(RoundedRectangle(cornerRadius: 14).fill(theme.accent))
                        .opacity(customAmount.isEmpty ? 0.5 : 1)
                }
                .buttonStyle(.plain)
                .disabled(customAmount.isEmpty)
            }
            Text("Tips can be one-off or recurring. Enjoying the app? Consider leaving a review on the App Store!")
                .font(.nunito(11, .semibold)).foregroundStyle(theme.ink.opacity(0.6))
        }
    }

    // MARK: Themes

    @ViewBuilder
    private func themesSection(theme: AppTheme) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionLabel("THEMES", theme: theme)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(AppTheme.all) { th in
                        Button { app.setTheme(th.id) } label: {
                            VStack(alignment: .leading, spacing: 12) {
                                HStack(spacing: 5) {
                                    ForEach(th.swatches.indices, id: \.self) { i in
                                        RoundedRectangle(cornerRadius: 7).fill(th.swatches[i]).frame(width: 22, height: 44)
                                    }
                                }
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(th.name).font(.nunito(15, .extraBold)).foregroundStyle(theme.ink)
                                    Text(app.theme == th.id ? "ACTIVE" : "FREE")
                                        .font(.nunito(11, .extraBold)).tracking(0.7)
                                        .foregroundStyle(app.theme == th.id ? theme.accent : theme.ink.opacity(0.45))
                                }
                            }
                            .padding(16)
                            .frame(width: 150, alignment: .leading)
                            .background(RoundedRectangle(cornerRadius: 20).fill(theme.ink.opacity(0.05)))
                            .overlay(RoundedRectangle(cornerRadius: 20).stroke(app.theme == th.id ? theme.accent.opacity(0.4) : theme.ink.opacity(0.09)))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 1)
            }
        }
    }

    // MARK: Skins

    @ViewBuilder
    private func skinsSection(theme: AppTheme) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                sectionLabel("SKINS", theme: theme)
                Spacer()
                Button { showAllSkins = true } label: {
                    Text("MORE")
                        .font(.nunito(11, .black)).tracking(0.8)
                        .foregroundStyle(theme.accent)
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(Capsule().fill(theme.accent.opacity(0.14)))
                }
                .buttonStyle(.plain)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(Skin.all) { sk in
                        skinCard(sk, theme: theme).frame(width: 140)
                    }
                }
                .padding(.horizontal, 1)
            }
        }
    }

    private var allSkinsSheet: some View {
        let theme = app.currentTheme
        return NavigationStack {
            ScrollView {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    ForEach(Skin.all) { sk in skinCard(sk, theme: theme, dismissOnPick: true) }
                }
                .padding(16)
            }
            .background(theme.screen)
            .navigationTitle("Skins")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showAllSkins = false } } }
        }
        .presentationDetents([.large])
        .preferredColorScheme(theme.light ? .light : .dark)
    }

    @ViewBuilder
    private func skinCard(_ sk: Skin, theme: AppTheme, dismissOnPick: Bool = false) -> some View {
        let owned = app.ownedSkins.contains(sk.id)
        let equipped = app.skin == sk.id
        Button {
            app.pickSkin(sk.id)
            if dismissOnPick { showAllSkins = false }
        } label: {
            VStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(RadialGradient(colors: [theme.dialA, theme.dialB], center: .init(x: 0.5, y: 0.3), startRadius: 0, endRadius: 44))
                        .overlay(Circle().stroke(theme.ink.opacity(0.12)))
                    if sk.hasArt, let glyph = sk.glyph {
                        Text(glyph).font(.nunito(30, .extraBold)).foregroundStyle(theme.accent)
                    } else {
                        ZStack {
                            DiagonalHatch(color: theme.ink.opacity(0.08))
                            Text("3D asset\nplaceholder")
                                .font(.system(.caption2, design: .monospaced))
                                .foregroundStyle(theme.ink.opacity(0.68))
                                .multilineTextAlignment(.center)
                        }
                        .clipShape(Circle())
                    }
                }
                .frame(width: 88, height: 88)

                VStack(spacing: 6) {
                    Text(sk.name).font(.nunito(14, .extraBold)).foregroundStyle(theme.ink)
                    Text(equipped ? "EQUIPPED" : owned ? (sk.price > 0 ? "OWNED" : "FREE") : app.aud(sk.price))
                        .font(.nunito(11, .extraBold)).tracking(0.5)
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
