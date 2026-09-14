//
//  DirectionsView.swift
//  ThatWay
//
//  The road-ahead line shown in guidance mode: side streets slide toward you,
//  the whole thread swings upright as you take the turn. Ported from the
//  design's buildThread()/tick() SVG path builder.
//

import SwiftUI

struct DirectionsView: View {
    @EnvironmentObject var app: AppModel
    let k: CGFloat

    var body: some View {
        ZStack(alignment: .topLeading) {
            Canvas { ctx, size in
                let scale = size.width / 402
                var g = ctx
                // Rotate the thread around its local anchor (201,268) — "you are here" —
                // then scale the whole 402x268 local space up to the view's real size.
                g.scaleBy(x: scale, y: scale)
                g.translateBy(x: 201, y: 268)
                g.rotate(by: .degrees(app.threadRot))
                g.translateBy(x: -201, y: -268)

                let thread = Self.buildThread(dir: app.step.dir, far: app.far)

                for stub in thread.stubs {
                    g.stroke(stub, with: .color(app.currentTheme.ink.opacity(0.2)), style: StrokeStyle(lineWidth: 3, lineCap: .round))
                }
                g.stroke(thread.route, with: .color(app.routeColor.opacity(0.22)), style: StrokeStyle(lineWidth: 21, lineCap: .round))
                g.stroke(thread.route, with: .color(app.routeColor), style: StrokeStyle(lineWidth: 7, lineCap: .round))
                g.stroke(thread.route, with: .color(.white.opacity(0.8)), style: StrokeStyle(lineWidth: 2.2, lineCap: .round, dash: [8, 14]))
            }
            .mask(LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.26), .init(color: .black, location: 1)], startPoint: .top, endPoint: .bottom))

            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 2).fill(app.routeColor).frame(width: 16, height: 3)
                Text("NEXT \(app.fmt(app.routeM))")
                    .font(.system(size: 10, weight: .bold))
                    .tracking(1.4)
                    .foregroundStyle(app.routeColor)
            }
            .padding(.leading, 16 * k)
            .padding(.top, 6 * k)
        }
    }

    private struct Thread {
        let route: Path
        let stubs: [Path]
    }

    private static func tick(_ x: Double, _ y: Double, _ nx: Double, _ ny: Double, _ len: Double) -> Path {
        let h = len / 2
        var p = Path()
        p.move(to: CGPoint(x: x - nx * h, y: y - ny * h))
        p.addLine(to: CGPoint(x: x + nx * h, y: y + ny * h))
        return p
    }

    private static func buildThread(dir: TurnDir, far: Double) -> Thread {
        let bx = 201.0, by0 = 268.0
        let by = by0 - 250 * far
        let s: Double = dir == .left ? -1 : dir == .right ? 1 : 0
        let leg = 58.0 * .pi / 180
        let ux = s * sin(leg), uy = -cos(leg)
        let r = s != 0 ? 34.0 : 0

        var route = Path()
        route.move(to: CGPoint(x: bx, y: by0 + 80))
        if s != 0 {
            route.addLine(to: CGPoint(x: bx, y: by + r))
            route.addQuadCurve(to: CGPoint(x: bx + ux * r, y: by + uy * r), control: CGPoint(x: bx, y: by))
            route.addLine(to: CGPoint(x: bx + ux * 620, y: by + uy * 620))
        } else {
            route.addLine(to: CGPoint(x: bx, y: by - 560))
        }

        var stubs: [Path] = []
        for i in 0..<8 {
            let y = by + 36 + Double(i) * 41
            if y < by0 - 8, y > -16 {
                stubs.append(tick(bx, y, 1, 0, 40 + Double(i % 3) * 9))
            }
        }
        for j in 0..<7 {
            let d = r + 36 + Double(j) * 44
            let px = bx + ux * d, py = by + uy * d
            if py > -16, py < by0 - 8, px > 6, px < 396 {
                stubs.append(tick(px, py, -uy, ux, 38 + Double(j % 3) * 9))
            }
        }
        return Thread(route: route, stubs: stubs)
    }
}
