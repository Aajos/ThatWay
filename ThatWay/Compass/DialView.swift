//
//  DialView.swift
//  ThatWay
//
//  The compass dial: cardinal ring, tilt/lean perspective, and swappable needle skins.
//

import SwiftUI
import UIKit

/// Everything the dial draws, as plain values. The dial takes this instead of observing the whole
/// AppModel, and is `Equatable`, so SwiftUI skips it entirely whenever none of these changed —
/// a GPS fix or a card update no longer re-evaluates the dial's big view tree.
struct DialState: Equatable {
    var themeID: ThemeID
    var skin: SkinID
    var guiding: Bool
    var arrived: Bool
    var isIdle: Bool
    var hasRealRoute: Bool
    var showsArrivalClockBelow: Bool
    var heading: Double
    var needle: Double
    var tilt: Double
    var lane: Double
    var sway: Double
    var arrow: String
    var distance: String

    /// `heading` and `needle` are *continuous* angles (see `ContinuousAngle`), so animating between two
    /// readings never spins the long way round at the ±180° wrap point.
    @MainActor
    init(app: AppModel, heading continuousHeading: Double, needle continuousNeedle: Double) {
        themeID = app.theme
        skin = app.skin
        guiding = app.guiding
        arrived = app.arrived
        isIdle = app.isIdle
        hasRealRoute = app.hasRealRoute
        showsArrivalClockBelow = app.etaManager.arrivalClock != nil
        heading = continuousHeading
        needle = continuousNeedle
        tilt = app.tiltDeg
        lane = app.laneDeg
        sway = app.swayAmplitude
        arrow = app.dialArrowSymbol
        distance = app.fmt(app.activeDist)
    }
}

/// Hosts the dial and lets *it* — not the whole compass screen — react to heading and position changes:
/// observing the location manager here means a new heading re-evaluates this tiny wrapper (it just
/// builds a `DialState`), and the dial itself only redraws if something it shows actually changed.
struct DialHost: View {
    let app: AppModel
    @ObservedObject var location: LocationManager
    let k: CGFloat

    /// Holds the running continuous angles. A reference type on purpose: updating it while building the
    /// body is safe (nothing observes it) and idempotent for an unchanged reading.
    private final class Angles { var heading = ContinuousAngle(); var needle = ContinuousAngle() }
    @State private var angles = Angles()

    var body: some View {
        let _ = angles.heading.update(to: app.dialHeadingDeg)
        let _ = angles.needle.update(to: app.needleDeg)
        DialView(state: DialState(app: app, heading: angles.heading.value, needle: angles.needle.value), k: k).equatable()
    }
}

struct DialView: View, Equatable {
    let state: DialState
    let k: CGFloat

    static func == (a: DialView, b: DialView) -> Bool { a.state == b.state && a.k == b.k }

    @State private var needleImage: UIImage?

    private struct NeedleImageKey: Hashable { let themeID: ThemeID; let skin: SkinID; let k: CGFloat }

    @ViewBuilder
    private func needleStack(theme: AppTheme) -> some View {
        ZStack {
            Circle()
                .fill(RadialGradient(colors: [theme.glow.opacity(0.85), theme.glow.opacity(0.5), .clear], center: .center, startRadius: 0, endRadius: 68 * k))
                .frame(width: 136 * k, height: 136 * k)
                .opacity(theme.light ? 0 : 1)
            switch state.skin {
            case .needle: NeedleSkin(theme: theme, k: k)
            case .wheel: WheelSkin(theme: theme, k: k)
            case .clock: ClockSkin(theme: theme, k: k)
            default: NeedleSkin(theme: theme, k: k)
            }
        }
        .frame(width: 286 * k, height: 286 * k)
    }

    @MainActor
    private func renderNeedle(theme: AppTheme) {
        let renderer = ImageRenderer(content: needleStack(theme: theme))
        renderer.scale = UIScreen.main.scale
        renderer.isOpaque = false
        needleImage = renderer.uiImage
    }

    private func leanOffset(k: CGFloat) -> CGFloat {
        let lean = state.lane
        guard lean != 0 else { return 0 }
        let radius = 143 * k
        let edge = radius * CGFloat(AppModel.leanEdgeFactor(atDegrees: lean))
        let pulledIn = radius * CGFloat(cos(abs(lean) * .pi / 180))
        return (lean < 0 ? -1 : 1) * (edge - pulledIn)
    }

