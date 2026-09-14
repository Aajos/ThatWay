//
//  CompassScreen.swift
//  ThatWay
//

import SwiftUI

/// Reports the dial's actual on-screen frame so sibling decorations (guide lines,
/// the mode toggle's no-go zone) can key off where it really ended up, rather than
/// a hard-coded offset tuned for one device size.
private struct DialFrameKey: PreferenceKey {
    static var defaultValue: CGRect?
    static func reduce(value: inout CGRect?, nextValue: () -> CGRect?) {
        value = nextValue() ?? value
    }
}

struct CompassScreen: View {
    @EnvironmentObject var app: AppModel
    @State private var dialFrame: CGRect?

    /// Reserve room below the content for RootView's floating tab bar so the
    /// destination card never sits under it.
    private let tabBarClearance: CGFloat = 90

    var body: some View {
        GeometryReader { geo in
            let k = geo.size.width / 402
            let theme = app.currentTheme
            // Shrinks gracefully on narrower/shorter phones instead of overflowing.
            let dialSize = min(286 * k, geo.size.width - 96, geo.size.height * 0.36)
            let dialCenter = dialFrame.map { CGPoint(x: $0.midX, y: $0.midY) }
                ?? CGPoint(x: geo.size.width / 2, y: geo.size.height * 0.58)

            ZStack {
                RadialGradient(colors: [theme.worldA, theme.worldB], center: .init(x: 0.5, y: 0.54), startRadius: 0, endRadius: 420 * k)
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    activityPill(theme: theme)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.leading, 16 * k)
                        .padding(.top, 10 * k)

                    if !app.guiding {
                        searchAndFriends(k: k, theme: theme)
                            .padding(.top, 14 * k)
                            .padding(.horizontal, 16 * k)
                    }

                    // Everything above hugs the top; the dial and card sit close beneath it
                    // with small, fixed gaps so nothing floats apart on tall screens — any
                    // extra device height just adds breathing room below the card instead.
                    dialCluster(theme: theme, k: k, dialSize: dialSize)
                        .padding(.top, 28 * k)
                        .background(
                            GeometryReader { dialGeo in
                                Color.clear.preference(key: DialFrameKey.self, value: dialGeo.frame(in: .named("compassScreen")))
                            }
                        )

                    bottomCard(theme: theme, k: k)
                        .padding(.horizontal, 16 * k)
                        .padding(.top, 20 * k)

                    Spacer(minLength: tabBarClearance * k)
                }

                ModeToggle(k: k, dialCenter: dialCenter, bounds: geo.size)
                    .environmentObject(app)
            }
            .coordinateSpace(name: "compassScreen")
            .onPreferenceChange(DialFrameKey.self) { dialFrame = $0 }
        }
    }

    /// The dial, its faint tilt guide lines, and the friend-colour backdrop blob — all
    /// positioned relative to this one cluster's own centre, so they can never drift out
    /// of alignment with each other regardless of what sits above them on a given device.
    @ViewBuilder
    private func dialCluster(theme: AppTheme, k: CGFloat, dialSize: CGFloat) -> some View {
        ZStack {
            if app.friendMode {
                Circle()
                    .fill(RadialGradient(colors: [app.accent, app.accent.opacity(0.55)], center: .center, startRadius: 0, endRadius: 160 * k))
                    .frame(width: 320 * k, height: 320 * k)
                    .overlay(
                        Text(app.dest.prefix(2).uppercased())
                            .font(.nunito(92 * k, .black))
                            .foregroundStyle(.black.opacity(0.3))
                    )
            }

            tiltGuideLines(theme: theme, dialSize: dialSize)

            DialView(k: k)
                .environmentObject(app)
                .frame(width: dialSize, height: dialSize)
        }
        .frame(width: dialSize, height: dialSize)
    }

    /// Faint vertical lines sitting just behind the dial — anchored to the interface, not the
    /// dial's own 3D transform, so a lane lean visually "reveals" more of them either side.
    @ViewBuilder
    private func tiltGuideLines(theme: AppTheme, dialSize: CGFloat) -> some View {
        let fade = LinearGradient(
            stops: [.init(color: .clear, location: 0), .init(color: theme.ink, location: 0.34),
                    .init(color: theme.ink, location: 0.66), .init(color: .clear, location: 1)],
            startPoint: .top, endPoint: .bottom
        )
        let lineHeight = dialSize * 1.12 // just a sliver beyond the dial's own top/bottom edges
        let halfSpans = [dialSize * 0.437, dialSize * 0.35] // outer pair, inner pair
        ForEach(Array(halfSpans.enumerated()), id: \.offset) { index, half in
            ForEach([-1.0, 1.0], id: \.self) { side in
                Rectangle()
                    .fill(fade)
                    .opacity(index == 0 ? 0.26 : 0.15)
                    .frame(width: 1, height: lineHeight)
                    .offset(x: side * half)
            }
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
                .font(.nunito(10, .extraBold))
                .tracking(1.4)
                .foregroundStyle(theme.ink.opacity(0.86))
            Text("\(Int(app.speed.rounded())) \(app.opts.units == "Miles" ? "mph" : "km/h")")
                .font(.nunito(10, .semibold))
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
                        .font(.nunito(15, .semibold))
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
                                        .font(.nunito(15, .extraBold))
                                        .foregroundStyle(Color(hex: "241A14"))
                                }
                                .overlay(
                                    Circle().stroke(f.color, lineWidth: app.destColor == f.color ? 2 : 0)
                                        .shadow(color: f.color, radius: app.destColor == f.color ? 8 : 0)
                                )
                                Text(f.name)
                                    .font(.nunito(11, .semibold))
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
                    Text(app.dest).font(.nunito(16, .extraBold)).foregroundStyle(theme.ink).lineLimit(1)
                    Text(app.friendMode ? "Pointing at a friend" : "Straight-line pointing")
                        .font(.nunito(13, .semibold)).foregroundStyle(theme.ink.opacity(0.7))
                }
                Spacer()
                Button { app.startGuidance() } label: {
                    Text("ROUTE")
                        .font(.nunito(12, .black))
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
            // Simplified guidance card for now: just the current turn, an arrow, and a way out.
            HStack(spacing: 16) {
                ZStack {
                    RoundedRectangle(cornerRadius: 15).fill(theme.accent.opacity(0.16)).frame(width: 46, height: 46)
                    TurnGlyph(dir: app.step.dir, color: theme.accent)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(app.step.copy).font(.nunito(16, .extraBold)).foregroundStyle(theme.ink)
                    Text(app.step.lane).font(.nunito(12, .semibold)).foregroundStyle(theme.ink.opacity(0.68))
                }
                Spacer()
                Button { app.endGuidance() } label: {
                    Text("END")
                        .font(.nunito(11, .black)).tracking(0.9)
                        .foregroundStyle(theme.ink.opacity(0.84))
                        .padding(.horizontal, 14).padding(.vertical, 10)
                        .overlay(RoundedRectangle(cornerRadius: 14).stroke(theme.ink.opacity(0.18)))
                }
            }
            .padding(.horizontal, 18).padding(.vertical, 16)
            .background(RoundedRectangle(cornerRadius: 22).fill(theme.ink.opacity(0.07)))
            .overlay(RoundedRectangle(cornerRadius: 22).stroke(theme.ink.opacity(0.12)))
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
