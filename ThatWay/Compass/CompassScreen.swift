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
    // Not read directly (AppModel's computed properties reach into it instead) — declaring
    // it here is what makes SwiftUI re-render this screen when a route arrives or advances,
    // since a nested ObservableObject's own publishes don't bubble through AppModel's.
    @EnvironmentObject var routing: RoutingManager
    @State private var dialFrame: CGRect?
    @State private var cardFrame: CGRect?
    @FocusState private var searchFocused: Bool

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
            let blurRest = app.searchOpen ? 3.0 : 0.0

            ZStack {
                RadialGradient(colors: [theme.worldA, theme.worldB], center: .init(x: 0.5, y: 0.54), startRadius: 0, endRadius: 420 * k)
                    .ignoresSafeArea()

                // Search bar pinned to the top (safe-area inset handled by the VStack itself
                // respecting the safe area), friends row fixed below it, compass centered in
                // the remaining space, destination card anchored above the tab bar. Everything
                // except the search bar itself blurs when its results are showing, so it stays
                // the one clearly "live" thing on screen.
                VStack(spacing: 0) {
                    // Wrapped together and nudged up as one unit so the activity pill, search
                    // bar, and friends row all shift in lockstep rather than drifting apart.
                    VStack(spacing: 0) {
                        activityPill(theme: theme)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.leading, Spacing.container * k)
                            .padding(.top, Spacing.tight * k)
                            .blur(radius: blurRest)

                        if !app.guiding {
                            searchBar(theme: theme)
                                .padding(.horizontal, Spacing.container * k)
                                .padding(.top, Spacing.element * k)

                            friendsRow(k: k, theme: theme)
                                .frame(height: 80 * k)
                                .padding(.top, Spacing.element * k)
                                .blur(radius: blurRest)
                                .zIndex(1)
                        }
                    }
                    .offset(y: -10)

                    if app.guiding {
                        RouteLineView(color: app.routeColor)
                            .frame(maxHeight: .infinity)
                            .padding(.top, Spacing.element * k)
                    } else {
                        Spacer(minLength: Spacing.element * k)
                    }

                    dialCluster(theme: theme, k: k, dialSize: dialSize)
                        // Guidance mode nudges the dial up so it never crowds the turn card below.
                        .offset(y: app.guiding ? -35 * k : 0)
                        .animation(.spring(response: 0.5, dampingFraction: 0.7), value: app.guiding)
                        .background(
                            GeometryReader { dialGeo in
                                Color.clear.preference(key: FramePreferenceKey.self, value: dialGeo.frame(in: .named("compassScreen")))
                            }
                        )
                        .onPreferenceChange(FramePreferenceKey.self) { dialFrame = $0 }
                        .blur(radius: blurRest)

                    Spacer(minLength: Spacing.element * k)

                    bottomCard(theme: theme, k: k)
                        .padding(.horizontal, Spacing.container * k)
                        .background(
                            GeometryReader { cardGeo in
                                Color.clear.preference(key: CardFramePreferenceKey.self, value: cardGeo.frame(in: .named("compassScreen")))
                            }
                        )
                        .onPreferenceChange(CardFramePreferenceKey.self) { cardFrame = $0 }
                        .blur(radius: blurRest)

                    Spacer(minLength: tabBarClearance * k)
                }

                ModeToggle(k: k, dialCenter: dialCenter, bounds: geo.size, cardFrame: cardFrame)
                    .environmentObject(app)
                    .blur(radius: blurRest)
                    .allowsHitTesting(!app.searchOpen)

                if app.searchOpen {
                    Color.black.opacity(0.001)
                        .ignoresSafeArea()
                        .contentShape(Rectangle())
                        .onTapGesture { closeSearch() }

                    SearchResultsPanel(k: k, onClose: closeSearch)
                        .environmentObject(app)
                        .padding(.top, 100 * k)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .coordinateSpace(name: "compassScreen")
            .animation(.spring(response: 0.5, dampingFraction: 0.7), value: app.searchOpen)
        }
    }

    private func closeSearch() {
        app.searchOpen = false
        searchFocused = false
    }

    /// The dial and its faint tilt guide lines — positioned relative to this one cluster's
    /// own centre, so they can never drift out of alignment with each other regardless of
    /// what sits above them on a given device. The friend-colour treatment lives entirely
    /// on the dial face itself now (see `DialView`) rather than a separate backdrop.
    @ViewBuilder
    private func dialCluster(theme: AppTheme, k: CGFloat, dialSize: CGFloat) -> some View {
        ZStack {
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
        HStack(spacing: Spacing.tight + 2) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(app.searchOpen ? theme.accent : theme.textSecondary)

            TextField("Where are we off to?", text: $app.searchQuery)
                .focused($searchFocused)
                .font(.nunito(15, .semibold))
                .foregroundStyle(theme.ink)
                .submitLabel(.search)
                .onSubmit { app.pickPlace(app.searchQuery) }

            if app.searchOpen {
                Button("Cancel") { closeSearch() }
                    .font(.nunito(13, .semibold))
                    .foregroundStyle(theme.accent)
                    .transition(.opacity)
            }
        }
        .padding(.horizontal, Spacing.container)
        .frame(height: 46)
        .background(Capsule().fill(theme.ink.opacity(0.06)))
        .overlay(Capsule().stroke(app.searchOpen ? theme.accent.opacity(0.65) : theme.borderColor, lineWidth: app.searchOpen ? 1.5 : 1))
        // The "pop out of the screen" moment when results appear, plus a soft back-glow
        // that keeps this the one thing that reads as active while everything else blurs.
        .shadow(color: theme.accent.opacity(app.searchOpen ? 0.5 : 0), radius: app.searchOpen ? 16 : 0)
        .scaleEffect(app.searchOpen ? 1.03 : 1)
        .contentShape(Capsule())
        .onTapGesture { app.searchOpen = true; searchFocused = true }
        .onChange(of: searchFocused) { _, focused in if focused { app.searchOpen = true } }
        .animation(.spring(response: 0.45, dampingFraction: 0.62), value: app.searchOpen)
        .sensoryFeedback(.impact(weight: .light), trigger: app.searchOpen)
    }

    @ViewBuilder
    private func friendsRow(k: CGFloat, theme: AppTheme) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: Spacing.element) {
                ForEach(Friend.all) { f in
                    let selected = app.destKind == .friend && app.destColor == f.color
                    Button {
                        if selected {
                            app.clearDestination()
                        } else {
                            app.goToFriend(f)
                        }
                    } label: {
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
                                Circle().stroke(f.color, lineWidth: selected ? 2 : 0)
                                    .shadow(color: f.color, radius: selected ? 8 : 0)
                            )
                            // Selected avatars zoom up well beyond their row and must paint
                            // over the search bar above, not get clipped or buried under it.
                            .scaleEffect(selected ? 1.45 : 1)
                            .zIndex(selected ? 1 : 0)
                            Text(f.name)
                                .font(.nunito(11, .semibold))
                                .foregroundStyle(theme.textSecondary)
                                .lineLimit(1)
                        }
                        .frame(width: 56)
                    }
                    .buttonStyle(.plain)
                    .animation(.spring(response: 0.4, dampingFraction: 0.65), value: selected)
                }
            }
            .padding(.horizontal, Spacing.container * k)
        }
        .scrollClipDisabled()
        .sensoryFeedback(.impact(weight: .medium), trigger: app.destColor)
    }

    @ViewBuilder
    private func bottomCard(theme: AppTheme, k: CGFloat) -> some View {
        if !app.guiding {
            if app.isIdle {
                idleCard(theme: theme)
            } else {
                HStack(spacing: Spacing.element) {
                    Circle().fill(app.accent).frame(width: 10, height: 10).shadow(color: app.accent, radius: 6)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(app.dest).font(.nunito(16, .extraBold)).foregroundStyle(theme.ink).lineLimit(1)
                        Text(app.friendMode ? "Pointing at a friend" : app.destinationCoordinate != nil ? "Real bearing · tap ROUTE" : "Straight-line pointing")
                            .font(.nunito(13, .semibold)).foregroundStyle(theme.textSecondary).lineLimit(1)
                    }
                    Spacer()
                    Button { app.clearDestination() } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 18))
                            .foregroundStyle(theme.textSecondary.opacity(0.55))
                    }
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
            }
        } else {
            // The turn card: a real OSRM instruction when a route is loaded (with a lane hint
            // swapped for live distance-to-turn), the simulated mock turn otherwise.
            HStack(spacing: Spacing.container) {
                ZStack {
                    RoundedRectangle(cornerRadius: 15).fill(theme.accent.opacity(0.16)).frame(width: 46, height: 46)
                    TurnGlyph(dir: app.turnDir, color: theme.accent)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(app.turnCopy).font(.nunito(16, .extraBold)).foregroundStyle(theme.ink).lineLimit(2)
                    Text(app.turnSubtitle).font(.nunito(12, .semibold)).foregroundStyle(theme.textSecondary)
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

    /// Shown in idle mode — no place or friend selected, dial resting north-up.
    @ViewBuilder
    private func idleCard(theme: AppTheme) -> some View {
        HStack(spacing: Spacing.element) {
            Image(systemName: "location.north.line")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(theme.textSecondary)
            Text("Search or pick a friend to start pointing")
                .font(.nunito(13, .semibold))
                .foregroundStyle(theme.textSecondary)
            Spacer()
        }
        .padding(.horizontal, Spacing.container + 2).padding(.vertical, Spacing.element + 4)
        .background(RoundedRectangle(cornerRadius: 22).fill(theme.ink.opacity(0.07)))
        .overlay(RoundedRectangle(cornerRadius: 22).stroke(theme.borderColor))
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
/// the dial, fading in at the top for depth, with chevrons marking the direction of
/// travel. Doubles as a visual countdown to the turn: `progress` is 1 when far from the
/// turn (full height) and 0 right at it (compresses toward the dial, then disappears).
private struct RouteLineView: View {
    let color: Color
    @State private var dashPhase: CGFloat = 0

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .top) {
                // Full-height glow line — always present at full length while guiding; it
                // never shrinks or vanishes mid-route.
                LinearGradient(
                    stops: [.init(color: .clear, location: 0), .init(color: color.opacity(0.85), location: 0.14), .init(color: color, location: 1)],
                    startPoint: .top, endPoint: .bottom
                )
                .frame(width: 4)
                .clipShape(Capsule())
                .shadow(color: color.opacity(0.5), radius: 6)
                .frame(maxWidth: .infinity)

                // A continuously-marching dashed overlay reads as traffic flowing down the
                // line toward you, rather than the line itself counting down.
                Path { path in
                    path.move(to: CGPoint(x: geo.size.width / 2, y: 14))
                    path.addLine(to: CGPoint(x: geo.size.width / 2, y: geo.size.height))
                }
                .stroke(Color.white.opacity(0.85), style: StrokeStyle(lineWidth: 2.5, lineCap: .round, dash: [8, 16], dashPhase: dashPhase))

                // Destination marker capping the top of the line.
                ZStack {
                    Circle().fill(color.opacity(0.28)).frame(width: 24, height: 24)
                    Circle().fill(color).frame(width: 10, height: 10)
                        .overlay(Circle().stroke(.white, lineWidth: 1.5))
                }
                .frame(maxWidth: .infinity)
                .shadow(color: color.opacity(0.6), radius: 8)
            }
        }
        .onAppear {
            withAnimation(.linear(duration: 1.0).repeatForever(autoreverses: false)) {
                dashPhase = -48
            }
        }
    }
}

/// Results and recent-search suggestions only — the search bar itself lives above this
/// panel and stays interactive, so there's no second, redundant text field in here.
private struct SearchResultsPanel: View {
    @EnvironmentObject var app: AppModel
    let k: CGFloat
    let onClose: () -> Void

    private let placeKinds: [String: (sub: String, kind: String, dist: String)] = [
        "Sunrise Bakery": ("Open until 9", "✦", "1.2 km"),
        "Home": ("Saved", "⌂", "6.8 km"),
        "Baker Street Lot": ("Parking", "P", "3.1 km"),
    ]

    private var results: [String] {
        guard !app.searchQuery.isEmpty else { return app.recentSearches }
        return app.recentSearches.filter { $0.localizedCaseInsensitiveContains(app.searchQuery) }
    }

    var body: some View {
        let theme = app.currentTheme
        VStack(alignment: .leading, spacing: Spacing.element) {
            Text(app.searchQuery.isEmpty ? "RECENT" : "RESULTS")
                .font(.system(size: 10, weight: .heavy)).tracking(1.6)
                .foregroundStyle(theme.textSecondary)
                .padding(.top, Spacing.container)

            if results.isEmpty {
                Text("No matches for \u{201C}\(app.searchQuery)\u{201D}")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(theme.textSecondary)
                    .padding(.vertical, Spacing.element)
            } else {
                VStack(spacing: 0) {
                    ForEach(results, id: \.self) { name in
                        let info = placeKinds[name] ?? ("Recent", "◷", "—")
                        Button {
                            app.pickPlace(name)
                            onClose()
                        } label: {
                            HStack(spacing: Spacing.element) {
                                Text(info.kind)
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundStyle(theme.ink.opacity(0.76))
                                    .frame(width: 34, height: 34)
                                    .background(RoundedRectangle(cornerRadius: 11).fill(theme.ink.opacity(0.08)))
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(name).font(.system(size: 15, weight: .heavy)).foregroundStyle(theme.ink)
                                    Text(info.sub).font(.system(size: 12, weight: .semibold)).foregroundStyle(theme.textSecondary)
                                }
                                Spacer()
                                Text(info.dist).font(.system(size: 12, weight: .bold)).foregroundStyle(theme.textSecondary)
                            }
                            .padding(.vertical, Spacing.tight + 3).padding(.horizontal, Spacing.tight)
                            .overlay(Divider().background(theme.borderColor), alignment: .bottom)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Spacing.container)
        .frame(maxWidth: .infinity, alignment: .top)
        .background(
            theme.screen.opacity(0.98)
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                .shadow(color: .black.opacity(0.35), radius: 24, y: -8)
        )
    }
}
