//
//  CompassScreen.swift
//  ThatWay
//

import SwiftUI
import MapKit

private enum Spacing {
    static let container: CGFloat = 16
    static let element: CGFloat = 12
    static let tight: CGFloat = 8
}

/// Reports a view's real on-screen frame — used to pin the search results panel exactly
/// below the search bar, wherever it actually ends up, rather than a guessed offset.
private struct SearchBarFramePreferenceKey: PreferenceKey {
    static var defaultValue: CGRect?
    static func reduce(value: inout CGRect?, nextValue: () -> CGRect?) {
        value = nextValue() ?? value
    }
}

/// Reports the dial cluster's real on-screen centre — so the guidance line above it can
/// extend mathematically to that exact point (whatever it ends up being on a given device,
/// at a given Dynamic Type size, mid-animation, etc.) rather than guessing a fixed offset.
private struct DialCenterPreferenceKey: PreferenceKey {
    static var defaultValue: CGPoint?
    static func reduce(value: inout CGPoint?, nextValue: () -> CGPoint?) {
        value = nextValue() ?? value
    }
}

/// The three top pills' reference widths — recorded once here, at the sizes they were
/// designed at, and used everywhere else only as *ratios* to maintain while the row
/// stretches to fill whatever width the actual device has. The theme square is fixed
/// (it has to stay square), so only the activity and mode pills flex against each other.
private enum TopBarMetrics {
    static let activityReferenceWidth: CGFloat = 160
    static let modeReferenceWidth: CGFloat = 132
    static let activityWidthRatio: CGFloat = activityReferenceWidth / (activityReferenceWidth + modeReferenceWidth)
    static let themeSquareSize: CGFloat = 54
    static let pillHeight: CGFloat = 66
    static let edgePadding: CGFloat = 12
    static let gap: CGFloat = 12
}

struct CompassScreen: View {
    @EnvironmentObject var app: AppModel
    // Not read directly (AppModel's computed properties reach into it instead) — declaring
    // it here is what makes SwiftUI re-render this screen when a route arrives or advances,
    // since a nested ObservableObject's own publishes don't bubble through AppModel's.
    @EnvironmentObject var routing: RoutingManager
    // Same story as `routing` above — read by GuidanceLineView via app state, declared here
    // only so SwiftUI re-renders this screen when a bake completes.
    @EnvironmentObject var routeDataGenerator: RouteDataGenerator
    @FocusState private var searchFocused: Bool
    @State private var searchBarFrame: CGRect?
    @State private var dialCenter: CGPoint?
    /// Shared by the collapsed card stack and the pulled-up list so each card slides and resizes
    /// between the two instead of one appearing and the other vanishing.
    @Namespace private var cardNamespace

    /// Reserve room below the content for RootView's floating tab bar so the
    /// destination card never sits under it — trimmed down so the card sits closer to
    /// the (now lower, more spread-out) tab bar instead of floating far above it.
    private let tabBarClearance: CGFloat = 56

