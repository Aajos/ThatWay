//
//  CompassScreen.swift
//  ThatWay
//

import SwiftUI

/// Reports a view's actual on-screen frame so siblings (guide lines, the mode
/// toggle's no-go zones) can key off where it really ended up, rather than a
/// hard-coded offset tuned for one device size.
private struct FramePreferenceKey: PreferenceKey {
    static var defaultValue: CGRect?
    static func reduce(value: inout CGRect?, nextValue: () -> CGRect?) {
        value = nextValue() ?? value
    }
}

private enum Spacing {
    static let container: CGFloat = 16
    static let element: CGFloat = 12
    static let tight: CGFloat = 8
}

struct CompassScreen: View {
    @EnvironmentObject var app: AppModel
    @State private var dialFrame: CGRect?
    @State private var cardFrame: CGRect?

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
                ?? CGPoint(x: geo.size.width / 2, y: geo.size.height * 0.5)

            ZStack {
                RadialGradient(colors: [theme.worldA, theme.worldB], center: .init(x: 0.5, y: 0.54), startRadius: 0, endRadius: 420 * k)
                    .ignoresSafeArea()

                // Search bar pinned to the top (safe-area inset handled by the VStack itself
                // respecting the safe area), friends row fixed below it, compass centered in
                // the remaining space, destination card anchored above the tab bar.
                VStack(spacing: 0) {
                    activityPill(theme: theme)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.leading, Spacing.container * k)
                        .padding(.top, Spacing.tight * k)

                    if !app.guiding {
                        searchBar(theme: theme)
                            .padding(.horizontal, Spacing.container * k)
                            .padding(.top, Spacing.element * k)

                        friendsRow(k: k, theme: theme)
                            .frame(height: 80 * k)
                            .padding(.top, Spacing.element * k)
                    }

                    if app.guiding {
                        RouteLineView(color: app.routeColor)
                            .frame(maxHeight: .infinity)
                            .padding(.top, Spacing.element * k)
                    } else {
                        Spacer(minLength: Spacing.element * k)
                    }

                    dialCluster(theme: theme, k: k, dialSize: dialSize)
                        .background(
                            GeometryReader { dialGeo in
                                Color.clear.preference(key: FramePreferenceKey.self, value: dialGeo.frame(in: .named("compassScreen")))
                            }
                        )
                        .onPreferenceChange(FramePreferenceKey.self) { dialFrame = $0 }

                    Spacer(minLength: Spacing.element * k)

                    bottomCard(theme: theme, k: k)
                        .padding(.horizontal, Spacing.container * k)
                        .background(
                            GeometryReader { cardGeo in
                                Color.clear.preference(key: CardFramePreferenceKey.self, value: cardGeo.frame(in: .named("compassScreen")))
                            }
                        )
                        .onPreferenceChange(CardFramePreferenceKey.self) { cardFrame = $0 }

                    Spacer(minLength: tabBarClearance * k)
                }

