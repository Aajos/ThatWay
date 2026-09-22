//
//  DialView.swift
//  ThatWay
//
//  The compass dial: cardinal ring, tilt/lean perspective, and swappable needle skins.
//

import SwiftUI

struct DialView: View {
    @EnvironmentObject var app: AppModel
    let k: CGFloat
    @State private var breathing = false

    private func leanOffset(k: CGFloat) -> CGFloat {
        let lean = app.laneDeg
        guard lean != 0 else { return 0 }
        let radius = 143 * k
        let edge = radius * CGFloat(AppModel.leanEdgeFactor(atDegrees: lean))
        let pulledIn = radius * CGFloat(cos(abs(lean) * .pi / 180))
        return (lean < 0 ? -1 : 1) * (edge - pulledIn)
    }

    var body: some View {
        let theme = app.currentTheme
        let glassColors = app.dialGlassColors

        ZStack {
            // aura glow — breathes continuously, tinted by the dominant dial-glass colors.
            // Left outside the hard circular clip below so its soft radial falloff can bleed
            // a little past the disc's edge; a RadialGradient has no hard border to go ragged.
            Circle()
                .fill(RadialGradient(colors: [glassColors[0].opacity(breathing ? 0.32 : 0.16), .clear], center: .center, startRadius: 0, endRadius: 160 * k))
                .frame(width: 318 * k, height: 318 * k)
                .onAppear { breathing = true }
                .animation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true), value: breathing)