    var body: some View {
        GeometryReader { geo in
            let k = geo.size.width / 402
            let theme = app.currentTheme
            // The compass's diameter is a fixed share of the screen width, so it adapts
            // from one device to another: 80% in guidance (when flat), 85% in point mode (centred).
            // Capped by height so it can never overflow a short screen.
            // Large and centred while the route line is away (85%), easing down to 80% and lower on
            // screen once the route line comes in for the last 500m. Height-capped so it can't
            // run into the top bar or the cards on a short screen.
            let dialSize = min(geo.size.width * (app.showsPolyline ? 0.80 : 0.85), geo.size.height * 0.42)
            let dialK = dialSize / 286
            let blurRest = app.searchOpen ? 3.0 : (app.cardsExpanded ? 14.0 : 0.0)

            ZStack {
                RadialGradient(colors: [theme.worldA, theme.worldB], center: .init(x: 0.5, y: 0.54), startRadius: 0, endRadius: 420 * k)
                    .ignoresSafeArea()

                // Activity/theme/mode pills are anchored to the top of the screen, fixed —
                // no floating, no dragging, no collision-avoidance with the dial or card
                // below. Search bar and friends row sit right below; compass centered in the
                // remaining space; destination card anchored above the tab bar. Everything
                // except the search bar itself blurs when its results are showing, so it
                // stays the one clearly "live" thing on screen.
                VStack(spacing: 0) {
                    topBar(theme: theme, screenWidth: geo.size.width)
                        .padding(.top, 12)
                        // The three top pills stay sharp while the cards are up.
                        .blur(radius: app.searchOpen ? 3 : 0)
                        .allowsHitTesting(!app.searchOpen)

                    if !app.guiding {
                        searchBar(theme: theme)
                            .padding(.horizontal, Spacing.container * k)
                            .padding(.top, Spacing.element * k)
                            .background(
                                GeometryReader { barGeo in
                                    Color.clear.preference(key: SearchBarFramePreferenceKey.self, value: barGeo.frame(in: .named("compassScreen")))
                                }
                            )
                            .onPreferenceChange(SearchBarFramePreferenceKey.self) { searchBarFrame = $0 }

                        friendsRow(k: k, theme: theme)
                            .frame(height: 80 * k)
                            .padding(.top, Spacing.element * k)
                            .blur(radius: blurRest)
                            .zIndex(1)
                    }

                    // The active instruction is always the first thing under the pills — before the
                    // route line comes in and after — so it never jumps to another part of the screen.
                    if app.guiding {
                        GuidanceCardStack(theme: theme, namespace: cardNamespace, showsPeeks: app.showsPolyline, opensOnPullDown: true)
                            .padding(.horizontal, Spacing.container * k)
                            .padding(.top, Spacing.element * k)
                            .blur(radius: blurRest)
                            .opacity(app.cardsExpanded ? 0 : 1)
                    }

                    if app.showsPolyline {
                        // currentLocation/speedKmh deliberately read the throttled
                        // guidanceCheck* snapshot (updated once per adaptive poll) rather
                        // than the live, continuously-updating values — the look-ahead
                        // geometry should only recompute as often as the corridor check
                        // itself actually runs.
                        GuidanceLineView(
                            guidanceData: routeDataGenerator.guidanceData,
                            steps: routing.steps,
                            currentLocation: app.guidanceCheckPosition,
                            speedKmh: app.guidanceCheckSpeedKmh,
                            activity: app.guidanceActivity,
                            destination: app.destinationCoordinate,
                            color: app.routeColor,
                            dialCenter: dialCenter,
                            // The dial tilts about its top edge, so that edge never moves: it always sits
                            // half the dial's diameter above its centre.
                            dialHalfHeight: dialSize / 2,
                            isRecalculating: routeDataGenerator.guidanceData != nil && routeDataGenerator.isGenerating
                        )
                            .frame(maxHeight: .infinity)
                            .padding(.top, Spacing.element * k)
                            .blur(radius: blurRest)
                    } else if app.guiding {
                        Spacer(minLength: Spacing.element * k)
                    } else {
                        Spacer(minLength: Spacing.element * k)
                    }

                    dialCluster(theme: theme, k: dialK, dialSize: dialSize)
                        .blur(radius: blurRest)

                    if app.guiding, app.hasRealRoute, let clock = app.etaManager.arrivalClock {
                        etaRow(clock: clock, theme: theme)
                            .padding(.top, Spacing.element * k)
                            .padding(.bottom, Spacing.tight)
                            .blur(radius: blurRest)
                            .opacity(app.cardsExpanded ? 0 : 1)
                    }

                    if app.guiding, !app.showsPolyline {
                        Spacer(minLength: Spacing.tight)
                        NextCardsStack(theme: theme, namespace: cardNamespace)
                            .padding(.horizontal, Spacing.container * k)
                            .blur(radius: blurRest)
                            .opacity(app.cardsExpanded ? 0 : 1)
                    } else if app.guiding {
                        Color.clear.frame(height: Spacing.element * k)
                    } else {
                        Spacer(minLength: Spacing.element * k)
                    }

                    if !app.guiding {
                        bottomCard(theme: theme, k: k)
                            .padding(.horizontal, Spacing.container * k)
                            .blur(radius: blurRest)
                    }

                    // While guiding, the cards sit at one fixed height whether or not the route
                    // line is showing — only the space above them flexes.
                    if app.guiding {
                        Color.clear.frame(height: tabBarClearance * k)
                    } else {
                        Spacer(minLength: tabBarClearance * k)
                    }
                }

                if app.guiding, app.cardsExpanded, app.hasRealRoute {
                    GuidanceCurtain(theme: theme, namespace: cardNamespace)
                        .transition(.opacity)
                        .zIndex(2)
                }

                if app.searchOpen {
                    Color.black.opacity(0.001)
                        .ignoresSafeArea()
                        .contentShape(Rectangle())
                        .onTapGesture { closeSearch() }

                    // Pinned to the search bar's own real bottom edge (tracked above via
                    // SearchBarFramePreferenceKey), never a guessed offset — so on any
                    // device, at any content size, the panel starts at least 12px below the
                    // search bar and never creeps up over it.
                    SearchResultsPanel(k: k, onClose: closeSearch)
                        .environmentObject(app)
                        .padding(.top, (searchBarFrame?.maxY ?? 100 * k) + 12)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }

                if app.arrived {
                    arrivalOverlay(theme: theme)
                        .transition(.opacity.combined(with: .scale(scale: 0.95)))
                }
            }
            .coordinateSpace(name: "compassScreen")
            .animation(.spring(response: 0.5, dampingFraction: 0.75), value: app.arrived)
            .animation(.spring(response: 0.8, dampingFraction: 0.86), value: app.showsPolyline)
            .animation(.spring(response: 0.5, dampingFraction: 0.82), value: app.cardsExpanded)
            .animation(.spring(response: 0.5, dampingFraction: 0.7), value: app.searchOpen)
            // The search field's own focus would otherwise trigger the system's default
            // keyboard-avoidance and shove this whole screen (compass included) upward —
            // the custom results panel already handles showing results, so nothing here
            // actually needs to shift when the keyboard appears.
            .ignoresSafeArea(.keyboard, edges: .bottom)
        }
        .alert(
            "Route there?",
            isPresented: Binding(
                get: { app.mapSelectionPrompt != nil },
                set: { if !$0 { app.dismissMapSelectionPrompt() } }
            ),
            presenting: app.mapSelectionPrompt
        ) { _ in
            Button("Route") { app.confirmMapSelectionRouting() }
            Button("Not now", role: .cancel) { app.dismissMapSelectionPrompt() }
        } message: { prompt in
            Text("Get directions to \(prompt.name)?")
        }
    }

