//
//  GuidanceLineView.swift
//  ThatWay
//
//  The "road ahead" indicator shown during guidance — a curved ribbon tracing the real
//  fetched route (not a straight abstraction), projected into a forward/lateral frame
//  relative to the traveller's current position and direction of travel, so real bends in
//  the road actually show up as bends on screen. Always reaches exactly to the compass
//  dial's real on-screen centre (reported by CompassScreen, not a guessed offset), stays
//  horizontally centred on its own starting point regardless of how far off the mapped
//  road the traveller's real position is, and shows a grey branch at each upcoming turn
//  for the road *not* taken.
//
//  Two states:
//  - Loading (`guidanceData == nil`): a plain straight line to the destination with a
//    squiggly "still baking" animation, so something useful renders immediately, before
//    RouteDataGenerator finishes baking in the background.
//  - Ready: the real curved route, culled to an adaptive look-ahead distance and capped
//    near an upcoming turn, with a soft corridor band around each sampled point whose
//    radius reflects the activity's real tolerance (15m walking / 30m driving), and an end
//    marker once the destination itself falls within the look-ahead window.
//

import SwiftUI
import CoreLocation

/// Adaptive look-ahead distance, kept separate from rendering so the thresholds are easy
/// to read and verify on their own.
enum GuidanceLookAhead {
    /// Under 20 km/h, or within 500m of the next turn: 500m ahead. 20–60 km/h ramps
    /// 500m→1200m. 60–100 km/h ramps 1200m→1800m. 100+ km/h: a flat 2000m.
    static func distance(speedKmh: Double, distanceToNextTurn: CLLocationDistance) -> CLLocationDistance {
        if speedKmh < 20 || distanceToNextTurn <= 500 { return 500 }
        if speedKmh < 60 {
            let t = (speedKmh - 20) / 40
            return 500 + t * (1200 - 500)
        }
        if speedKmh < 100 {
            let t = (speedKmh - 60) / 40
            return 1200 + t * (1800 - 1200)
        }
        return 2000
    }
}

struct GuidanceLineView: View {
    let guidanceData: GuidanceData?
    /// The active route's real turn-by-turn steps — used only to place the "road not
    /// taken" branch at each real manoeuvre point, not for the main line's own geometry.
    let steps: [RouteStep]
    let currentLocation: CLLocationCoordinate2D
    let speedKmh: Double
    let activity: GuidanceActivity
    let destination: CLLocationCoordinate2D?
    let color: Color
    /// The compass dial's real on-screen centre, in the shared "compassScreen" coordinate
    /// space — the line always extends exactly to this point, mathematically, rather than
    /// a fixed pixel guess. Nil only for the first frame or two before CompassScreen's own
    /// layout has reported it.
    let dialCenter: CGPoint?
    /// Distance from the dial's centre up to its visible top edge (already accounting for
    /// its guidance scale and 3D tilt) — the route's starting point sits a fixed 20pt above
    /// that edge, and everything below it is the hidden dummy tail running behind the dial.
    let dialHalfHeight: CGFloat?
    /// True while a reroute is baking fresh guidance data to replace data that's already
    /// on screen — shows a "Recalculating…" squiggle *over* the still-visible old line,
    /// rather than the full loading state (which would otherwise flash every reroute).
    var isRecalculating: Bool = false

    @State private var squiggle: CGFloat = 0
    @State private var renderModel: RouteRenderModel?
    @State private var renderCacheKey: String?
    /// The look-ahead the ribbon is currently drawn with — eased toward the adaptive-zoom target
    /// rather than jumping, so a zoom change reads as a smooth push in/out.
    @State private var smoothedLookAhead: CLLocationDistance?
    @State private var easeTask: Task<Void, Never>?

    /// Used only before `dialCenter` has been reported at all (the very first layout
    /// pass) — everything after that extends to the dial's real measured centre instead.
    private static let fallbackExtension: CGFloat = 28

    /// Tunnel-glow constants, named (rather than inlined at each call site) so the debug
    /// log below and the actual Canvas drawing can never drift apart.
    private static let tunnelGlowWidth: CGFloat = 18
    private static let tunnelGlowOpacity: Double = 0.08
    private static let tunnelGlowBlurRadius: CGFloat = 4
    private static let tunnelCoreWidth: CGFloat = 4

    /// Side-branch tuning, named so the debug log and the actual filter/draw logic can
    /// never drift apart. Two tiers: tier 1 is a genuinely confusable "don't take this"
    /// warning at a real decision point; tier 2 is a short, faint "a real road just passed
    /// by" heartbeat — legal to turn onto, but not confusable with the route — so a long
    /// unambiguous stretch still shows periodic signs of life instead of going silent.
    private static let tier1BranchLength: CGFloat = 35
    private static let tier2BranchLength: CGFloat = 16
    private static let branchOpacityTurn: Double = 0.5
    private static let branchOpacityRoundaboutExit: Double = 0.4
    /// Tier 2 reads at 70% of its tier-1 counterpart's opacity.
    private static let tier2Scale: Double = 0.7
    private static let tier2Opacity: Double = branchOpacityTurn * tier2Scale
    private static let tier2RoundaboutOpacity: Double = branchOpacityRoundaboutExit * tier2Scale
    /// A plain turn's alternative has to differ from the road actually taken by at least
    /// this much to count as a genuinely different option, not the same carriageway.
    private static let branchBearingDiffThreshold: CLLocationDirection = 30
    /// A roundabout exit only reads as "you could take this by mistake" if it sits within
    /// this many degrees of the exit you're actually meant to take — further away and it's
    /// obviously a different exit, not a plausible slip.
    private static let roundaboutExitConfusionThreshold: CLLocationDirection = 45
    /// Minimum real-world gap between tier-2 ambient ticks — OSRM's own graph nodes can sit
    /// only a few metres apart, so without this a dense run of them would redraw the same
    /// "still tracking" signal over and over instead of reading as a steady heartbeat.
    private static let tier2MinSpacingWalking: CLLocationDistance = 40
    private static let tier2MinSpacingDriving: CLLocationDistance = 60