    var body: some View {
        let _ = Perf.hit("body.dial")
        let _ = Perf.stamp("dialUpdate")
        let theme = AppTheme.byId(state.themeID)
        let glassColors = [theme.accent, Color(hex: "34D6A5"), theme.accent.hueShifted(24)]

        ZStack {
            // aura glow — held still (a breathing version cost too much CPU), tinted by the dominant
            // dial-glass colours (dark themes only). Left outside the hard circular clip below so its soft radial falloff can
            // bleed a little past the disc's edge.
            Circle()
                .fill(RadialGradient(colors: [glassColors[0].opacity(0.24), .clear], center: .center, startRadius: 0, endRadius: 160 * k))
                .frame(width: 318 * k, height: 318 * k)
                .opacity(theme.light ? 0 : 1)

            // Everything that makes up the dial's actual face is clipped to one exact circle
            // BEFORE the 3D tilt/lean below is applied, so under perspective it always warps
            // as a single clean ellipse — never a mismatched patchwork of differently-sized
            // circles or straight edges poking out past the rim.
            ZStack {
              // The static face (body, rim, bezel, sheen) is flattened into one cached bitmap, so
              // the needle's sway animates only the needle instead of re-rendering the whole dial.
              ZStack {
                // dial body — theme-coloured (coral, in Ember) tint.
                Circle()
                    .fill(RadialGradient(colors: [theme.dialA, theme.dialB], center: .init(x: 0.5, y: 0.28), startRadius: 0, endRadius: 150 * k))

                // glassmorphic rim — a frosted gradient ring pulling 2-3 dominant tones from
                // the current accent.
                Circle()
                    .strokeBorder(
                        AngularGradient(colors: glassColors.map { $0.opacity(0.18) } + [glassColors[0].opacity(0.18)], center: .center),
                        lineWidth: 10 * k
                    )
                    .background(Circle().fill(.ultraThinMaterial).opacity(Perf.on("dialfx") ? 0.15 : 0))
                    .blendMode(.plusLighter)

                // The tick ring and cardinal letters rotate together as one real compass
                // bezel — "N" always ends up at true geographic north on screen as the
                // phone turns, exactly like a physical compass's rotating dial. The needle
                // (below) rotates independently to point at the destination.
                ZStack {
                    TickRing(color: theme.ink)
                        .padding(14 * k)

                    // cardinal letters — idle mode emphasizes all four so the dial visibly reads
                    // as "resting, north-up" rather than mid-navigation.
                    VStack {
                        Text("N").font(.nunito(state.isIdle ? 17 : 13, .black)).tracking(2).foregroundStyle(theme.accent)
                            .glow(theme.accent.opacity(state.isIdle ? 0.55 : 0), radius: 8, theme: theme)
                        Spacer()
                        Text("S").font(.nunito(state.isIdle ? 15 : 12, state.isIdle ? .black : .bold))
                            .foregroundStyle(state.isIdle ? theme.accent : theme.textSecondary)
                            .glow(theme.accent.opacity(state.isIdle ? 0.4 : 0), radius: 6, theme: theme)
                    }
                    .padding(.vertical, 30 * k)
                    HStack {
                        Text("W").font(.nunito(state.isIdle ? 15 : 12, state.isIdle ? .black : .bold))
                            .foregroundStyle(state.isIdle ? theme.accent : theme.textSecondary)
                            .glow(theme.accent.opacity(state.isIdle ? 0.4 : 0), radius: 6, theme: theme)
                        Spacer()
                        Text("E").font(.nunito(state.isIdle ? 15 : 12, state.isIdle ? .black : .bold))
                            .foregroundStyle(state.isIdle ? theme.accent : theme.textSecondary)
                            .glow(theme.accent.opacity(state.isIdle ? 0.4 : 0), radius: 6, theme: theme)
                    }
                    .padding(.horizontal, 30 * k)
                }
                .rotationEffect(.degrees(state.heading))
                .animation(Perf.anim(.easeOut(duration: 0.2)), value: state.heading)
                .animation(.spring(response: 0.5, dampingFraction: 0.7), value: state.isIdle)

                // glass sheen — under the needle, so it never washes the needle's colour out
                Circle()
                    .fill(LinearGradient(colors: [.white.opacity(0.18), .white.opacity(0.05), .clear], startPoint: .top, endPoint: .bottom))
                    .allowsHitTesting(false)

              }
              .drawingGroup()

                // needle, with its gentle "alive" sway. The needle is rendered once to an image and the
                // sway is a native Core Animation rotation on that image: it runs in the render server
                // at full smoothness and costs the app no CPU. (Measured on the SwiftUI alternatives:
                // an every-frame animation cost 6-8 CPU points, a 5 Hz stepped one still ~1 point.)
                Group {
                    if let image = needleImage {
                        SwayingImage(image: image, amplitude: state.sway)
                    } else {
                        needleStack(theme: theme)
                    }
                }
                .frame(width: 286 * k, height: 286 * k)
                .rotationEffect(.degrees(state.needle))
                .task(id: NeedleImageKey(themeID: state.themeID, skin: state.skin, k: k)) { renderNeedle(theme: theme) }
            }
            .frame(width: 286 * k, height: 286 * k)
            .clipShape(Circle())
            .overlay(Circle().stroke(theme.borderColor, lineWidth: theme.light ? 1.5 : 1))
            .lift(theme: theme, radius: 30, y: 20)
        }
        .frame(width: 286 * k, height: 286 * k)
        // Pivots on the dial's top edge (not its centre), so the top stays fixed on screen and the
        // bottom swings out toward the viewer as it tilts.
        .rotation3DEffect(.degrees(Perf.on("dialfx") ? state.tilt : 0), axis: (x: 1, y: 0, z: 0), anchor: .top, perspective: 0.18)
        .rotation3DEffect(.degrees(Perf.on("dialfx") ? state.lane : 0), axis: (x: 0, y: 1, z: 0), perspective: 0.5)
        // Slides so the leaning side's edge lands on the matching side guide line (Slight or Hard):
        // edge = radius × (1 + 0.16 × lean/40), and the rotation already pulls it in by cos(lean).
        .offset(x: leanOffset(k: k))
        .overlay(alignment: .top) {
            VStack(spacing: 7) {
                if state.isIdle {
                    Text("IDLE")
                        .font(.nunito(28, .black))
                        .foregroundStyle(theme.ink)
                    Text("FACING NORTH")
                        .font(.nunito(10, .bold))
                        .tracking(1.6)
                        .foregroundStyle(theme.textSecondary)
                } else {
                    if state.guiding, !state.arrived, state.hasRealRoute, state.showsArrivalClockBelow {
                        // While guiding the arrival time lives under the compass; on the dial itself
                        // there's just the adaptive direction arrow, centred and large.
                        Image(systemName: state.arrow)
                            .font(.system(size: 52, weight: .black))
                            .foregroundStyle(theme.ink)
                            .contentTransition(.symbolEffect(.replace))
                            .animation(.easeInOut(duration: 0.25), value: state.arrow)
                    } else {
                        HStack(spacing: 8) {
                            Text(state.distance)
                                .font(.nunito(34, .black))
                                .foregroundStyle(theme.ink)
                            Image(systemName: state.arrow)
                                .font(.system(size: 26, weight: .black))
                                .foregroundStyle(theme.ink)
                                .contentTransition(.symbolEffect(.replace))
                                .animation(.easeInOut(duration: 0.25), value: state.arrow)
                        }
                    }
                }
            }
            .offset(x: leanOffset(k: k), y: (state.skin == .wheel ? 54 : 172) * k * cos(state.tilt * .pi / 180))
            .allowsHitTesting(false)
        }
        .animation(Perf.anim(.spring(response: 0.5, dampingFraction: 0.7)), value: state.tilt)
        .animation(Perf.anim(.spring(response: 0.5, dampingFraction: 0.7)), value: state.lane)
        .animation(Perf.anim(.spring(response: 0.5, dampingFraction: 0.7)), value: state.needle)
        .animation(.easeOut(duration: 0.45), value: state.themeID)
    }
}