                ModeToggle(k: k, dialCenter: dialCenter, bounds: geo.size, cardFrame: cardFrame)
                    .environmentObject(app)
            }
            .coordinateSpace(name: "compassScreen")
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
        HStack(spacing: Spacing.tight) {
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
                .foregroundStyle(theme.textSecondary)
        }
        .padding(.vertical, Spacing.tight - 1)
        .padding(.horizontal, Spacing.element)
        .background(Capsule().fill(theme.ink.opacity(0.06)))
        .overlay(Capsule().stroke(theme.borderColor))
    }

    @ViewBuilder
    private func searchBar(theme: AppTheme) -> some View {
        Button {
            app.searchOpen = true
        } label: {
            HStack(spacing: Spacing.tight + 2) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(theme.textSecondary)
                Text("Where are we off to?")
                    .font(.nunito(15, .semibold))
                    .foregroundStyle(theme.textSecondary)
                Spacer()
            }
            .padding(.horizontal, Spacing.container)
            .frame(height: 46)
            .background(Capsule().fill(theme.ink.opacity(0.06)))
            .overlay(Capsule().stroke(theme.borderColor))
        }
        .sensoryFeedback(.impact(weight: .light), trigger: app.searchOpen)
    }

    @ViewBuilder
    private func friendsRow(k: CGFloat, theme: AppTheme) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Spacing.element) {
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
                                .foregroundStyle(theme.textSecondary)
                                .lineLimit(1)
                        }
                        .frame(width: 56)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, Spacing.container * k)
        }
        .sensoryFeedback(.impact(weight: .medium), trigger: app.destColor)
    }

    @ViewBuilder
    private func bottomCard(theme: AppTheme, k: CGFloat) -> some View {
        if !app.guiding {
            HStack(spacing: Spacing.element) {
                Circle().fill(app.accent).frame(width: 10, height: 10).shadow(color: app.accent, radius: 6)
                VStack(alignment: .leading, spacing: 3) {
                    Text(app.dest).font(.nunito(16, .extraBold)).foregroundStyle(theme.ink).lineLimit(1)
                    Text(app.friendMode ? "Pointing at a friend" : "Straight-line pointing")
                        .font(.nunito(13, .semibold)).foregroundStyle(theme.textSecondary)
                }
                Spacer()
                Button { app.startGuidance() } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "arrowshape.turn.up.right").font(.system(size: 12, weight: .bold))
                        Text("ROUTE").font(.nunito(12, .black)).tracking(0.6)
                    }
                    .foregroundStyle(app.accent.onInk)
                    .padding(.horizontal, Spacing.element + 3).padding(.vertical, Spacing.tight + 2)
                    .background(RoundedRectangle(cornerRadius: 15).fill(app.accent))
                }
            }
            .padding(.horizontal, Spacing.container + 2).padding(.vertical, Spacing.element + 4)
            .background(RoundedRectangle(cornerRadius: 22).fill(theme.ink.opacity(0.07)))
            .overlay(RoundedRectangle(cornerRadius: 22).stroke(theme.borderColor))
        } else {
            // Simplified guidance card for now: just the current turn, an arrow, and a way out.
            HStack(spacing: Spacing.container) {
                ZStack {
                    RoundedRectangle(cornerRadius: 15).fill(theme.accent.opacity(0.16)).frame(width: 46, height: 46)
                    TurnGlyph(dir: app.step.dir, color: theme.accent)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(app.step.copy).font(.nunito(16, .extraBold)).foregroundStyle(theme.ink)
                    Text(app.step.lane).font(.nunito(12, .semibold)).foregroundStyle(theme.textSecondary)
                }
                Spacer()
                Button { app.endGuidance() } label: {
                    Text("END")
                        .font(.nunito(11, .black)).tracking(0.9)
                        .foregroundStyle(theme.textSecondary)
                        .padding(.horizontal, Spacing.element + 2).padding(.vertical, Spacing.tight + 2)
                        .overlay(RoundedRectangle(cornerRadius: 14).stroke(theme.borderColor))
                }
            }
            .padding(.horizontal, Spacing.container + 2).padding(.vertical, Spacing.element + 4)
            .background(RoundedRectangle(cornerRadius: 22).fill(theme.ink.opacity(0.07)))
            .overlay(RoundedRectangle(cornerRadius: 22).stroke(theme.borderColor))
        }
    }
}

/// Reports the destination card's frame, mirroring `FramePreferenceKey` — kept as a
/// distinct type since a view can only own one preference value per key per subtree.
private struct CardFramePreferenceKey: PreferenceKey {
    static var defaultValue: CGRect?
    static func reduce(value: inout CGRect?, nextValue: () -> CGRect?) {
        value = nextValue() ?? value
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

/// The "road ahead" indicator shown in guidance mode: a colour-coded vertical line
/// (blue for driving, green for walking) running from just below the header down to
/// the dial, fading in at the top for depth, with chevrons marking the direction of travel.
private struct RouteLineView: View {
    let color: Color

    var body: some View {
        GeometryReader { geo in
            ZStack {
                LinearGradient(
                    stops: [.init(color: .clear, location: 0), .init(color: color.opacity(0.85), location: 0.22), .init(color: color, location: 1)],
                    startPoint: .top, endPoint: .bottom
                )
                .frame(width: 4)
                .clipShape(Capsule())
                .shadow(color: color.opacity(0.5), radius: 6)
                .position(x: geo.size.width / 2, y: geo.size.height / 2)

                VStack(spacing: 0) {
                    ForEach(0..<3, id: \.self) { i in
                        Spacer()
                        Image(systemName: "chevron.down")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(color)
                            .opacity(0.3 + Double(i) * 0.25)
                    }
                    Spacer()
                }
            }
        }
    }
}
