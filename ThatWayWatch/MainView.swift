//
//  MainView.swift
//  ThatWayWatch
//
//  The watch face of the spike, dressed in the iPhone app's look (ThatWayUI): theme palettes, Nunito, the dial
//  face with its glass rim and tick ring, and the real needle skins. Point/Guide toggle on top, the compass,
//  guidance arrow + distance to the next waypoint bottom left, speed bottom right.
//  Gestures: swipe left = next theme · swipe right = voice destination search · swipe up/down = next/previous travel
//  mode (walk, run, cycle: never drive) · long-press the compass = next needle skin · ⋯ = test tools.
//

import SwiftUI
import ThatWayCore
import ThatWayUI

struct MainView: View {
    @EnvironmentObject var model: WatchModel
    @State private var showSearch = false
    @State private var showTools = false

    var body: some View {
        let theme = model.theme
        // The screen is laid out on the whole display (the app root ignores the safe area): the system keeps 40 pt free
        // at the top and 19 pt at the bottom of a 40 mm SE 3, which left the compass a 158 x 138 pt band with controls
        // hard against the rounded edge. Instead: start just under the system clock, keep a margin from the rounded
        // corners, and put the readouts in a strip above the dial rather than over its rim.
        GeometryReader { g in
            let w = g.size.width, h = g.size.height
            let side = max(9, w * 0.06)
            let top = 22 + max(0, w - 162) * 0.06
            let bottom = max(8, w * 0.05)
            ZStack {
                VStack(spacing: 4) {
                    HStack(spacing: 4) {
                        modeButton("Point", .point, theme)
                        modeButton("Guide", .guidance, theme)
                        Image(systemName: model.mode.symbolName)
                            .font(.system(size: 13, weight: .black))
                            .foregroundStyle(theme.modeTint(model.mode))
                            .frame(width: 26, height: 22)
                            .background(Capsule().fill(theme.surface(0.12)))
                            .overlay(Capsule().stroke(theme.borderColor))
                        Button { showTools = true } label: {
                            Image(systemName: "ellipsis").font(.system(size: 12, weight: .black)).foregroundStyle(theme.ink.opacity(0.7))
                                .frame(width: 26, height: 22)
                                .background(Capsule().fill(theme.surface(0.12)))
                                .overlay(Capsule().stroke(theme.borderColor))
                        }
                        .buttonStyle(.plain)
                    }
                    .frame(height: 24)

                    infoStrip(theme)

                    GeometryReader { geo in
                        let d = max(40, min(geo.size.width, geo.size.height))
                        dial(theme: theme, d: d)
                            .frame(width: d, height: d)
                            .position(x: geo.size.width / 2, y: geo.size.height / 2)
                            .onLongPressGesture { model.cycleSkin() }
                    }
                }
                .padding(.top, top).padding(.horizontal, side).padding(.bottom, bottom)

                if let flash = model.modeFlash {
                    VStack(spacing: 2) {
                        Image(systemName: flash.symbolName).font(.system(size: 26, weight: .black)).foregroundStyle(theme.modeTint(flash))
                        Text(flash.displayName).font(.nunito(18, .black)).foregroundStyle(theme.ink)
                    }
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    .background(RoundedRectangle(cornerRadius: 18).fill(theme.screen.opacity(0.92)))
                    .overlay(RoundedRectangle(cornerRadius: 18).stroke(theme.outline(0.5)))
                    .transition(.scale.combined(with: .opacity))
                    .allowsHitTesting(false)
                }
            }
            .frame(width: w, height: h)
            .animation(.spring(response: 0.3, dampingFraction: 0.75), value: model.modeFlash)
            .animation(.easeOut(duration: 0.2), value: model.proximity)
        }
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 22).onEnded { v in
                let dx = v.translation.width, dy = v.translation.height
                if abs(dx) > abs(dy) {
                    if dx < 0 { model.cycleTheme() } else { showSearch = true }
                } else {
                    model.changeMode(steps: dy < 0 ? 1 : -1)      // up = next, down = previous
                }
            }
        )
        .sheet(isPresented: $showSearch) { SearchView().environmentObject(model) }
        .sheet(isPresented: $showTools) { ToolsView() }
        .onAppear {
            // Simulator testing aid: `-spike-open search|tools` opens that sheet at launch.
            let args = ProcessInfo.processInfo.arguments
            guard let i = args.firstIndex(of: "-spike-open"), i + 1 < args.count else { return }
            if args[i + 1] == "search" { showSearch = true } else if args[i + 1] == "tools" { showTools = true }
        }
    }

    /// One row above the dial: what is happening (a friend being found, the next turn, or the gesture hint) on the
    /// left and the speed on the right. It used to float over the dial's lower corners and overlap its rim.
    @ViewBuilder
    private func infoStrip(_ theme: AppTheme) -> some View {
        HStack(alignment: .center, spacing: 6) {
            Group {
                if let near = model.proximity {
                    HStack(spacing: 4) {
                        Image(systemName: "person.wave.2.fill").font(.system(size: 11, weight: .black)).foregroundStyle(theme.accent)
                        Text("\(near.friendName) · \(near.meters.map { "\($0) m" } ?? near.band.label)")
                            .font(.nunito(12, .extraBold)).foregroundStyle(theme.ink).lineLimit(1).minimumScaleFactor(0.6)
                    }
                    .padding(.horizontal, 8).frame(height: 22)
                    .background(Capsule().fill(theme.surface(0.12)))
                    .overlay(Capsule().stroke(theme.accent.opacity(0.6)))
                } else {
                    bottomLeft(theme)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(alignment: .lastTextBaseline, spacing: 2) {
                Text("\(Int((model.speed * 3.6).rounded()))").font(.nunito(18, .extraBold)).foregroundStyle(theme.ink.opacity(0.9))
                Text("km/h").font(.nunito(9, .extraBold)).tracking(0.3).foregroundStyle(theme.ink.opacity(0.6))
            }
            .fixedSize()
        }
        .frame(height: 26)
        .allowsHitTesting(false)
    }

    // MARK: Dial

    private func dial(theme: AppTheme, d: CGFloat) -> some View {
        let k = d / 286
        let glass = [theme.accent, Color(hex: "34D6A5"), theme.accent.opacity(0.8)]
        return ZStack {
            Circle().fill(RadialGradient(colors: [theme.dialA, theme.dialB], center: .init(x: 0.5, y: 0.28), startRadius: 0, endRadius: d * 0.52))
            Circle().strokeBorder(AngularGradient(colors: glass.map { $0.opacity(0.28) } + [glass[0].opacity(0.28)], center: .center), lineWidth: d * 0.04)
            // Tick ring and cardinal letters turn together: "N" stays at true north as the wrist turns.
            ZStack {
                TickRing(color: theme.ink, k: max(0.3, k * 1.6)).padding(d * 0.045)
                cardinal("N", theme.accent, d, offset: -0.30)
                cardinal("E", theme.textSecondary, d, offset: 0.30, horizontal: true)
                cardinal("S", theme.textSecondary, d, offset: 0.30)
                cardinal("W", theme.textSecondary, d, offset: -0.30, horizontal: true)
            }
            .rotationEffect(.degrees(model.ringAngle.value))
            Circle().fill(LinearGradient(colors: [.white.opacity(0.16), .white.opacity(0.04), .clear], startPoint: .top, endPoint: .bottom))
                .allowsHitTesting(false)
            skin(theme: theme, k: k)
                .frame(width: 286 * k, height: 286 * k)
                .rotationEffect(.degrees(model.needleAngle.value))
            if model.navMode == .point, model.hasDestination, let metres = model.straightLineDistance {
                Text(CompassManager.formattedDistance(metres)).font(.nunito(16, .black)).foregroundStyle(theme.ink).offset(y: d * 0.22)
            }
        }
        .clipShape(Circle())
        .overlay(Circle().stroke(theme.borderColor, lineWidth: theme.light ? 1.5 : 1))
        .shadow(color: theme.light ? .clear : .black.opacity(0.45), radius: 8, y: 4)
        .animation(.linear(duration: 0.15), value: model.needleAngle.value)
        .animation(.linear(duration: 0.15), value: model.ringAngle.value)
    }

    @ViewBuilder
    private func skin(theme: AppTheme, k: CGFloat) -> some View {
        switch model.skin {
        case .needle: NeedleSkin(theme: theme, k: k)
        case .wheel: WheelSkin(theme: theme, k: k)
        case .clock: ClockSkin(theme: theme, k: k)
        }
    }

    private func cardinal(_ letter: String, _ color: Color, _ d: CGFloat, offset: CGFloat, horizontal: Bool = false) -> some View {
        Text(letter).font(.nunito(d * 0.085, .black)).foregroundStyle(color)
            .offset(x: horizontal ? d * offset : 0, y: horizontal ? 0 : d * offset)
    }

    // MARK: Pills

    private func modeButton(_ title: String, _ mode: WatchModel.NavMode, _ theme: AppTheme) -> some View {
        let on = model.navMode == mode
        return Button { model.navMode = mode } label: {
            Text(title).font(.nunito(13, .extraBold))
                .frame(maxWidth: .infinity, minHeight: 22)
                .background(Capsule().fill(on ? theme.accent : theme.surface(0.12)))
                .overlay(Capsule().stroke(on ? theme.accent : theme.borderColor))
                .foregroundStyle(on ? theme.onAccent : theme.ink.opacity(0.8))
                .glow(on ? theme.accent.opacity(0.5) : .clear, radius: 5, theme: theme)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func bottomLeft(_ theme: AppTheme) -> some View {
        if model.navMode == .guidance, let p = model.progress {
            HStack(spacing: 4) {
                Image(systemName: arrow(p.nextTurn?.dir)).font(.system(size: 15, weight: .black)).foregroundStyle(theme.accent)
                    .glow(theme.accent.opacity(0.5), radius: 5, theme: theme)
                Text(CompassManager.formattedDistance(p.distanceToNext)).font(.nunito(15, .black)).minimumScaleFactor(0.6)
                    .foregroundStyle(p.offRoute ? Color.red : theme.ink)
            }
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(RoundedRectangle(cornerRadius: 12).fill(theme.surface(0.08)))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(theme.outline(0.4)))
        } else {
            Text(model.message.isEmpty ? "← theme · → search\n↕ mode" : model.message)
                .font(.nunito(9, .semibold)).foregroundStyle(theme.textSecondary).lineLimit(2).minimumScaleFactor(0.8)
        }
    }

    private func arrow(_ dir: TurnDir?) -> String {
        switch dir {
        case .left: return "arrow.turn.up.left"
        case .right: return "arrow.turn.up.right"
        default: return "arrow.up"
        }
    }
}