private struct TickRing: View {
    let color: Color
    var body: some View {
        Canvas { ctx, size in
            let r = min(size.width, size.height) / 2
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            for i in 0..<120 {
                let major = i % 10 == 0
                let angle = Double(i) / 120 * 2 * .pi - .pi / 2
                let len: CGFloat = major ? 14 : 6
                let p1 = CGPoint(x: center.x + cos(angle) * r, y: center.y + sin(angle) * r)
                let p2 = CGPoint(x: center.x + cos(angle) * (r - len), y: center.y + sin(angle) * (r - len))
                var path = Path()
                path.move(to: p1); path.addLine(to: p2)
                ctx.stroke(path, with: .color(color.opacity(major ? 0.78 : 0.32)), lineWidth: major ? 1.6 : 1)
            }
        }
    }
}

private struct NeedleSkin: View {
    let theme: AppTheme
    let k: CGFloat
    var body: some View {
        VStack(spacing: 0) {
            Triangle(pointingUp: true)
                .fill(theme.needleRed)
                .frame(width: 26 * k, height: 111 * k)
                .lift(theme: theme, radius: 8, darkOpacity: 0.5)
            Triangle(pointingUp: false)
                .fill(theme.needleGray)
                .frame(width: 26 * k, height: 111 * k)
                .lift(theme: theme, radius: 8, darkOpacity: 0.5)
        }
        .overlay(
            ZStack {
                Circle().fill(theme.ink.opacity(0.95)).frame(width: 20 * k, height: 20 * k)
                Circle().fill(theme.screen).frame(width: 7 * k, height: 7 * k)
            }
        )
    }
}

