//
//  CompassScreen.swift
//  ThatWay
//

import SwiftUI

struct CompassScreen: View {
    @EnvironmentObject var app: AppModel

    var body: some View {
        GeometryReader { geo in
            let k = geo.size.width / 402
            let theme = app.currentTheme
            let dialSize: CGFloat = 286 * k
            let dialCenter = CGPoint(x: geo.size.width / 2, y: geo.size.height - 300 * k)

            ZStack {
                backdrop(theme: theme, k: k, dialCenter: dialCenter)

                VStack(spacing: 0) {
                    activityPill(theme: theme)
                        .padding(.top, 66 * k)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.leading, 16 * k)

                    if !app.guiding {
                        searchAndFriends(k: k, theme: theme)
                            .padding(.top, 14 * k)
                            .padding(.horizontal, 16 * k)
                    }

                    Spacer(minLength: 0)
                }

                if app.guiding {
                    DirectionsView(k: k)
                        .environmentObject(app)
                        .frame(width: geo.size.width, height: 268 * k)
                        .position(x: geo.size.width / 2, y: 58 * k + 134 * k)
                }

                DialView(k: k)
                    .environmentObject(app)
                    .frame(width: dialSize, height: dialSize)
                    .position(dialCenter)

                VStack {
                    Spacer()
                    bottomCard(theme: theme, k: k)
                        .padding(.horizontal, 16 * k)
                        .padding(.bottom, 92 * k)
                }

                ModeToggle(k: k, dialCenter: dialCenter, bounds: geo.size)
                    .environmentObject(app)
            }
        }
    }

    @ViewBuilder
    private func backdrop(theme: AppTheme, k: CGFloat, dialCenter: CGPoint) -> some View {
        RadialGradient(colors: [theme.worldA, theme.worldB], center: .init(x: 0.5, y: 0.54), startRadius: 0, endRadius: 420 * k)
            .ignoresSafeArea()

        if app.friendMode {
            Circle()
                .fill(RadialGradient(colors: [app.accent, app.accent.opacity(0.55)], center: .center, startRadius: 0, endRadius: 160 * k))
                .frame(width: 320 * k, height: 320 * k)
                .overlay(
                    Text(app.dest.prefix(2).uppercased())
                        .font(.system(size: 92 * k, weight: .black, design: .rounded))
                        .foregroundStyle(.black.opacity(0.3))
                )
                .position(dialCenter)
        }
    }

    @ViewBuilder
    private func activityPill(theme: AppTheme) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(app.routeColor)
                .frame(width: 7, height: 7)
                .shadow(color: app.routeColor, radius: 5)
            Text(app.activity)
                .font(.system(size: 10, weight: .heavy))
                .tracking(1.4)
                .foregroundStyle(theme.ink.opacity(0.86))
            Text("\(Int(app.speed.rounded())) \(app.opts.units == "Miles" ? "mph" : "km/h")")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(theme.ink.opacity(0.66))
        }
        .padding(.vertical, 7)
        .padding(.horizontal, 12)
        .background(Capsule().fill(theme.ink.opacity(0.06)))
        .overlay(Capsule().stroke(theme.ink.opacity(0.1)))
    }

    @ViewBuilder
    private func searchAndFriends(k: CGFloat, theme: AppTheme) -> some View {
        VStack(spacing: 14 * k) {
            Button { app.searchOpen = true } label: {
                HStack(spacing: 10) {
                    Circle().strokeBorder(theme.ink.opacity(0.45), lineWidth: 1.5).frame(width: 13, height: 13)
                    Text("Where are we off to?")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(theme.ink.opacity(0.68))
                    Spacer()
                }
                .padding(.horizontal, 16)
                .frame(height: 46)
                .background(Capsule().fill(theme.ink.opacity(0.06)))
                .overlay(Capsule().stroke(theme.ink.opacity(0.1)))
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    ForEach(Friend.all) { f in
                        Button { app.goToFriend(f) } label: {
                            VStack(spacing: 6) {
                                ZStack {
                                    Circle()
                                        .fill(LinearGradient(colors: [app.currentTheme.accent, Color(hex: "34D6A5")], startPoint: .topLeading, endPoint: .bottomTrailing))
                                        .frame(width: 52, height: 52)
                                    Circle().fill(theme.screen).frame(width: 48, height: 48)
                                    Circle().fill(f.color).frame(width: 42, height: 42)
                                    Text(f.initials)
                                        .font(.system(size: 15, weight: .heavy))
                                        .foregroundStyle(Color(hex: "241A14"))
                                }
                                .overlay(
                                    Circle().stroke(f.color, lineWidth: app.destColor == f.color ? 2 : 0)
                                        .shadow(color: f.color, radius: app.destColor == f.color ? 8 : 0)
                                )
                                Text(f.name)
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(theme.ink.opacity(0.76))
                                    .lineLimit(1)
                            }
                            .frame(width: 56)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func bottomCard(theme: AppTheme, k: CGFloat) -> some View {
        if !app.guiding {
            HStack(spacing: 14) {
                Circle().fill(app.accent).frame(width: 10, height: 10).shadow(color: app.accent, radius: 6)
                VStack(alignment: .leading, spacing: 3) {
                    Text(app.dest).font(.system(size: 16, weight: .heavy)).foregroundStyle(theme.ink).lineLimit(1)
                    Text(app.friendMode ? "Pointing at a friend" : "Straight-line pointing")
                        .font(.system(size: 13, weight: .semibold)).foregroundStyle(theme.ink.opacity(0.7))
                }
                Spacer()
                Button { app.startGuidance() } label: {
                    Text("ROUTE")
                        .font(.system(size: 12, weight: .black))
                        .tracking(0.6)
                        .foregroundStyle(app.accent.onInk)
                        .padding(.horizontal, 15).padding(.vertical, 10)
                        .background(RoundedRectangle(cornerRadius: 15).fill(app.accent))
                }
            }
            .padding(.horizontal, 18).padding(.vertical, 16)
            .background(RoundedRectangle(cornerRadius: 22).fill(theme.ink.opacity(0.07)))
            .overlay(RoundedRectangle(cornerRadius: 22).stroke(theme.ink.opacity(0.12)))
        } else {
            VStack(spacing: 10) {
                HStack(spacing: 16) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 15).fill(theme.accent.opacity(0.16)).frame(width: 46, height: 46)
                        TurnGlyph(dir: app.step.dir, color: theme.accent)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text(app.step.copy).font(.system(size: 16, weight: .heavy)).foregroundStyle(theme.ink)
                        Text(app.step.lane).font(.system(size: 12, weight: .semibold)).foregroundStyle(theme.ink.opacity(0.68))
                    }
                    Spacer()
                }
                .padding(.horizontal, 18).padding(.vertical, 16)
                .background(RoundedRectangle(cornerRadius: 22).fill(theme.ink.opacity(0.07)))
                .overlay(RoundedRectangle(cornerRadius: 22).stroke(theme.ink.opacity(0.12)))

                HStack(spacing: 10) {
                    HStack(spacing: 9) {
                        Text("THEN").font(.system(size: 10, weight: .heavy)).tracking(1.8).foregroundStyle(theme.ink.opacity(0.68))
                        Text(app.nextStep.copy).font(.system(size: 13, weight: .semibold)).foregroundStyle(theme.ink.opacity(0.8)).lineLimit(1)
                    }
                    .padding(.horizontal, 14).padding(.vertical, 11)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 16).fill(theme.ink.opacity(0.05)))
                    .overlay(RoundedRectangle(cornerRadius: 16).stroke(theme.ink.opacity(0.09)))

                    Button { app.endGuidance() } label: {
                        Text("END")
                            .font(.system(size: 11, weight: .black)).tracking(0.9)
                            .foregroundStyle(theme.ink.opacity(0.84))
                            .padding(.horizontal, 16).padding(.vertical, 12)
                            .overlay(RoundedRectangle(cornerRadius: 16).stroke(theme.ink.opacity(0.18)))
                    }
                }
            }
        }
    }
}

private struct TurnGlyph: View {
    let dir: TurnDir
    let color: Color

    var body: some View {
        Group {
            switch dir {
            case .left:
                Image(systemName: "arrow.turn.up.left").resizable().scaledToFit()
            case .right:
                Image(systemName: "arrow.turn.up.right").resizable().scaledToFit()
            case .straight:
                Image(systemName: "arrow.up").resizable().scaledToFit()
            }
        }
        .frame(width: 22, height: 22)
        .foregroundStyle(color)
        .fontWeight(.bold)
    }
}