    private func closeSearch() {
        app.searchOpen = false
        searchFocused = false
    }

    /// The dial and its faint tilt guide lines — positioned relative to this one cluster's
    /// own centre, so they can never drift out of alignment with each other regardless of
    /// what sits above them on a given device.
    @ViewBuilder
    private func dialCluster(theme: AppTheme, k: CGFloat, dialSize: CGFloat) -> some View {
        ZStack {
            tiltGuideLines(theme: theme, dialSize: dialSize)

            DialView(k: k)
                .environmentObject(app)
                .frame(width: dialSize, height: dialSize)
        }
        .frame(width: dialSize, height: dialSize)
        // Reports this cluster's real centre in the screen's shared coordinate space, so
        // GuidanceLineView can extend its line to exactly that point — mathematically, not
        // by a hand-tuned offset that only happens to line up on one device.
        .background(
            GeometryReader { dialGeo in
                Color.clear.preference(key: DialCenterPreferenceKey.self, value: CGPoint(
                    x: dialGeo.frame(in: .named("compassScreen")).midX,
                    y: dialGeo.frame(in: .named("compassScreen")).midY
                ))
            }
        )
        .onPreferenceChange(DialCenterPreferenceKey.self) { dialCenter = $0 }
    }

    /// The arrival time and time remaining, side by side under the compass.
    @ViewBuilder
    private func etaRow(clock: (time: String, period: String), theme: AppTheme) -> some View {
        HStack(alignment: .center, spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(clock.time)
                    .font(.nunito(34, .black))
                    .foregroundStyle(theme.ink)
                Text(clock.period)
                    .font(.nunito(15, .extraBold))
                    .foregroundStyle(theme.ink.opacity(0.75))
            }
            Text(app.etaManager.minutesLeftText.map { "ETA · \($0)" } ?? "ETA")
                .font(.nunito(17, .black)).tracking(0.8)
                .foregroundStyle(theme.accent)
                .shadow(color: theme.accent.opacity(0.6), radius: 7)
                .padding(.horizontal, 14).padding(.vertical, 6)
                .background(Capsule().fill(theme.accent.opacity(0.16)))
                .overlay(Capsule().stroke(theme.accent.opacity(0.4), lineWidth: 1))
        }
        .lineLimit(1)
        .minimumScaleFactor(0.8)
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
        let radius = dialSize / 2
        // Drawn exactly where the dial's leaning-side edge lands at the two lean stops, so the
        // dial visibly reaches the inner pair for a Slight lean and the outer pair for a Hard one.
        let stops = [radius * AppModel.leanEdgeFactor(atDegrees: AppModel.hardLeanMax),
                     radius * AppModel.leanEdgeFactor(atDegrees: AppModel.slightLeanMax)]
        ForEach(Array(stops.enumerated()), id: \.offset) { index, half in
            ForEach([-1.0, 1.0], id: \.self) { side in
                Rectangle()
                    .fill(fade)
                    .opacity(index == 0 ? 0.3 : 0.2)
                    .frame(width: 1, height: lineHeight)
                    .offset(x: side * half)
            }
        }
    }

    /// The three anchored top pills — activity, theme toggle, Point/Guidance — fixed to
    /// the top of the screen. No floating, no dragging, no collision avoidance with the
    /// dial or destination card below: they're just always here. The activity and mode
    /// pills stretch to fill whatever width the device has, split according to their
    /// recorded reference-width ratio (`TopBarMetrics`); the theme square stays a fixed
    /// size since it has to stay square.
    @ViewBuilder
    private func topBar(theme: AppTheme, screenWidth: CGFloat) -> some View {
        let available = max(
            0,
            screenWidth - TopBarMetrics.edgePadding * 2 - TopBarMetrics.gap * 2 - TopBarMetrics.themeSquareSize
        )
        let activityWidth = available * TopBarMetrics.activityWidthRatio
        let modeWidth = available * (1 - TopBarMetrics.activityWidthRatio)

        HStack(spacing: TopBarMetrics.gap) {
            activityPill(theme: theme, width: activityWidth)
            themeSquareButton(theme: theme)
            modeTogglePill(theme: theme, width: modeWidth)
        }
        .padding(.horizontal, TopBarMetrics.edgePadding)
    }

    @ViewBuilder
    private func activityPill(theme: AppTheme, width: CGFloat) -> some View {
        let stationary = app.isStationary
        let tint = stationary ? Color.white : app.routeColor
        // The speed *is* the pill: the glowing activity dot, then the number and its unit
        // filling the whole thing, in the same weight, tracking and colour the activity label had.
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Circle()
                .fill(tint)
                .frame(width: 8, height: 8)
                .shadow(color: tint, radius: 6)
                .alignmentGuide(.firstTextBaseline) { $0[.bottom] + 9 }
            Text("\(Int(app.displaySpeed.rounded()))")
                .font(.nunito(34, .extraBold))
                .tracking(1.0)
                .foregroundStyle(theme.ink.opacity(0.86))
                .shadow(color: tint.opacity(0.55), radius: 8)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            Text(app.opts.units == "Miles" ? "mph" : "km/h")
                .font(.nunito(13, .extraBold))
                .tracking(1.0)
                .foregroundStyle(theme.ink.opacity(0.86))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .padding(.horizontal, 12)
        .frame(width: width, height: TopBarMetrics.pillHeight)
        .background(RoundedRectangle(cornerRadius: 20).fill(theme.ink.opacity(0.06)))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(theme.borderColor))
    }

    /// A small square, standalone from the mode pill now — tap to cycle light/dark, exactly
    /// as it did when it lived inside the old floating toggle. Fixed size: unlike the two
    /// pills either side of it, it doesn't flex with screen width, since it has to stay
    /// visually square.
    @ViewBuilder
    private func themeSquareButton(theme: AppTheme) -> some View {
        Button { app.toggleTheme() } label: {
            RoundedRectangle(cornerRadius: 14)
                .fill(theme.ink.opacity(0.06))
                .frame(width: TopBarMetrics.themeSquareSize, height: TopBarMetrics.themeSquareSize)
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(theme.borderColor))
                .overlay(
                    Circle()
                        .fill(theme.light ? Color(hex: "FFD86B") : theme.ink.opacity(0.22))
                        .frame(width: 16, height: 16)
                        .shadow(color: theme.light ? Color(hex: "FFD86B").opacity(0.9) : .clear, radius: 8)
                )
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.selection, trigger: app.theme)
    }

    /// The Point/Guidance switch — a single tap target now (no drag-to-move, no
    /// drag-vs-tap disambiguation), since the pill no longer moves around the screen. The
    /// track+dot sits at the pill's leading edge with an equal (12px) margin from the top,
    /// bottom, and left of the pill; the labels fill the remaining space to its right.
    @ViewBuilder
    private func modeTogglePill(theme: AppTheme, width: CGFloat) -> some View {
        let margin: CGFloat = TopBarMetrics.gap
        let dotSize: CGFloat = 13 * 1.7
        let trackWidth: CGFloat = dotSize + 6
        let trackHeight: CGFloat = TopBarMetrics.pillHeight - margin * 2

        Button { app.flipMode() } label: {
            HStack(spacing: 10) {
                ZStack(alignment: .top) {
                    RoundedRectangle(cornerRadius: trackWidth / 2)
                        .fill(theme.ink.opacity(0.14))
                        .frame(width: trackWidth, height: trackHeight)
                    Circle()
                        .fill(app.accent)
                        .frame(width: dotSize, height: dotSize)
                        .shadow(color: app.accent, radius: 6)
                        .offset(y: app.guiding ? trackHeight - dotSize : 0)
                        .animation(.spring(response: 0.5, dampingFraction: 0.7), value: app.guiding)
                }
                .padding(.leading, margin)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Point")
                        .font(.nunito(10, .extraBold))
                        .foregroundStyle(theme.ink)
                        .opacity(app.guiding ? 0.3 : 1)
                    Text("Guidance")
                        .font(.nunito(10, .extraBold))
                        .foregroundStyle(theme.ink)
                        .opacity(app.guiding ? 1 : 0.3)
                }
                .lineLimit(1)
                .minimumScaleFactor(0.7)

                Spacer(minLength: 0)
            }
            .frame(width: width, height: TopBarMetrics.pillHeight)
            .background(RoundedRectangle(cornerRadius: 20).fill(theme.ink.opacity(0.06)))
            .overlay(RoundedRectangle(cornerRadius: 20).stroke(theme.borderColor))
        }
        .buttonStyle(.plain)
        // Nowhere to guide to yet — Guidance can't be switched on until a destination is picked.
        .disabled(!app.guiding && !app.canStartGuidance)
        .opacity(!app.guiding && !app.canStartGuidance ? 0.45 : 1)
        .sensoryFeedback(.selection, trigger: app.guiding)
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

    /// A purely social/decorative roster — friends have no real location data, so unlike a
    /// place or the You page, tapping one doesn't point or route to them (there's nothing
    /// real to point at).
    @ViewBuilder
    private func friendsRow(k: CGFloat, theme: AppTheme) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: Spacing.element) {
                ForEach(Friend.all) { f in
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
                        Text(f.name)
                            .font(.nunito(11, .semibold))
                            .foregroundStyle(theme.textSecondary)
                            .lineLimit(1)
                    }
                    .frame(width: 56)
                }
            }
            .padding(.horizontal, Spacing.container * k)
        }
        .scrollClipDisabled()
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
                        Text(app.destinationCoordinate != nil ? "Real bearing · tap GUIDE" : "Straight-line pointing")
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
                            Text("GUIDE").font(.nunito(12, .black)).tracking(0.6)
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
        }
    }

    /// Shown in idle mode — no place selected, dial resting north-up.
    @ViewBuilder
    private func idleCard(theme: AppTheme) -> some View {
        HStack(spacing: Spacing.element) {
            Image(systemName: "location.north.line")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(theme.textSecondary)
            Text("Search for a place to start pointing")
                .font(.nunito(13, .semibold))
                .foregroundStyle(theme.textSecondary)
            Spacer()
        }
        .padding(.horizontal, Spacing.container + 2).padding(.vertical, Spacing.element + 4)
        .background(RoundedRectangle(cornerRadius: 22).fill(theme.ink.opacity(0.07)))
        .overlay(RoundedRectangle(cornerRadius: 22).stroke(theme.borderColor))
    }

    /// The completion screen shown once guidance detects arrival (within 10m of the
    /// destination) — guidance has nothing left to compute at that point, so this replaces
    /// the turn card/dial interaction entirely until the user taps Done.
    @ViewBuilder
    private func arrivalOverlay(theme: AppTheme) -> some View {
        ZStack {
            Color.black.opacity(0.55).ignoresSafeArea()
                .contentShape(Rectangle())

            VStack(spacing: 18) {
                ZStack {
                    Circle().fill(app.accent.opacity(0.18)).frame(width: 84, height: 84)
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 44, weight: .bold))
                        .foregroundStyle(app.accent)
                }
                VStack(spacing: 6) {
                    Text("You've arrived").font(.nunito(22, .black)).foregroundStyle(theme.ink)
                    Text(app.dest).font(.nunito(15, .semibold)).foregroundStyle(theme.textSecondary)
                }
                Button { app.endGuidance() } label: {
                    Text("DONE").font(.nunito(13, .black)).tracking(1)
                        .foregroundStyle(app.accent.onInk)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Capsule().fill(app.accent))
                }
            }
            .padding(28)
            .frame(maxWidth: 320)
            .background(RoundedRectangle(cornerRadius: 28).fill(theme.screen))
            .overlay(RoundedRectangle(cornerRadius: 28).stroke(theme.borderColor))
            .padding(.horizontal, 40)
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