            // Everything that makes up the dial's actual face is clipped to one exact circle
            // BEFORE the 3D tilt/lean below is applied, so under perspective it always warps
            // as a single clean ellipse — never a mismatched patchwork of differently-sized
            // circles or straight edges poking out past the rim.
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
                    .background(Circle().fill(.ultraThinMaterial).opacity(0.15))
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
                        Text("N").font(.nunito(app.isIdle ? 17 : 13, .black)).tracking(2).foregroundStyle(theme.accent)
                            .shadow(color: theme.accent.opacity(app.isIdle ? 0.55 : 0), radius: 8)
                        Spacer()
                        Text("S").font(.nunito(app.isIdle ? 15 : 12, app.isIdle ? .black : .bold))
                            .foregroundStyle(app.isIdle ? theme.accent : theme.textSecondary)
                            .shadow(color: theme.accent.opacity(app.isIdle ? 0.4 : 0), radius: 6)
                    }
                    .padding(.vertical, 30 * k)
                    HStack {
                        Text("W").font(.nunito(app.isIdle ? 15 : 12, app.isIdle ? .black : .bold))
                            .foregroundStyle(app.isIdle ? theme.accent : theme.textSecondary)
                            .shadow(color: theme.accent.opacity(app.isIdle ? 0.4 : 0), radius: 6)
                        Spacer()
                        Text("E").font(.nunito(app.isIdle ? 15 : 12, app.isIdle ? .black : .bold))
                            .foregroundStyle(app.isIdle ? theme.accent : theme.textSecondary)
                            .shadow(color: theme.accent.opacity(app.isIdle ? 0.4 : 0), radius: 6)
                    }
                    .padding(.horizontal, 30 * k)
                }
                .rotationEffect(.degrees(app.dialHeadingDeg))
                .animation(.easeOut(duration: 0.2), value: app.dialHeadingDeg)
                .animation(.spring(response: 0.5, dampingFraction: 0.7), value: app.isIdle)

                // needle
                ZStack {
                    Circle()
                        .fill(RadialGradient(colors: [theme.glow.opacity(0.85), theme.glow.opacity(0.5), .clear], center: .center, startRadius: 0, endRadius: 68 * k))
                        .frame(width: 136 * k, height: 136 * k)

                    switch app.skin {
                    case .needle: NeedleSkin(theme: theme, k: k)
                    case .wheel: WheelSkin(theme: theme, k: k)
                    case .clock: ClockSkin(theme: theme, k: k)
                    default: NeedleSkin(theme: theme, k: k)
                    }
                }
                .rotationEffect(.degrees(app.needleDeg))

                // glass sheen
                Circle()
                    .fill(LinearGradient(colors: [.white.opacity(0.18), .white.opacity(0.05), .clear], startPoint: .top, endPoint: .bottom))
                    .allowsHitTesting(false)
            }
            .frame(width: 286 * k, height: 286 * k)
            .clipShape(Circle())
            .overlay(Circle().stroke(theme.borderColor, lineWidth: 1))
            .shadow(color: .black.opacity(0.45), radius: 30, y: 20)
        }
        .frame(width: 286 * k, height: 286 * k)
        // Pivots on the dial's top edge (not its centre), so the top stays fixed on screen and the
        // bottom swings out toward the viewer as it tilts.
        .rotation3DEffect(.degrees(app.tiltDeg), axis: (x: 1, y: 0, z: 0), anchor: .top, perspective: 0.18)
        .rotation3DEffect(.degrees(app.laneDeg), axis: (x: 0, y: 1, z: 0), perspective: 0.5)
        // Slides so the leaning side's edge lands on the matching side guide line (Slight or Hard):
        // edge = radius × (1 + 0.16 × lean/40), and the rotation already pulls it in by cos(lean).
        .offset(x: leanOffset(k: k))
        .overlay(alignment: .top) {
            VStack(spacing: 7) {
                if app.isIdle {
                    Text("IDLE")
                        .font(.nunito(28, .black))
                        .foregroundStyle(theme.ink)
                    Text("FACING NORTH")
                        .font(.nunito(10, .bold))
                        .tracking(1.6)
                        .foregroundStyle(theme.textSecondary)
                } else {
                    if app.guiding, app.hasRealRoute, app.etaManager.arrivalClock != nil {
                        // While guiding the arrival time lives under the compass; on the dial itself
                        // there's just the adaptive direction arrow, centred and large.
                        Image(systemName: app.dialArrowSymbol)
                            .font(.system(size: 52, weight: .black))
                            .foregroundStyle(theme.ink)
                            .contentTransition(.symbolEffect(.replace))
                            .animation(.easeInOut(duration: 0.25), value: app.dialArrowSymbol)
                    } else {
                        HStack(spacing: 8) {
                            Text(app.fmt(app.activeDist))
                                .font(.nunito(34, .black))
                                .foregroundStyle(theme.ink)
                            Image(systemName: app.dialArrowSymbol)
                                .font(.system(size: 26, weight: .black))
                                .foregroundStyle(theme.ink)
                                .contentTransition(.symbolEffect(.replace))
                                .animation(.easeInOut(duration: 0.25), value: app.dialArrowSymbol)
                        }
                    }
                }
            }
            .offset(y: (app.skin == .wheel ? 54 : 172) * k * cos(app.tiltDeg * .pi / 180))
            .allowsHitTesting(false)
        }
        .animation(.spring(response: 0.5, dampingFraction: 0.7), value: app.tiltDeg)
        .animation(.spring(response: 0.5, dampingFraction: 0.7), value: app.laneDeg)
        .animation(.spring(response: 0.5, dampingFraction: 0.7), value: app.needleDeg)
        .animation(.easeOut(duration: 0.45), value: app.accent)
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
                .shadow(color: .black.opacity(0.5), radius: 8)
            Triangle(pointingUp: false)
                .fill(theme.needleGray)
                .frame(width: 26 * k, height: 111 * k)
                .shadow(color: .black.opacity(0.5), radius: 8)
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
                .shadow(color: .black.opacity(0.6), radius: 12, y: 6)
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
            Circle().fill(theme.accent).frame(width: 26 * k, height: 26 * k).shadow(color: theme.accent, radius: 10)
            RoundedRectangle(cornerRadius: 2 * k)
                .fill(theme.accent)
                .frame(width: 4 * k, height: 22 * k)
                .shadow(color: theme.accent, radius: 8)
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
                .shadow(color: theme.accent, radius: 8)
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