private struct Triangle: Shape {
    let pointingUp: Bool
    func path(in rect: CGRect) -> Path {
        var p = Path()
        if pointingUp {
            p.move(to: CGPoint(x: rect.midX, y: rect.minY))
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        } else {
            p.move(to: CGPoint(x: rect.midX, y: rect.maxY))
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
            p.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        }
        p.closeSubpath()
        return p
    }
}

private struct WheelSkin: View {
    let theme: AppTheme
    let k: CGFloat
    var body: some View {
        ZStack {
            Circle()
                .strokeBorder(Color(hex: "6E6358"), lineWidth: 18 * k)
                .frame(width: 226 * k, height: 226 * k)
                .lift(theme: theme, radius: 12, y: 6, darkOpacity: 0.6)
            Circle().strokeBorder(.black.opacity(0.4), lineWidth: 5 * k).frame(width: 198 * k, height: 198 * k)
            RoundedRectangle(cornerRadius: 8 * k)
                .fill(LinearGradient(colors: [Color(hex: "8A7E71"), Color(hex: "4A4238")], startPoint: .leading, endPoint: .trailing))
                .frame(width: 186 * k, height: 16 * k)
                .rotationEffect(.degrees(-9))
            RoundedRectangle(cornerRadius: 8 * k)
                .fill(LinearGradient(colors: [Color(hex: "4A4238"), Color(hex: "8A7E71")], startPoint: .top, endPoint: .bottom))
                .frame(width: 16 * k, height: 100 * k)
            Circle()
                .fill(RadialGradient(colors: [Color(hex: "3A342E"), Color(hex: "181513")], center: .init(x: 0.5, y: 0.32), startRadius: 0, endRadius: 40 * k))
                .frame(width: 74 * k, height: 74 * k)
                .overlay(Circle().stroke(theme.borderColor, lineWidth: 1))
            Circle().fill(theme.accent).frame(width: 26 * k, height: 26 * k).glow(theme.accent, radius: 10, theme: theme)
            RoundedRectangle(cornerRadius: 2 * k)
                .fill(theme.accent)
                .frame(width: 4 * k, height: 22 * k)
                .glow(theme.accent, radius: 8, theme: theme)
                .offset(y: -113 * k)
        }
    }
}

private struct ClockSkin: View {
    let theme: AppTheme
    let k: CGFloat
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 3 * k)
                .fill(theme.accent)
                .frame(width: 6 * k, height: 83 * k)
                .glow(theme.accent, radius: 8, theme: theme)
                .offset(y: -41 * k)
            RoundedRectangle(cornerRadius: 4 * k)
                .fill(theme.ink.opacity(0.92))
                .frame(width: 8 * k, height: 47 * k)
                .rotationEffect(.degrees(128), anchor: .bottom)
                .offset(y: -23 * k)
            Circle()
                .fill(theme.accent)
                .frame(width: 18 * k, height: 18 * k)
                .overlay(Circle().stroke(theme.screen, lineWidth: 3))
        }
    }
}


/// A static image with a native, forever-repeating gentle rotation. The animation lives in Core
/// Animation, so SwiftUI never has to re-evaluate anything per frame. It is only (re)started when
/// the amplitude changes, never on an ordinary redraw, so the sway doesn't hiccup as the needle turns.
struct SwayingImage: UIViewRepresentable {
    let image: UIImage
    let amplitude: Double

    final class Coordinator { var amplitude: Double = -1 }
    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> UIImageView {
        let view = UIImageView(image: image)
        view.contentMode = .scaleAspectFit
        view.backgroundColor = .clear
        return view
    }

    func updateUIView(_ view: UIImageView, context: Context) {
        if view.image !== image { view.image = image }
        guard context.coordinator.amplitude != amplitude else { return }
        context.coordinator.amplitude = amplitude
        view.layer.removeAnimation(forKey: "sway")
        guard amplitude != 0 else { return }
        let sway = CABasicAnimation(keyPath: "transform.rotation.z")
        sway.fromValue = -amplitude * .pi / 180
        sway.toValue = amplitude * .pi / 180
        sway.duration = 2.8
        sway.autoreverses = true
        sway.repeatCount = .infinity
        sway.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        view.layer.add(sway, forKey: "sway")
    }
}
