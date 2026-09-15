//
//  MapScreen.swift
//  ThatWay
//
//  A deliberately label-free, routing-free map: drag to pan, pinch to zoom,
//  rotate with two fingers, and a tilt toggle for a pseudo-3D look. The live map
//  bleeds full-bleed behind the whole screen (blurred and faded toward the physical
//  edges) so the interactive box in front never visibly "stops" at its own border.
//

import SwiftUI

struct MapScreen: View {
    @EnvironmentObject var app: AppModel
    @GestureState private var panOffset: CGSize = .zero
    @GestureState private var pinchDelta: CGFloat = 1
    @GestureState private var rotateDelta: Angle = .zero
    @State private var pulsing = false

    var body: some View {
        let theme = app.currentTheme

        ZStack {
            // Full-bleed underlay — the same live map, filling the entire screen edge to
            // edge (including behind the header and the floating tab bar), blurred and
            // faded toward the screen's extreme edges. Its transforms are driven by the
            // exact same state as the boxed map below, so the two stay perfectly in sync
            // as you pan, zoom, rotate, or tilt.
            GeometryReader { geo in
                mapContent(theme: theme)
                    .position(x: geo.size.width / 2, y: geo.size.height / 2)
                    .frame(width: geo.size.width, height: geo.size.height)
                    .clipped()
            }
            .blur(radius: 12)
            .opacity(0.92)
            .mask(edgeFadeMask)
            .ignoresSafeArea()
            .allowsHitTesting(false)

            VStack(spacing: 0) {
                Text("Map").font(.system(size: 24, weight: .black))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.top, 2)
                    .padding(.bottom, 6)

                GeometryReader { geo in
                    ZStack {
                        RoundedRectangle(cornerRadius: 26).fill(theme.ink.opacity(0.03))

                        mapContent(theme: theme)
                            .position(x: geo.size.width / 2, y: geo.size.height / 2)
                            .clipped()

                        // north indicator
                        VStack(spacing: 3) {
                            Triangle().fill(theme.accent).frame(width: 12, height: 12)
                            Text("N").font(.system(size: 10, weight: .black)).tracking(1.4).foregroundStyle(theme.ink.opacity(0.72))
                        }
                        .rotationEffect(.degrees(app.mapRot))
                        .position(x: 30, y: 26)

                        // controls — always live; the map stays fully interactive whether or not
                        // you're guiding. Centred low enough that the top button clears the box's
                        // own rounded-corner clip instead of getting sheared off.
                        VStack(spacing: 8) {
                            ctrl("+") { app.mapZoom = min(3, app.mapZoom * 1.25) }
                            ctrl("−") { app.mapZoom = max(0.55, app.mapZoom / 1.25) }
                            ctrl("↺") { app.mapRot -= 30 }
                            ctrl("↻") { app.mapRot += 30 }
                            ctrl("◰") { app.mapTilt = app.mapTilt == 0 ? 42 : 0 }
                            ctrl("◎") { app.recenterMap() }
                        }
                        .position(x: geo.size.width - 30, y: 150)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 26))
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture()
                            .updating($panOffset) { value, state, _ in state = value.translation }
                            .onEnded { value in
                                app.mapX += value.translation.width
                                app.mapY += value.translation.height
                            }
                    )
                    .simultaneousGesture(
                        MagnificationGesture()
                            .updating($pinchDelta) { value, state, _ in state = value }
                            .onEnded { value in app.mapZoom = max(0.55, min(3, app.mapZoom * value)) }
                    )
                    .simultaneousGesture(
                        RotationGesture()
                            .updating($rotateDelta) { value, state, _ in state = value }
                            .onEnded { value in app.mapRot += value.degrees }
                    )
                }
                .padding(.top, -10)
                .padding(.horizontal, 16)
                .padding(.bottom, 70)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(.top, 8)
        .background(theme.screen)
        .onAppear { pulsing = true }
        .animation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true), value: pulsing)
    }

    /// The live map field with all of its interactive transforms applied, but not yet
    /// positioned or clipped — shared by both the full-bleed underlay and the sharp boxed
    /// layer so they're always pixel-for-pixel in sync. Spring-animated so every button
    /// tap (zoom, rotate, tilt, recentre) glides smoothly rather than snapping.
    @ViewBuilder
    private func mapContent(theme: AppTheme) -> some View {
        MapField(theme: theme, routeColor: app.guiding ? app.routeColor : nil, pulsing: pulsing)
            .frame(width: 1200, height: 1200)
            .scaleEffect(app.mapZoom * pinchDelta)
            .rotationEffect(app.mapRot == 0 && rotateDelta == .zero ? .zero : .degrees(app.mapRot) + rotateDelta)
            .rotation3DEffect(.degrees(app.mapTilt), axis: (x: 1, y: 0, z: 0), perspective: 0.5)
            .offset(x: app.mapX + panOffset.width, y: app.mapY + panOffset.height)
            .animation(.spring(response: 0.45, dampingFraction: 0.82), value: app.mapZoom)
            .animation(.spring(response: 0.45, dampingFraction: 0.82), value: app.mapRot)
            .animation(.spring(response: 0.45, dampingFraction: 0.82), value: app.mapTilt)
            .animation(.spring(response: 0.45, dampingFraction: 0.82), value: app.mapX)
            .animation(.spring(response: 0.45, dampingFraction: 0.82), value: app.mapY)
    }

    /// Fades the full-bleed underlay out toward the physical screen edges on every side,
    /// so it reads as periphery rather than a hard-edged rectangle of its own.
    private var edgeFadeMask: some View {
        ZStack {
            LinearGradient(
                stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.04),
                        .init(color: .black, location: 0.96), .init(color: .clear, location: 1)],
                startPoint: .top, endPoint: .bottom
            )
            LinearGradient(
                stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.03),
                        .init(color: .black, location: 0.97), .init(color: .clear, location: 1)],
                startPoint: .leading, endPoint: .trailing
            )
            .blendMode(.multiply)
        }
    }

    @ViewBuilder
    private func ctrl(_ glyph: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(glyph)
                .font(.system(size: 15, weight: .heavy))
                .foregroundStyle(app.currentTheme.ink.opacity(0.9))
                .frame(width: 38, height: 38)
                .background(RoundedRectangle(cornerRadius: 13).fill(app.currentTheme.screen))
                .overlay(RoundedRectangle(cornerRadius: 13).stroke(app.currentTheme.ink.opacity(0.14)))
        }
    }
}