    /// Discrete activity colour for the route ribbon: blue while driving, green while
    /// walking, white once speed drops to a standstill — distinct from `AppModel.routeColor`
    /// (a continuous walk→run→drive blend used elsewhere), since this ribbon should read as
    /// one of three clear states rather than smoothly interpolate.
    private var polylineColor: Color {
        if speedKmh <= 2 { return .white }
        return activity == .driving ? Color(hex: "3B82F6") : Color(hex: "2FCF9B")
    }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .top) {
                if let guidanceData {
                    readyLine(geo: geo, data: guidanceData)
                    if isRecalculating {
                        recalculatingOverlay(geo: geo)
                    }
                } else {
                    loadingLine(geo: geo, caption: "Loading your guideline")
                }
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true)) { squiggle = 1 }
        }
    }

    /// `dialCenter` (in the shared "compassScreen" space) converted into this view's own
    /// local coordinates — the actual point any drawing in here needs to reach.
    private func localDialCenter(geo: GeometryProxy) -> CGPoint? {
        guard let dialCenter else { return nil }
        let frame = geo.frame(in: .named("compassScreen"))
        return CGPoint(x: dialCenter.x - frame.minX, y: dialCenter.y - frame.minY)
    }

    // MARK: - Loading state

    /// Fast, cheap to render — a plain line to the destination plus a squiggle that draws
    /// and undoes itself, so the user sees *something* the instant guidance starts, rather
    /// than a blank gap while the background bake finishes. Used for the very first bake
    /// (no data at all yet) — a reroute's re-bake uses `recalculatingOverlay` instead, since
    /// there's already a real line to keep showing.
    @ViewBuilder
    private func loadingLine(geo: GeometryProxy, caption: String) -> some View {
        let bottom = localDialCenter(geo: geo)?.y ?? (geo.size.height + Self.fallbackExtension)

        ZStack(alignment: .top) {
            LinearGradient(
                stops: [.init(color: .clear, location: 0), .init(color: polylineColor.opacity(0.6), location: 0.14), .init(color: polylineColor.opacity(0.85), location: 1)],
                startPoint: .top, endPoint: .bottom
            )
            .frame(width: 3)
            .clipShape(Capsule())
            .frame(maxWidth: .infinity)
            .frame(height: bottom, alignment: .top)

            SquigglePath(amplitude: 5, wavelength: 26)
                .trim(from: squiggle > 0.5 ? squiggle - 0.5 : 0, to: min(squiggle + 0.5, 1))
                .stroke(Color.white.opacity(0.55), style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .frame(width: 28, height: bottom, alignment: .top)
                .frame(maxWidth: .infinity)

            endMarker(color: polylineColor)
                .frame(maxWidth: .infinity)

            Text(caption)
                .font(.nunito(9, .semibold))
                .foregroundStyle(.white.opacity(0.4))
                .frame(maxWidth: .infinity)
                .frame(height: bottom, alignment: .bottom)
                .padding(.bottom, 4)
        }
    }

    /// Sits on top of the still-visible, now-stale `readyLine` while a reroute's fresh
    /// corridor bakes in the background — a squiggle plus a small pill of text, not a full
    /// replacement, so the user never loses the line entirely mid-reroute.
    @ViewBuilder
    private func recalculatingOverlay(geo: GeometryProxy) -> some View {
        let bottom = localDialCenter(geo: geo)?.y ?? (geo.size.height + Self.fallbackExtension)
        ZStack(alignment: .top) {
            SquigglePath(amplitude: 5, wavelength: 26)
                .trim(from: squiggle > 0.5 ? squiggle - 0.5 : 0, to: min(squiggle + 0.5, 1))
                .stroke(Color.white.opacity(0.75), style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .frame(width: 28, height: bottom, alignment: .top)
                .frame(maxWidth: .infinity)

            Text("Recalculating…")
                .font(.nunito(9, .extraBold))
                .foregroundStyle(.white.opacity(0.85))
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(Capsule().fill(Color.black.opacity(0.4)))
                .frame(maxWidth: .infinity)
                .frame(height: bottom, alignment: .bottom)
                .padding(.bottom, 4)
        }
    }

    // MARK: - Ready state

    @ViewBuilder
    private func readyLine(geo: GeometryProxy, data: GuidanceData) -> some View {
        let dialCenterLocal = localDialCenter(geo: geo)
        let dialTopLocal: CGFloat? = dialCenterLocal.flatMap { center in dialHalfHeight.map { center.y - $0 } }
        let key = cacheKey(data: data, size: geo.size, dialCenterLocal: dialCenterLocal, dialTopLocal: dialTopLocal)
        let model = renderModel

        ZStack(alignment: .topLeading) {
            if let model {
                Canvas { context, size in
                    // The corridor circles' geometry (position + real-world 15m/30m radius
                    // projected to screen) is still computed every render — nothing about
                    // off-route detection reads it, that's entirely `RoutingManager`'s own
                    // nearest-point math against the real corridor radius, independent of
                    // anything drawn here — but the shapes are kept and drawn at zero
                    // opacity rather than skipped outright, so a future visual toggle has
                    // real geometry to flip back on rather than needing to be rebuilt.
                    for sample in model.corridorSamples {
                        let rect = CGRect(
                            x: sample.point.x - sample.radius, y: sample.point.y - sample.radius,
                            width: sample.radius * 2, height: sample.radius * 2
                        )
                        context.fill(Path(ellipseIn: rect), with: .color(polylineColor.opacity(0)))
                    }

                    // Tunnel glow: a wide, soft, blurred halo underneath a crisp core line —
                    // scoped to its own layer so the blur doesn't smear the branches or the
                    // branches drawn on top of it.
                    context.drawLayer { glowContext in
                        glowContext.addFilter(.blur(radius: Self.tunnelGlowBlurRadius))
                        glowContext.stroke(
                            model.path,
                            with: .color(polylineColor.opacity(Self.tunnelGlowOpacity)),
                            style: StrokeStyle(lineWidth: Self.tunnelGlowWidth, lineCap: .round, lineJoin: .round)
                        )
                    }
                    // Grey "not this way" branches — drawn over the glow halo (which would
                    // otherwise wash out the faint tier-2 ticks) but under the crisp core line.
                    for branch in model.sideBranches {
                        var branchPath = Path()
                        branchPath.move(to: branch.point)
                        branchPath.addLine(to: branch.end)
                        context.stroke(branchPath, with: .color(Color(hex: "666666").opacity(branch.opacity)), style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    }

                    context.stroke(
                        model.path,
                        with: .color(polylineColor),
                        style: StrokeStyle(lineWidth: Self.tunnelCoreWidth, lineCap: .round, lineJoin: .round)
                    )
                    // Current-location marker: a small arrow in the route colour with a black border,
                    // fixed at 15pt tall at every zoom. It sits on the hidden dummy line *below* where
                    // the real route starts (never on the route itself), so the route — and the
                    // destination flag at its end — always finishes in front of it, never on top of it.
                    let markerHeight: CGFloat = 15
                    let markerCenter = CGPoint(x: model.nearPoint.x, y: model.nearPoint.y + 12)
                    var arrow = Path()
                    arrow.move(to: CGPoint(x: markerCenter.x, y: markerCenter.y - markerHeight / 2))
                    arrow.addLine(to: CGPoint(x: markerCenter.x + 6, y: markerCenter.y + markerHeight / 2))
                    arrow.addLine(to: CGPoint(x: markerCenter.x, y: markerCenter.y + markerHeight / 2 - 4))
                    arrow.addLine(to: CGPoint(x: markerCenter.x - 6, y: markerCenter.y + markerHeight / 2))
                    arrow.closeSubpath()
                    context.fill(arrow, with: .color(polylineColor))
                    context.stroke(arrow, with: .color(.black), style: StrokeStyle(lineWidth: 1.2, lineJoin: .round))
                }
                // Canvas clips its own drawing to its layout frame — since the tail
                // deliberately draws past `geo.size.height` down to the dial's real centre,
                // the Canvas itself needs to be at least that tall, top-aligned so its
                // (0, 0) origin — and every point `buildRenderModel` computed against
                // `geo.size` — stays exactly where it was.
                .frame(width: geo.size.width, height: max(geo.size.height, model.tailPoint.y), alignment: .top)

                // Only shown once the destination itself falls inside the look-ahead
                // window — otherwise the line trails off into "more road ahead" with
                // nothing to mark yet.
                if let endMarkerPosition = model.endMarkerPosition {
                    endMarker(color: polylineColor)
                        .position(endMarkerPosition)
                }
            }
        }
        .onAppear { updateRenderModelIfNeeded(key: key, data: data, size: geo.size, dialCenterLocal: dialCenterLocal, dialTopLocal: dialTopLocal) }
        .onChange(of: key) { _, newKey in updateRenderModelIfNeeded(key: newKey, data: data, size: geo.size, dialCenterLocal: dialCenterLocal, dialTopLocal: dialTopLocal) }
    }

    /// One sampled point of the rendered route, in view-local screen coordinates, plus the
    /// pixel radius its real-world corridor tolerance projects to at that depth.
    private struct CorridorSample {
        let point: CGPoint
        let radius: CGFloat
    }

    /// A grey tick at a turn point showing the direction of the road *not* taken —
    /// `point` is the manoeuvre's own on-screen position, `end` the tick's far end.
    /// `opacity` differs by kind: a plain turn's one alternative reads at 50%, a
    /// roundabout's confusable exit at a subtler 40% (there can be up to two of them).
    private struct SideBranch {
        let point: CGPoint
        let end: CGPoint
        let opacity: Double
    }

    /// The cached result of projecting `GuidanceData`'s waypoints into screen space —
    /// rebuilt only when `cacheKey` actually changes (a new bake, the traveller's nearest
    /// waypoint moving on, the container resizing, or the dial's own centre moving), not
    /// on every render.
    private struct RouteRenderModel {
        let path: Path
        let corridorSamples: [CorridorSample]
        let endMarkerPosition: CGPoint?
        let sideBranches: [SideBranch]
        /// 0 while inside the route's own corridor tolerance, ramping to 1 as the
        /// traveller gets further outside it — drives the fabricated connector's opacity.
        let offRoadLineOpacity: Double
        let tailPoint: CGPoint
        let nearPoint: CGPoint
        /// Baseline look-ahead ÷ the look-ahead actually used (≥ 1) — how far the adaptive zoom has
        /// pushed in — and the look-ahead the zoom is heading toward.
        let zoomFactor: CGFloat
        let targetLookAhead: CLLocationDistance
    }

    /// Cheap fingerprint of everything that actually changes the rendered geometry — a new
    /// bake (`generatedAt`), the traveller having moved, the container resizing, or the
    /// dial's own centre moving. Used to skip rebuilding `renderModel` on renders that
    /// don't touch any of these (e.g. a purely animated state that never touches geometry).
    private func cacheKey(data: GuidanceData, size: CGSize, dialCenterLocal: CGPoint?, dialTopLocal: CGFloat?) -> String {
        "\(data.generatedAt.timeIntervalSince1970)|\(Int(currentLocation.latitude * 1_000_000))|\(Int(currentLocation.longitude * 1_000_000))|\(Int(size.width))x\(Int(size.height))|\(Int(speedKmh))|\(Int(dialCenterLocal?.x ?? -1))x\(Int(dialCenterLocal?.y ?? -1))|\(steps.count)"
    }

    private func updateRenderModelIfNeeded(key: String, data: GuidanceData, size: CGSize, dialCenterLocal: CGPoint?, dialTopLocal: CGFloat?) {
        guard key != renderCacheKey else { return }
        renderCacheKey = key
        easeTask?.cancel()
        rebuildModel(data: data, size: size, dialCenterLocal: dialCenterLocal, dialTopLocal: dialTopLocal, log: true)

        print("4. VISUAL RENDERING:")
        print("   - Main polyline colour: \(polylineColor)")
        print("   - Glow opacity: \(Self.tunnelGlowOpacity), blur radius: \(Self.tunnelGlowBlurRadius)pt")
        print("   - Tunnel width: \(Self.tunnelCoreWidth)pt core, \(Self.tunnelGlowWidth)pt glow")

        // A zoom target that moved since the last frame is eased toward over a few dozen
        // milliseconds of cheap re-projections (a few dozen points each) instead of snapping.
        guard let target = renderModel?.targetLookAhead, let current = smoothedLookAhead, abs(target - current) > 1.5 else { return }
        easeTask = Task { @MainActor in
            while !Task.isCancelled {
                guard let current = smoothedLookAhead, let target = renderModel?.targetLookAhead else { return }
                let remaining = target - current
                let done = abs(remaining) < 1.5
                smoothedLookAhead = done ? target : current + remaining * 0.28
                rebuildModel(data: data, size: size, dialCenterLocal: dialCenterLocal, dialTopLocal: dialTopLocal, log: false)
                if done { return }
                try? await Task.sleep(nanoseconds: 40_000_000)
            }
        }
    }

    private func rebuildModel(data: GuidanceData, size: CGSize, dialCenterLocal: CGPoint?, dialTopLocal: CGFloat?, log: Bool) {
        let model = Self.buildRenderModel(data: data, steps: steps, currentLocation: currentLocation, speedKmh: speedKmh, activity: activity, size: size, dialCenterLocal: dialCenterLocal, dialTopLocal: dialTopLocal, fallbackExtension: Self.fallbackExtension, lookAheadOverride: smoothedLookAhead, log: log)
        renderModel = model
        if smoothedLookAhead == nil { smoothedLookAhead = model?.targetLookAhead }
    }

    /// One route waypoint projected into a forward/lateral frame centred on the traveller,
    /// facing the direction they're actually travelling (the nearest waypoint's own
    /// bearing) — this is what turns real lat/lon geometry into an on-screen ribbon that
    /// curves the way the real road does, rather than a straight line to the destination.
    private struct ProjectedWaypoint {
        let forward: CLLocationDistance
        let lateral: CLLocationDistance
        let corridorRadius: CLLocationDistance
        let distanceFromStart: CLLocationDistance
    }

    /// The real per-frame(ish) math: finds the baked waypoint nearest the traveller,
    /// derives the adaptive look-ahead from real speed and real distance-to-next-turn,
    /// projects every waypoint from there forward into forward/lateral metres relative to
    /// the traveller's position and direction of travel, culls anything behind them or past
    /// the look-ahead window, recentres the whole set so the traveller's own nearest point
    /// sits exactly on the screen's horizontal centre (however far off the mapped road they
    /// really are), then maps the survivors into screen space with a simple perspective
    /// taper before smoothing them into one continuous curve down to the dial's real centre.
    nonisolated private static func buildRenderModel(
        data: GuidanceData,
        steps: [RouteStep],
        currentLocation: CLLocationCoordinate2D,
        speedKmh: Double,
        activity: GuidanceActivity,
        size: CGSize,
        dialCenterLocal: CGPoint?,
        dialTopLocal: CGFloat?,
        fallbackExtension: CGFloat,
        lookAheadOverride: CLLocationDistance?,
        log: Bool
    ) -> RouteRenderModel? {
        guard let nearest = data.waypoints.min(by: {
            CompassManager.distance(from: currentLocation, to: $0.coordinate)
                < CompassManager.distance(from: currentLocation, to: $1.coordinate)
        }) else { return nil }

        let baselineLookAhead = GuidanceLookAhead.distance(speedKmh: speedKmh, distanceToNextTurn: nearest.distanceToNextTurn)
        let referenceBearing = nearest.bearing
        let candidates = data.waypoints.filter { $0.distanceFromStart >= nearest.distanceFromStart }

        // Projects any coordinate into (forward, lateral) metres relative to the
        // traveller's current position, "forward" meaning along `referenceBearing".
        func project(_ coordinate: CLLocationCoordinate2D) -> (forward: CLLocationDistance, lateral: CLLocationDistance) {
            let d = CompassManager.distance(from: currentLocation, to: coordinate)
            guard d > 0 else { return (0, 0) }
            let bearingToPoint = CompassManager.bearing(from: currentLocation, to: coordinate)
            let relative = CompassManager.relativeBearing(heading: referenceBearing, bearing: bearingToPoint).radians
            return (d * cos(relative), d * sin(relative))
        }

        // MARK: Adaptive zoom
        // Straight and gently bending roads keep the normal speed-based look-ahead. When a real
        // turn, exit, roundabout, sharp bend or the destination is inside that window, the
        // view pushes in so that feature — and the road leading to it — lands ~10% below the top
        // of the screen instead of sitting tiny in the middle of a 500m+ window.
        let complexTypes: Set<String> = ["turn", "end of road", "fork", "roundabout", "rotary", "roundabout turn", "exit roundabout", "exit rotary", "on ramp", "off ramp", "merge"]
        var zoomTarget = baselineLookAhead
        var zoomNote = "no turn, exit, roundabout, sharp bend or arrival inside the window — baseline look-ahead kept"
        for step in steps.dropFirst() {
            let modifier = step.maneuverModifier ?? ""
            let isArrival = step.maneuverType == "arrive"
            let isSharp = modifier.contains("sharp") || modifier == "uturn"
            let bendsGently = modifier.contains("slight") && !["roundabout", "rotary", "fork"].contains(step.maneuverType)
            guard isArrival || isSharp || (complexTypes.contains(step.maneuverType) && !bendsGently) else { continue }
            let coordinate = step.intersections.first?.coordinate ?? step.startCoordinate
            guard let along = data.waypoints.min(by: {
                CompassManager.distance(from: coordinate, to: $0.coordinate) < CompassManager.distance(from: coordinate, to: $1.coordinate)
            })?.distanceFromStart, along >= nearest.distanceFromStart - 5 else { continue }
            // Steps run in route order, so the first one still ahead is the nearest feature.
            if along - nearest.distanceFromStart <= baselineLookAhead {
                let nearLateral = project(nearest.coordinate).lateral
                var maxForward: CLLocationDistance = 0
                var maxLateral: CLLocationDistance = 0
                for waypoint in candidates where waypoint.distanceFromStart <= along + 25 {
                    let p = project(waypoint.coordinate)
                    maxForward = max(maxForward, p.forward)
                    maxLateral = max(maxLateral, abs(p.lateral - nearLateral))
                }
                // 0.9 → the feature ends up 10% from the top; 0.22 × 0.9 → its sideways extent fits.
                zoomTarget = min(baselineLookAhead, max(90, maxForward / 0.9, maxLateral / (0.22 * 0.9)))
                zoomNote = "\(step.maneuverType) \(modifier) at +\(Int(along - nearest.distanceFromStart))m, farthest point \(Int(maxForward))m ahead → look-ahead \(Int(zoomTarget))m"
            }
            break
        }
        let lookAhead = min(baselineLookAhead, max(45, lookAheadOverride ?? zoomTarget))

        func out(_ text: @autoclosure () -> String) { if log { print(text()) } }

        out("=== GUIDANCE LINE WORKFLOW ===")
        out("1. INPUT DATA:")
        out("   - Baked waypoints (resampled ~15m apart — this view never sees RoutingManager's raw OSRM polyline directly): \(data.waypoints.count)")
        out("   - OSRM steps (turns): \(steps.count)")
        out("   - User location: \(currentLocation.latitude), \(currentLocation.longitude)")
        out("   - Baseline look-ahead: \(baselineLookAhead)m; adaptive zoom: \(zoomNote); drawing with \(Int(lookAhead))m")

        var projected: [ProjectedWaypoint] = []
        projected.reserveCapacity(candidates.count)
        for waypoint in candidates {
            let (forward, lateral) = project(waypoint.coordinate)
            // Anything projecting behind the traveller (already passed, or a road that
            // loops back on itself) is culled — only what's genuinely ahead gets drawn.
            guard forward > -5 else { continue }
            projected.append(ProjectedWaypoint(forward: forward, lateral: lateral, corridorRadius: waypoint.corridorRadius, distanceFromStart: waypoint.distanceFromStart))
            if forward >= lookAhead { break }
        }
        guard !projected.isEmpty else { return nil }

        out("2. POLYLINE FILTERING:")
        out("   - Candidates considered (from nearest waypoint onward): \(candidates.count)")
        out("   - Points within look-ahead (survived culling): \(projected.count)")
        out("   - Points culled (behind traveller, or past the look-ahead window — this loop stops early so it never even reaches the rest): \(candidates.count - projected.count)")

        // Recentring correction: whatever lateral offset the traveller's real position has
        // from the route's own nearest point, subtract it from every point so the ribbon
        // always starts dead-centre on screen — the road's true relative shape beyond that
        // is preserved exactly, just the whole thing is shifted to start centred.
        let rawNearLateral = projected[0].lateral
        let rawNearForward = projected[0].forward
        let maxLateralPixels = min(size.width, 260) * 0.34
        let lateralClamp = max(30, lookAhead * 0.22)

        // The traveller's own position (forward == 0) always sits exactly 20pt above the
        // dial's visible top edge — the route rises from there, and the line continues
        // *below* it as a hidden dummy tail running behind the dial, so reaching the
        // destination puts its marker at most 20pt above the compass.
        let userY = max(60, dialTopLocal.map { $0 - 20 } ?? size.height)

        // Flat 2D for every activity (distance maps linearly to height) — it gives the
        // clearest read of upcoming turns, driving included.
        func visualFrac(_ forward: CLLocationDistance) -> CGFloat {
            min(1, max(0, CGFloat(forward / lookAhead)))
        }
        func depthScale(_ forward: CLLocationDistance) -> CGFloat {
            1 - visualFrac(forward) * 0.55
        }

        func screenPoint(forward: CLLocationDistance, lateral: CLLocationDistance) -> CGPoint {
            let depth = depthScale(forward)
            let normalizedLateral = max(-1, min(1, lateral / lateralClamp))
            let x = size.width / 2 + normalizedLateral * maxLateralPixels * depth
            let y = userY * (1 - visualFrac(forward))
            return CGPoint(x: x, y: y)
        }

        let rawNearScreenX = screenPoint(forward: rawNearForward, lateral: rawNearLateral).x
        let offset = rawNearScreenX - size.width / 2
        out("[GuidanceLineView] Polyline X offset: \(offset)")

        let corrected = projected.map {
            ProjectedWaypoint(forward: $0.forward, lateral: $0.lateral - rawNearLateral, corridorRadius: $0.corridorRadius, distanceFromStart: $0.distanceFromStart)
        }
        let screenPoints = corrected.map { screenPoint(forward: $0.forward, lateral: $0.lateral) }

        let corridorSamples: [CorridorSample] = zip(corrected, screenPoints).map { p, pt in
            let depth = depthScale(p.forward)
            let radiusPixels = CGFloat(p.corridorRadius) * (maxLateralPixels / lateralClamp) * depth
            return CorridorSample(point: pt, radius: max(4, radiusPixels))
        }

        // Extends mathematically to the dial's own real centre rather than a fixed pixel
        // guess — falls back to a small fixed amount only if that centre hasn't been
        // reported yet (the first layout pass).
        let nearPoint = screenPoints[0]
        let tailTarget = dialCenterLocal ?? CGPoint(x: nearPoint.x, y: size.height + fallbackExtension)
        let tailPoint = CGPoint(x: nearPoint.x, y: max(nearPoint.y, tailTarget.y))

        var path = Path()
        path.move(to: tailPoint)
        path.addLine(to: nearPoint)
        if screenPoints.count > 1 {
            // Smooths the polyline into one continuous curve (each interior vertex becomes
            // a quad-curve control point rather than a hard corner) instead of drawing
            // individual straight segments.
            for i in 0..<(screenPoints.count - 1) {
                let current = screenPoints[i]
                let next = screenPoints[i + 1]
                let mid = CGPoint(x: (current.x + next.x) / 2, y: (current.y + next.y) / 2)
                path.addQuadCurve(to: mid, control: current)
            }
            path.addLine(to: screenPoints[screenPoints.count - 1])
        }

        let destinationInSight = (corrected.last?.distanceFromStart ?? -1) >= data.totalDistance - 1
        let endMarkerPosition = destinationInSight ? screenPoints.last : nil

        // Grey branches at real decision points — a step's *own first* intersection is
        // exactly where the previous step ends and this one's manoeuvre happens (its
        // location matches `maneuver.location`), not one of the many cross-streets a long
        // step's road simply passes over along the way. Restricting a plain street to this
        // one node (rather than every intersection OSRM reports along the full road) is
        // what keeps it from drawing a branch at every cross-street it isn't deciding
        // between. A "roundabout" step is different: OSRM models the *whole* circle as one
        // step, so every exit passed along the way is a real intersection of its own,
        // handled separately below rather than being thrown out along with the plain-road
        // cross-streets its first-node-only restriction is meant to exclude.
        var sideBranches: [SideBranch] = []

        // Angular separation between two true-north bearings, always in [0, 180] — the
        // short way round the compass, never the long way.
        func angularDiff(_ a: CLLocationDirection, _ b: CLLocationDirection) -> CLLocationDirection {
            let diff = abs(a - b).truncatingRemainder(dividingBy: 360)
            return min(diff, 360 - diff)
        }

        // A screen-space unit vector for a real bearing, relative to the direction of
        // travel — isotropic (no dependence on the route ribbon's own forward/lateral
        // scale or perspective taper), so a real right-angle street reads as a right angle
        // on screen no matter where along the ribbon it sits.
        func branchDirection(for bearing: CLLocationDirection) -> CGPoint {
            let relative = CompassManager.relativeBearing(heading: referenceBearing, bearing: bearing).radians
            return CGPoint(x: sin(relative), y: -cos(relative))
        }

        // A plain turn point: at most one tier-1 branch, for the single most significant
        // road not taken — the road actually taken (`in`/`out`) is already excluded from
        // `otherBearings` upstream in RoutingManager, so every candidate here really is a
        // different road meeting at this intersection. A legal road that doesn't clear the
        // "confusing" bar still gets a short tier-2 tick rather than nothing — only a road
        // you genuinely can't turn onto renders as nothing at all.
        @discardableResult
        func appendTurnBranch(at turnPoint: RouteIntersection, stepBearing: CLLocationDirection, label: String) -> Int {
            let (turnForward, turnLateralRaw) = project(turnPoint.coordinate)
            out("   [Branch] \(label):")
            guard turnForward > -5, turnForward <= lookAhead else {
                out("     - Outside the look-ahead window, skipped")
                return 0
            }
            let turnLateral = turnLateralRaw - rawNearLateral
            let turnScreen = screenPoint(forward: turnForward, lateral: turnLateral)
            let currentBearing = turnPoint.outBearing ?? stepBearing

            let rawCount = turnPoint.otherBearings.count
            // `entry == true` is OSRM's own answer to "can you actually turn onto this
            // road from here" — false means a one-way street the wrong way or a
            // restricted turn, physically there but never a real option.
            let entryFiltered = turnPoint.otherBearings
                .filter(\.entry)
                .map { (bearing: $0.bearing, diff: angularDiff($0.bearing, currentBearing)) }
            let bearingFiltered = entryFiltered
                .filter { $0.diff >= Self.branchBearingDiffThreshold }
                .sorted { $0.diff > $1.diff } // Largest difference = most significant alternative.

            out("     - otherBearings count: \(rawCount)")
            out("     - After entry filter (entry == true): \(entryFiltered.count)")
            out("     - After bearing filter (\(Int(Self.branchBearingDiffThreshold))°+): \(bearingFiltered.count)")

            guard let top = bearingFiltered.first else {
                // Legal but not a genuinely different option (within the same-carriageway
                // band) — still a real road, so it earns the short ambient tick rather than
                // vanishing outright.
                guard let fallback = entryFiltered.max(by: { $0.diff < $1.diff }) else {
                    out("     - After name dedup: 0")
                    out("     - Rendering: NO (no legal alternative at all)")
                    return 0
                }
                out("     - After name dedup: 0 (none confusing)")
                let direction = branchDirection(for: fallback.bearing)
                let branchEnd = CGPoint(x: turnScreen.x + direction.x * Self.tier2BranchLength, y: turnScreen.y + direction.y * Self.tier2BranchLength)
                sideBranches.append(SideBranch(point: turnScreen, end: branchEnd, opacity: Self.tier2Opacity))
                out("     - Rendering: TIER 2 (legal, \(Int(fallback.diff))° offset — not confusing enough for tier 1)")
                return 1
            }
            // The step-name/roundabout-continuation dedup that would skip this branch
            // entirely already ran before this function was ever called (see the loop
            // below) — reaching here means it passed, so the count carries straight
            // through unchanged.
            out("     - After name dedup: 1")

            let direction = branchDirection(for: top.bearing)
            let branchEnd = CGPoint(x: turnScreen.x + direction.x * Self.tier1BranchLength, y: turnScreen.y + direction.y * Self.tier1BranchLength)
            sideBranches.append(SideBranch(point: turnScreen, end: branchEnd, opacity: Self.branchOpacityTurn))
            out("     - Rendering: TIER 1 (grey branch at \(Int(top.diff))° offset)")
            return 1
        }

        // A roundabout's own internal exit point: up to two tier-1 branches, only for exits
        // close enough to the one actually taken to be a plausible slip — an exit 150° away
        // is obviously wrong, so it falls back to a tier-2 tick (still a real, legal exit)
        // rather than a bold warning.
        @discardableResult
        func appendRoundaboutExitBranches(at exitPoint: RouteIntersection, actualExitBearing: CLLocationDirection, label: String) -> Int {
            let (turnForward, turnLateralRaw) = project(exitPoint.coordinate)
            out("   [Roundabout exit] \(label):")
            guard turnForward > -5, turnForward <= lookAhead else {
                out("     - Outside the look-ahead window, skipped")
                return 0
            }
            let turnLateral = turnLateralRaw - rawNearLateral
            let turnScreen = screenPoint(forward: turnForward, lateral: turnLateral)

            let rawCount = exitPoint.otherBearings.count
            let entryFiltered = exitPoint.otherBearings
                .filter(\.entry)
                .map { (bearing: $0.bearing, diff: angularDiff($0.bearing, actualExitBearing)) }
            let confusable = entryFiltered
                .filter { $0.diff <= Self.roundaboutExitConfusionThreshold }
                .sorted { $0.diff < $1.diff } // Closest to the real exit = most confusable, ranked first.
                .prefix(2)

            out("     - otherBearings count: \(rawCount)")
            out("     - After entry filter (entry == true): \(entryFiltered.count)")
            out("     - Within \(Int(Self.roundaboutExitConfusionThreshold))° of your real exit bearing (\(Int(actualExitBearing))°): \(confusable.count)")

            guard !confusable.isEmpty else {
                guard let fallback = entryFiltered.min(by: { $0.diff < $1.diff }) else {
                    out("     - Rendering: NO (no legal exit at all)")
                    return 0
                }
                let direction = branchDirection(for: fallback.bearing)
                let branchEnd = CGPoint(x: turnScreen.x + direction.x * Self.tier2BranchLength, y: turnScreen.y + direction.y * Self.tier2BranchLength)
                sideBranches.append(SideBranch(point: turnScreen, end: branchEnd, opacity: Self.tier2RoundaboutOpacity))
                out("     - Rendering: TIER 2 (legal exit, \(Int(fallback.diff))° from your real exit — not confusing enough for tier 1)")
                return 1
            }
            for candidate in confusable {
                let direction = branchDirection(for: candidate.bearing)
                let branchEnd = CGPoint(x: turnScreen.x + direction.x * Self.tier1BranchLength, y: turnScreen.y + direction.y * Self.tier1BranchLength)
                sideBranches.append(SideBranch(point: turnScreen, end: branchEnd, opacity: Self.branchOpacityRoundaboutExit))
                out("     - Rendering: TIER 1, roundabout exit alternative at \(Int(candidate.diff))° from your real exit")
            }
            return confusable.count
        }

        // The "still tracking" heartbeat: every OSRM node a plain (non-roundabout) step
        // passes over that it isn't itself a decision point — never a tier-1 warning,
        // since nothing here is actually a fork the traveller is choosing between, just a
        // real road going by. Throttled by real distance travelled (not by node count,
        // which OSRM can pack densely) so it reads as a steady, sparse pulse rather than a
        // cluster of ticks at every graph vertex.
        var lastAmbientForward: CLLocationDistance = -.infinity
        let tier2MinSpacing = activity == .driving ? Self.tier2MinSpacingDriving : Self.tier2MinSpacingWalking
        var ambientTickCount = 0

        @discardableResult
        func appendAmbientTick(at point: RouteIntersection, label: String) -> Int {
            let (turnForward, turnLateralRaw) = project(point.coordinate)
            guard turnForward > -5, turnForward <= lookAhead else { return 0 }
            guard turnForward - lastAmbientForward >= tier2MinSpacing else { return 0 }
            guard let candidate = point.otherBearings.first(where: \.entry) else { return 0 }
            lastAmbientForward = turnForward
            let turnLateral = turnLateralRaw - rawNearLateral
            let turnScreen = screenPoint(forward: turnForward, lateral: turnLateral)
            let direction = branchDirection(for: candidate.bearing)
            let branchEnd = CGPoint(x: turnScreen.x + direction.x * Self.tier2BranchLength, y: turnScreen.y + direction.y * Self.tier2BranchLength)
            sideBranches.append(SideBranch(point: turnScreen, end: branchEnd, opacity: Self.tier2Opacity))
            ambientTickCount += 1
            out("   [Ambient] \(label) at \(Int(turnForward))m: real road passing by, tier 2 tick")
            return 1
        }

        var branchCountByStepIndex: [Int: Int] = [:]

        // `steps[0]` (the depart step) never appears as `step` in the pairing below — only
        // as `previousStep` — so its own interior nodes need their own pass here, *before*
        // the main loop, since `lastAmbientForward` only advances monotonically forward:
        // running this after would compare an early node's small `forward` against a
        // throttle baseline already pushed far down the route by later steps and wrongly
        // suppress it.
        if let departStep = steps.first, departStep.maneuverType != "roundabout" {
            for (nodeIndex, intersection) in departStep.intersections.dropFirst().enumerated() {
                _ = appendAmbientTick(at: intersection, label: "step 0 at \(departStep.name.isEmpty ? "(unnamed)" : departStep.name), node \(nodeIndex + 1)")
            }
        }

        for (pairIndex, (previousStep, step)) in zip(steps, steps.dropFirst()).enumerated() {
            let stepIndex = pairIndex + 1 // `steps.dropFirst()` shifts every index by one.
            guard let turnPoint = step.intersections.first else { continue }
            let isRoundabout = step.maneuverType == "roundabout"
            var branchCount = 0
            let stepLabel = "step \(stepIndex) at \(step.name.isEmpty ? "(unnamed)" : step.name)"

            // Same named road continuing (OSRM sometimes splits one physical road into
            // several steps for a gentle bend or a name change elsewhere) isn't a real
            // decision — nothing to show a "not taken" alternative against.
            var skipOwnTurnPoint = step.name == previousStep.name

            // Two consecutive "roundabout" steps that barely moved and barely changed
            // heading are still the same lap of the same roundabout at the point they
            // meet, not a distinct exit worth flagging there — its *real* exits are
            // handled by the loop below, over this step's own intersections.
            if !skipOwnTurnPoint, isRoundabout, previousStep.maneuverType == "roundabout" {
                let previousPoint = previousStep.intersections.first?.coordinate ?? previousStep.startCoordinate
                let hopDistance = CompassManager.distance(from: previousPoint, to: turnPoint.coordinate)
                let bearingDiff = angularDiff(step.bearing, previousStep.bearing)
                if hopDistance < 10, bearingDiff < 10 { skipOwnTurnPoint = true }
            }

            if skipOwnTurnPoint {
                out("For \(stepLabel): skipped — same road as previous step, or a same-roundabout micro-continuation")
            } else {
                branchCount += appendTurnBranch(at: turnPoint, stepBearing: step.bearing, label: stepLabel)
            }

            // Every exit the roundabout's own road passes on the way to the one actually
            // taken — real intersections in their own right, not cross-traffic to ignore.
            // "Your exit" is the bearing of the step that follows the roundabout (OSRM's
            // own "exit roundabout" instruction) — the one real destination amid however
            // many exits the circle actually has.
            if isRoundabout {
                let actualExitBearing = steps.indices.contains(stepIndex + 1) ? steps[stepIndex + 1].bearing : step.bearing
                for (exitIndex, intersection) in step.intersections.dropFirst().enumerated() {
                    branchCount += appendRoundaboutExitBranches(at: intersection, actualExitBearing: actualExitBearing, label: "\(stepLabel), exit \(exitIndex + 1)")
                }
            } else {
                // Every other real node this step's own road passes over before its own
                // decision point — not a fork to choose between, just the ambient heartbeat.
                for (nodeIndex, intersection) in step.intersections.dropFirst().enumerated() {
                    branchCount += appendAmbientTick(at: intersection, label: "\(stepLabel), node \(nodeIndex + 1)")
                }
            }
            branchCountByStepIndex[stepIndex] = branchCount
        }

        out("3. BRANCH LOGIC:")
        for (index, step) in steps.enumerated() {
            out("   Step \(index): \(step.name.isEmpty ? "(unnamed)" : step.name)")
            out("     - Type: \(step.maneuverType)")
            out("     - Modifier: \(step.maneuverModifier ?? "none")")
            let location = step.intersections.first?.coordinate ?? step.startCoordinate
            out("     - Location: \(location.latitude), \(location.longitude)")
            out("     - Branches drawn: \(branchCountByStepIndex[index] ?? 0)")
        }

        out("5. SIDE BRANCHES (\"nearby roads\"):")
        out("   - Total branches drawn: \(sideBranches.count) (tier 1 + tier 2 combined)")
        out("   - Data source: the SAME fetched OSRM route used for the main line — every branch comes from that route's own steps[].intersections[].otherBearings (roads meeting at a real point on THIS route), never a separate MapKit or other lookup. There is no independent \"nearby roads\" query anywhere in this file.")
        out("   - Tier 1 (35pt, confusable — a road you could plausibly take by mistake): plain turns need entry == true and ≥\(Int(Self.branchBearingDiffThreshold))° from the road taken, keep the single largest diff; roundabout exits need entry == true and ≤\(Int(Self.roundaboutExitConfusionThreshold))° from the real exit bearing, keep up to 2 closest.")
        out("   - Tier 2 (16pt, 70% of tier 1's opacity, ambient — legal but not confusable, or just a real node the route passes without deciding anything there): renders wherever tier 1 doesn't fire but a legal (entry == true) road still exists. A node with no legal road at all renders nothing.")
        out("6. AMBIENT HEARTBEAT:")
        out("   - Tier-2 \"still tracking\" ticks along plain (non-decision) nodes: \(ambientTickCount)")
        out("   - Minimum spacing enforced: \(Int(tier2MinSpacing))m (\(activity == .driving ? "driving" : "walking")) — throttled by real distance travelled, not by OSRM node count, so a dense run of graph nodes doesn't redraw the same signal repeatedly.")

        // The traveller's real straight-line distance from the nearest point on the route
        // — inside its own corridor tolerance counts as "on the road", further out fades
        // the fabricated property-to-road connector in.
        let nearestRealDistance = CompassManager.distance(from: currentLocation, to: nearest.coordinate)
        let corridorRadius = nearest.corridorRadius
        let offRoadLineOpacity = max(0, min(1, (nearestRealDistance - corridorRadius) / max(corridorRadius, 1)))

        return RouteRenderModel(
            path: path,
            corridorSamples: corridorSamples,
            endMarkerPosition: endMarkerPosition,
            sideBranches: sideBranches,
            offRoadLineOpacity: offRoadLineOpacity,
            tailPoint: tailPoint,
            nearPoint: nearPoint,
            zoomFactor: CGFloat(max(1, baselineLookAhead / lookAhead)),
            targetLookAhead: zoomTarget
        )
    }

    /// The same flag for every activity, tinted to match `color` — ~20pt, and
    /// only ever appears once the destination itself is inside the rendered window. The
    /// flag is shifted so its pole base (bottom-left of the glyph, not its bounding-box
    /// centre) is what actually lands on the route's endpoint.
    @ViewBuilder
    private func endMarker(color: Color) -> some View {
        Image(systemName: "flag.fill")
            .font(.system(size: 16, weight: .bold))
            .foregroundStyle(color)
            .frame(width: 20, height: 20)
            .offset(x: 8, y: -14)
        .shadow(color: color.opacity(0.6), radius: 8)
    }
}

/// A simple sine-ish wiggle used for the loading state's "still figuring it out" squiggle.
private struct SquigglePath: Shape {
    let amplitude: CGFloat
    let wavelength: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let midX = rect.midX
        path.move(to: CGPoint(x: midX, y: rect.minY))
        var y = rect.minY
        var goingRight = true
        while y < rect.maxY {
            let nextY = min(y + wavelength / 2, rect.maxY)
            let controlX = midX + (goingRight ? amplitude : -amplitude)
            path.addQuadCurve(to: CGPoint(x: midX, y: nextY), control: CGPoint(x: controlX, y: (y + nextY) / 2))
            y = nextY
            goingRight.toggle()
        }
        return path
    }
}
