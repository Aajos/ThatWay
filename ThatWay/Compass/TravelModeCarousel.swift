//
//  TravelModeCarousel.swift
//  ThatWay
//
//  The Walk / Run / Cycle / Drive selector in the activity pill: square tiles on an arc,
//  the selected one in front and largest. Selection is manual and authoritative — "Still"
//  is only a white tint on the selected tile, never a mode of its own.
//

import SwiftUI
import UIKit
import ThatWayCore
import ThatWayUI

private final class CarouselHaptics {
    let selection = UISelectionFeedbackGenerator()
    let impact = UIImpactFeedbackGenerator(style: .heavy)
    func prepare() { selection.prepare(); impact.prepare() }
}

struct TravelModeCarousel: View {
    @EnvironmentObject var app: AppModel
    let theme: AppTheme
    /// The mode name to show (in place of the speed) for ~1.5s after a change.
    @Binding var flashName: String?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let modes = TravelMode.allCases
    /// Sized to fill the 66pt pill with a few points to spare; the side tiles (0.8×) peek out
    /// from behind it, and the whole arc fits in `arcWidth` so nothing spills past the pill.
    static let frontSize: CGFloat = 60
    private var frontSize: CGFloat { Self.frontSize }
    private let spacing: CGFloat = 28
    private let pixelsPerTile: CGFloat = 34
    static let arcWidth: CGFloat = 2 * (28 + 60 * 0.8 / 2)

    @State private var position: Double = 0
    @State private var dragStart: Double?
    @State private var lastNearest = 0
    @State private var nameTask: Task<Void, Never>?
    @State private var haptics = CarouselHaptics()

    private var committedIndex: Int { modes.firstIndex(of: app.travelMode) ?? 0 }

    var body: some View {
        ZStack {
            ForEach(Array(modes.enumerated()), id: \.offset) { index, mode in
                tile(mode, index: index)
            }
        }
        .frame(width: Self.arcWidth, height: frontSize)
        .contentShape(Rectangle())
        .gesture(dragGesture)
        .onAppear {
            position = Double(committedIndex)
            lastNearest = committedIndex
        }
        .onChange(of: app.travelMode) { _, _ in
            if dragStart == nil { move(to: committedIndex) }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Travel mode")
        .accessibilityValue(app.isStationary ? "\(app.travelMode.displayName), still" : app.travelMode.displayName)
        .accessibilityAdjustableAction { direction in
            let next = committedIndex + (direction == .increment ? 1 : -1)
            guard modes.indices.contains(next) else { return }
            commit(next)
        }
    }

    // MARK: Tiles

    @ViewBuilder
    private func tile(_ mode: TravelMode, index: Int) -> some View {
        let d = Double(index) - position
        let a = min(1, abs(d))
        let scale = 1 - 0.2 * a
        let fade = abs(d) <= 1 ? 1 - 0.5 * abs(d) : max(0, 0.5 * (1 - (abs(d) - 1) / 0.4))
        let x = tileX(index)
        let still = app.isStationary && index == committedIndex
        let tint = theme.modeTint(mode, still: still)
        let border = still ? theme.modeStillBorder : tint
        let size = frontSize * scale

        // The active tile sits on a solid backing (so the tiles behind it don't show through) and
        // carries a much stronger tint than the faded side tiles.
        let isFront = index == committedIndex
        let fill = isFront ? (still ? (theme.light ? 1.0 : 0.38) : 0.34) : 0.14
        RoundedRectangle(cornerRadius: 15 * scale)
            .fill(isFront ? theme.screen : Color.clear)
            .overlay(RoundedRectangle(cornerRadius: 15 * scale).fill(tint.opacity(fill)))
            .overlay(RoundedRectangle(cornerRadius: 15 * scale).stroke(border.opacity(still ? 0.9 : 0.85), lineWidth: 1.5))
            .overlay(
                Image(systemName: mode.symbolName)
                    .font(.system(size: 27 * scale, weight: .semibold))
                    .foregroundStyle(theme.ink)
            )
            .frame(width: size, height: size)
            .opacity(fade)
            .offset(x: x)
            .zIndex(1 - abs(d))
            .animation(.easeInOut(duration: 0.2), value: still)
    }

    // MARK: Interaction

    /// One gesture handles both: a touch that never travels past a few points is a tap on
    /// whichever tile is under it; anything further is a drag that scrubs the arc.
    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if dragStart == nil {
                    guard abs(value.translation.width) >= 6 else { return }
                    dragStart = position
                    haptics.prepare()
                }
                let raw = (dragStart ?? position) - Double(value.translation.width / pixelsPerTile)
                position = max(0, min(Double(modes.count - 1), raw))
                let nearest = Int(position.rounded())
                if nearest != lastNearest {
                    lastNearest = nearest
                    haptics.selection.selectionChanged()
                    haptics.selection.prepare()
                }
            }
            .onEnded { value in
                if dragStart == nil {
                    tap(atX: value.location.x - Self.arcWidth / 2)
                } else {
                    dragStart = nil
                    commit(Int(position.rounded()))
                }
            }
    }

    private func tap(atX x: CGFloat) {
        // Front-most tile under the touch wins (tiles overlap, nearest-to-front is on top).
        let hit = modes.indices
            .sorted { abs(Double($0) - position) < abs(Double($1) - position) }
            .first { index in
                let scale = 1 - 0.2 * min(1, abs(Double(index) - position))
                return abs(tileX(index) - x) <= frontSize * scale / 2
            }
        guard let hit else { return }
        haptics.prepare()
        commit(hit)
    }

    private func tileX(_ index: Int) -> CGFloat {
        let d = max(-1.4, min(1.4, Double(index) - position))
        return spacing * CGFloat(sin(d * 0.9) / sin(0.9))
    }

    private func move(to index: Int) {
        lastNearest = index
        if reduceMotion {
            withAnimation(.easeInOut(duration: 0.2)) { position = Double(index) }
        } else {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { position = Double(index) }
        }
    }

    /// Snaps to `index` and, if it's a different mode, commits it: strong haptic, the mode name
    /// for ~1.5s (so a switch is never silent even with system haptics off), and a VoiceOver
    /// announcement. Writing `app.travelMode` also persists it and starts the debounced reroute.
    private func commit(_ index: Int) {
        move(to: index)
        let mode = modes[index]
        guard mode != app.travelMode else { return }
        haptics.impact.impactOccurred()
        app.travelMode = mode
        withAnimation(.easeInOut(duration: 0.2)) { flashName = mode.displayName }
        nameTask?.cancel()
        nameTask = Task {
            try? await Task.sleep(for: .milliseconds(1500))
            if !Task.isCancelled { withAnimation(.easeInOut(duration: 0.2)) { flashName = nil } }
        }
        UIAccessibility.post(notification: .announcement, argument: mode.displayName)
    }
}