/// Recent-search suggestions when the field is empty, or up to 10 real nearby-place
/// matches (via `PlaceSearch`, ranked by actual distance from the user) once they start
/// typing. The search bar itself lives above this panel and stays interactive, so there's
/// no second, redundant text field in here.
private struct SearchResultsPanel: View {
    @EnvironmentObject var app: AppModel
    let k: CGFloat
    let onClose: () -> Void

    @State private var liveResults: [MKMapItem] = []
    @State private var isSearching = false
    @State private var searchTask: Task<Void, Never>?

    var body: some View {
        let theme = app.currentTheme
        VStack(alignment: .leading, spacing: Spacing.element) {
            Text(app.searchQuery.isEmpty ? "RECENT" : "RESULTS")
                .font(.nunito(10, .extraBold)).tracking(1.6)
                .foregroundStyle(theme.textSecondary)
                .padding(.top, Spacing.container)

            if app.searchQuery.isEmpty {
                recentList(theme: theme)
            } else if isSearching && liveResults.isEmpty {
                Text("Searching…")
                    .font(.nunito(13, .semibold))
                    .foregroundStyle(theme.textSecondary)
                    .padding(.vertical, Spacing.element)
            } else if liveResults.isEmpty {
                Text("No matches for \u{201C}\(app.searchQuery)\u{201D}")
                    .font(.nunito(13, .semibold))
                    .foregroundStyle(theme.textSecondary)
                    .padding(.vertical, Spacing.element)
            } else {
                VStack(spacing: 0) {
                    ForEach(liveResults, id: \.self) { item in
                        resultRow(item, theme: theme)
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
        .onChange(of: app.searchQuery) { _, query in scheduleSearch(query) }
        .onDisappear { searchTask?.cancel() }
    }

    @ViewBuilder
    private func recentList(theme: AppTheme) -> some View {
        if app.recentSearches.isEmpty {
            Text("No recent searches yet")
                .font(.nunito(13, .semibold))
                .foregroundStyle(theme.textSecondary)
                .padding(.vertical, Spacing.element)
        } else {
            VStack(spacing: 0) {
                ForEach(app.recentSearches) { place in
                    Button {
                        app.pickRecent(place)
                        onClose()
                    } label: {
                        HStack(spacing: Spacing.element) {
                            Image(systemName: "clock.arrow.circlepath")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(theme.ink.opacity(0.76))
                                .frame(width: 34, height: 34)
                                .background(RoundedRectangle(cornerRadius: 11).fill(theme.ink.opacity(0.08)))
                            VStack(alignment: .leading, spacing: 3) {
                                Text(place.name).font(.nunito(15, .extraBold)).foregroundStyle(theme.ink).lineLimit(1)
                                if let subtitle = place.subtitle {
                                    Text(subtitle).font(.nunito(12, .semibold)).foregroundStyle(theme.textSecondary).lineLimit(1)
                                }
                            }
                            Spacer()
                        }
                        .padding(.vertical, Spacing.tight + 3).padding(.horizontal, Spacing.tight)
                        .overlay(Rectangle().fill(theme.borderColor).frame(height: 1), alignment: .bottom)
                        // The whole row is the tap target, not just its text — a short name like
                        // "Coles" would otherwise ignore taps on the empty space to its right.
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    @ViewBuilder
    private func resultRow(_ item: MKMapItem, theme: AppTheme) -> some View {
        let name = item.name ?? "Unnamed place"
        let metres = CompassManager.distance(from: app.currentPosition, to: item.placemark.coordinate)
        Button {
            app.pickPlace(mapItem: item)
            onClose()
        } label: {
            HStack(spacing: Spacing.element) {
                Image(systemName: "mappin.circle.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(theme.ink.opacity(0.76))
                    .frame(width: 34, height: 34)
                    .background(RoundedRectangle(cornerRadius: 11).fill(theme.ink.opacity(0.08)))
                VStack(alignment: .leading, spacing: 3) {
                    Text(name).font(.nunito(15, .extraBold)).foregroundStyle(theme.ink).lineLimit(1)
                    if let subtitle = subtitle(for: item) {
                        Text(subtitle).font(.nunito(12, .semibold)).foregroundStyle(theme.textSecondary).lineLimit(1)
                    }
                }
                Spacer()
                Text(CompassManager.formattedDistance(metres))
                    .font(.nunito(12, .bold)).foregroundStyle(theme.textSecondary)
            }
            .padding(.vertical, Spacing.tight + 3).padding(.horizontal, Spacing.tight)
            .overlay(Rectangle().fill(theme.borderColor).frame(height: 1), alignment: .bottom)
                        // The whole row is the tap target, not just its text — a short name like
                        // "Coles" would otherwise ignore taps on the empty space to its right.
                        .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func subtitle(for item: MKMapItem) -> String? {
        if let street = item.placemark.thoroughfare { return street }
        return item.placemark.locality
    }

    /// Debounces as the user types so every keystroke doesn't fire its own network
    /// request, then asks for the 10 nearest real matches for whatever they typed last.
    private func scheduleSearch(_ query: String) {
        searchTask?.cancel()
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            liveResults = []
            isSearching = false
            return
        }
        isSearching = true
        let origin = app.currentPosition
        searchTask = Task {
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled else { return }
            let found = await PlaceSearch.search(for: trimmed, near: origin)
            guard !Task.isCancelled else { return }
            liveResults = found
            isSearching = false
        }
    }
}
