//
//  DialSkins.swift
//  ThatWayUI
//
//  The compass dial's reusable art: the tick ring and the three needle skins (needle, wheel, clock).
//  `k` is the dial scale (1 = the iPhone's 286 pt reference dial).
//

import SwiftUI

public struct TickRing: View {
    public let color: Color
    /// Scales tick length and stroke width (1 = the iPhone dial; the watch passes its much smaller dial's scale).
    public let k: CGFloat
    public init(color: Color, k: CGFloat = 1) { self.color = color; self.k = k }
    public var body: some View {
        Canvas { ctx, size in
            let r = min(size.width, size.height) / 2
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            for i in 0..<120 {
                let major = i % 10 == 0
                let angle = Double(i) / 120 * 2 * .pi - .pi / 2
                let len: CGFloat = (major ? 14 : 6) * k
                let p1 = CGPoint(x: center.x + cos(angle) * r, y: center.y + sin(angle) * r)
                let p2 = CGPoint(x: center.x + cos(angle) * (r - len), y: center.y + sin(angle) * (r - len))
                var path = Path()
                path.move(to: p1); path.addLine(to: p2)
                ctx.stroke(path, with: .color(color.opacity(major ? 0.78 : 0.32)), lineWidth: (major ? 1.6 : 1) * max(k, 0.55))
            }
        }
    }
}

public struct NeedleSkin: View {
    public let theme: AppTheme
    public let k: CGFloat
    public init(theme: AppTheme, k: CGFloat) { self.theme = theme; self.k = k }
    public var body: some View {
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

public struct Triangle: Shape {
    public let pointingUp: Bool
    public init(pointingUp: Bool) { self.pointingUp = pointingUp }
    public func path(in rect: CGRect) -> Path {
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

public struct WheelSkin: View {
    public let theme: AppTheme
    public let k: CGFloat
    public init(theme: AppTheme, k: CGFloat) { self.theme = theme; self.k = k }
    public var body: some View {
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

public struct ClockSkin: View {
    public let theme: AppTheme
    public let k: CGFloat
    public init(theme: AppTheme, k: CGFloat) { self.theme = theme; self.k = k }
    public var body: some View {
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