private struct MapField: View {
    let theme: AppTheme
    /// Non-nil (and tinted to the current activity) while guiding, standing in for a real
    /// route polyline; nil in Point mode, where the road is just a neutral accent hint.
    let routeColor: Color?
    let pulsing: Bool

    var body: some View {
        ZStack {
            GridLines(color: theme.ink.opacity(0.06))
            // arterial roads
            Rectangle().fill(theme.ink.opacity(0.09)).frame(height: 14).offset(y: 420 - 600)
            Rectangle().fill(theme.ink.opacity(0.07)).frame(height: 9).offset(y: 660 - 600)
            Rectangle().fill(theme.ink.opacity(0.08)).frame(height: 12).offset(y: 868 - 600)
            Rectangle().fill(theme.ink.opacity(0.08)).frame(width: 12).offset(x: 380 - 600)
            Rectangle().fill(theme.ink.opacity(0.065)).frame(width: 9).offset(x: 600 - 600)
            Rectangle().fill(theme.ink.opacity(0.075)).frame(width: 12).offset(x: 820 - 600)

            // route overlay — a plain accent hint in Point mode, the live route colour
            // (and a fuller glow) once guidance is under way.
            Rectangle()
                .fill((routeColor ?? theme.accent).opacity(routeColor != nil ? 0.55 : 0.16))
                .frame(width: 900, height: routeColor != nil ? 14 : 10)
                .shadow(color: (routeColor ?? .clear).opacity(0.6), radius: routeColor != nil ? 10 : 0)
                .rotationEffect(.degrees(34))
                .offset(x: 570 - 600, y: 505 - 600)

            // you-are-here — pulses continuously so it reads clearly on a live map.
            ZStack {
                Circle().fill((routeColor ?? theme.accent).opacity(pulsing ? 0.12 : 0.45))
                    .frame(width: pulsing ? 54 : 36, height: pulsing ? 54 : 36)
                Circle().fill(routeColor ?? theme.accent).frame(width: 18, height: 18)
                    .overlay(Circle().stroke(theme.screen, lineWidth: 3))
                    .shadow(color: routeColor ?? theme.accent, radius: 10)
            }
            .offset(x: 599 - 600, y: 599 - 600)

            ForEach(Friend.all) { f in
                VStack(spacing: 4) {
                    Circle().fill(f.color).frame(width: 34, height: 34)
                        .overlay(Circle().stroke(theme.screen, lineWidth: 2))
                        .overlay(Text(f.initials).font(.system(size: 12, weight: .heavy)).foregroundStyle(Color(hex: "241A14")))
                    Text(f.name).font(.system(size: 10, weight: .semibold)).foregroundStyle(theme.ink.opacity(0.72))
                }
                .offset(x: f.mapPos.x * 1200 - 600, y: f.mapPos.y * 1200 - 600)
            }
        }
    }
}

private struct GridLines: View {
    let color: Color
    var body: some View {
        Canvas { ctx, size in
            let step: CGFloat = 34
            var x: CGFloat = 0
            while x <= size.width {
                var p = Path(); p.move(to: CGPoint(x: x, y: 0)); p.addLine(to: CGPoint(x: x, y: size.height))
                ctx.stroke(p, with: .color(color), lineWidth: 1)
                x += step
            }
            var y: CGFloat = 0
            while y <= size.height {
                var p = Path(); p.move(to: CGPoint(x: 0, y: y)); p.addLine(to: CGPoint(x: size.width, y: y))
                ctx.stroke(p, with: .color(color), lineWidth: 1)
                y += step
            }
        }
    }
}

private struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.midX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        p.closeSubpath()
        return p
    }
}
