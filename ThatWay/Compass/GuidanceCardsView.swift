//
//  GuidanceCardsView.swift
//  ThatWay
//
//  The way cards. Every instruction for the whole trip is built up front when the route
//  arrives (`RoutingManager.cards`); this file only presents them:
//  - `GuidanceCardStack`: the current instruction at the bottom of the screen, with the next
//    couple peeking out behind it like stacked notifications.
//  - `GuidanceCurtain`: pull the stack up and the full list slides over the compass and the
//    rest of the screen like a curtain — read-only, scrollable, current instruction highlighted.
//

import SwiftUI
import ThatWayCore
import ThatWayUI

extension GuidanceCard {
    /// The glyph for this card — the manoeuvre's own shape, so a slight bend, a full turn and a
    /// U-turn each look different.
    var symbolName: String {
        switch kind {
        case .depart: return "location.north.fill"
        case .arrive: return "flag.checkered"
        case .roundabout: return "arrow.triangle.turn.up.right.circle.fill"
        case .fork: return "arrow.triangle.branch"
        case .merge: return "arrow.triangle.merge"
        case .turn, .ramp, .keepGoing:
            let side = turn.side == .left ? "left" : "right"
            switch turn.side {
            case .straight: return "arrow.up"
            case .left, .right:
                switch turn.severity {
                case .slight: return "arrow.up.\(side)"
                case .normal: return "arrow.turn.up.\(side)"
                case .sharp, .uTurn: return "arrow.uturn.\(side)"
                }
            }
        }
    }
}

private struct CardIcon: View {
    let symbol: String
    let theme: AppTheme
    var highlighted = true
    var scale: CGFloat = 1

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12 * scale)
                .fill(highlighted ? theme.tint(0.16) : theme.ink.opacity(0.08))
            Image(systemName: symbol)
                .font(.system(size: 19 * scale, weight: .bold))
                .foregroundStyle(highlighted ? theme.accent : theme.ink.opacity(0.7))
        }
        .frame(width: 42 * scale, height: 42 * scale)
    }
}

// MARK: - Plain values the stacks draw

/// Everything one card shows, as values — so a card view can be skipped when none of it changed.
struct CardFace: Equatable {
    let id: Int
    let symbol: String
    let title: String
    let road: String
    let distance: String

    @MainActor
    init(_ card: GuidanceCard, app: AppModel) {
        id = card.id
        symbol = card.symbolName
        title = card.shortTitle
        road = card.kind == .arrive ? app.dest : card.shortRoad
        distance = app.fmt(app.routingManager.distanceTo(card))
    }
}

/// What the active-instruction stack shows. The stack takes this instead of observing the whole
/// `AppModel`, and is `Equatable`: a GPS fix, a heading change or the once-a-second dead-reckoned
/// update that doesn't change any text on the cards no longer re-renders them.
struct GuidanceStackState: Equatable {
    var themeID: ThemeID
    var front: CardFace?
    var phase: String
    var phaseHighlighted: Bool
    var peeks: [CardFace]
    var expanded: Bool

    @MainActor
    init(app: AppModel, showsPeeks: Bool) {
        let routing = app.routingManager
        let cards = routing.cards
        let index = routing.currentCardIndex
        themeID = app.theme
        front = index.map { CardFace(cards[$0], app: app) }
        phase = app.currentPhaseText
        phaseHighlighted = app.currentPhaseHighlighted
        peeks = showsPeeks && index != nil
            ? (1...2).compactMap { d in (index! + d < cards.count) ? CardFace(cards[index! + d], app: app) : nil }
            : []
        expanded = app.cardsExpanded
    }
}

/// What the "Up next" stack under the compass shows.
struct NextStackState: Equatable {
    var themeID: ThemeID
    var faces: [CardFace]
    var expanded: Bool

    @MainActor
    init(app: AppModel) {
        let routing = app.routingManager
        let cards = routing.cards
        let index = routing.currentCardIndex
        themeID = app.theme
        faces = index == nil ? [] : (1...3).compactMap { d in (index! + d < cards.count) ? CardFace(cards[index! + d], app: app) : nil }
        expanded = app.cardsExpanded
    }
}

// MARK: - Collapsed stack

private let cardSpring = Animation.spring(response: 0.6, dampingFraction: 0.82)

private func expand(_ app: AppModel) {
    withAnimation(.spring(response: 0.5, dampingFraction: 0.82)) { app.cardsExpanded = true }
}

/// A behind-the-front card in a stack: just the card's silhouette plus, when it's the first one
/// behind, a hint of its content — scaled and lowered by `depth` so the stack reads as layers.
private struct PeekCard: View {
    let face: CardFace
    let depth: Int
    let theme: AppTheme
    let namespace: Namespace.ID
    let height: CGFloat
    let expanded: Bool
    /// Which way the stack fans: down (the usual — behind cards peek out below) or up.
    var showsContent = false
    var scale: CGFloat = 1
    /// Text size factor, kept separate from the card's geometry `scale` so text stays readable
    /// when the cards shrink for a short screen. Defaults to `scale`.
    var fontScale: CGFloat?

    var body: some View {
        let f = fontScale ?? scale
        HStack(spacing: 14) {
            if showsContent {
                CardIcon(symbol: face.symbol, theme: theme, highlighted: false, scale: scale)
                VStack(alignment: .leading, spacing: 2) {
                    Text(face.title)
                        .font(.nunito(14 * f, .extraBold)).foregroundStyle(theme.ink)
                        .lineLimit(1).minimumScaleFactor(0.6)
                    if !face.road.isEmpty {
                        Text(face.road)
                            .font(.nunito(11.5 * f, .semibold)).foregroundStyle(theme.ink.opacity(0.75))
                            .lineLimit(1).minimumScaleFactor(0.6)
                    }
                }
                Spacer(minLength: 4)
                Text(face.distance)
                    .font(.nunito(15 * f, .black)).foregroundStyle(theme.ink.opacity(0.85))
                    .lineLimit(1).minimumScaleFactor(0.7)
            } else {
                Spacer()
            }
        }
        .padding(.horizontal, 14 * scale)
        .frame(height: height)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(theme.screen)
                .overlay(RoundedRectangle(cornerRadius: 20).fill(theme.surface(0.05)))
                .matchedGeometryEffect(id: face.id, in: namespace, isSource: !expanded)
        )
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(theme.borderColor))
        .scaleEffect(1 - CGFloat(max(0, depth - 1)) * 0.05, anchor: .top)
        .offset(y: CGFloat(max(0, depth - 1)) * 9)
        .opacity(1 - Double(max(0, depth - 1)) * 0.28)
        .zIndex(Double(10 - depth))
    }
}

/// The active instruction. Far from the destination it sits above the compass on its own; in the
/// last 500m (`showsPeeks`) it goes back to the bottom of the screen with the next two stacked
/// behind it.
struct GuidanceCardStack: View, Equatable {
    @Environment(\.dynamicTypeSize) private var typeSize
    let state: GuidanceStackState
    /// Not observed — only used to run the tap/END actions, so the stack never redraws just because
    /// something else in the model changed.
    let app: AppModel
    let theme: AppTheme
    let namespace: Namespace.ID
    var showsPeeks = true
    /// The top stack also opens when it's pulled *down* (there's nothing above it to scroll).
    var opensOnPullDown = false
    /// 1 on a full-size phone; down to ~0.72 on a short screen like the iPhone SE.
    var density: CGFloat = 1

    static func == (a: GuidanceCardStack, b: GuidanceCardStack) -> Bool {
        a.state == b.state && a.showsPeeks == b.showsPeeks && a.opensOnPullDown == b.opensOnPullDown && a.density == b.density
    }

    /// The cards are 1.5× their original size for readability at a glance.
    private var scale: CGFloat { 1.5 * density }
    /// Text keeps its full size on a short screen — only the card's height and icon shrink.
    private let fontScale: CGFloat = 1.5
    private var cardHeight: CGFloat { 84 * scale }

    var body: some View {
        let _ = Perf.hit("body.cards")
        ZStack(alignment: .top) {
            ForEach(Array(state.peeks.enumerated()), id: \.element.id) { offset, face in
                PeekCard(face: face, depth: offset + 2, theme: theme, namespace: namespace, height: cardHeight,
                         expanded: state.expanded, scale: scale, fontScale: 1.5)
                    .transition(.opacity)
            }
            front(face: state.front)
                .id(state.front?.id ?? -1)
                .transition(.asymmetric(insertion: .opacity, removal: .opacity.combined(with: .scale(scale: 0.94))))
                .zIndex(20)
        }
        .frame(minHeight: cardHeight + (showsPeeks ? 22 * density : 0), alignment: .top)
        .animation(cardSpring, value: state.front?.id)
        .contentShape(Rectangle())
        .onTapGesture { expand(app) }
        .gesture(
            DragGesture(minimumDistance: 10)
                .onEnded { value in
                    let dy = value.translation.height
                    if dy < -20 || (opensOnPullDown && dy > 20) { expand(app) }
                }
        )
    }

    private func front(face: CardFace?) -> some View {
        let stackedLayout = typeSize >= .xxxLarge
        let icon = CardIcon(symbol: face?.symbol ?? "flag.checkered", theme: theme, scale: scale)
        let texts = VStack(alignment: .leading, spacing: 3) {
            Text(face?.title ?? "Arrived")
                .font(.nunito(15 * fontScale, .extraBold)).foregroundStyle(theme.ink)
                .lineLimit(2).minimumScaleFactor(0.6)
            if let road = face?.road, !road.isEmpty {
                Text(road)
                    .font(.nunito(12 * fontScale, .bold)).foregroundStyle(theme.ink.opacity(0.85))
                    .lineLimit(2).minimumScaleFactor(0.6)
            }
            Text(state.phase)
                .font(.nunito(10 * fontScale, state.phaseHighlighted ? .black : .semibold))
                .foregroundStyle(state.phaseHighlighted ? theme.accent : theme.textSecondary)
                .glow(state.phaseHighlighted ? theme.accent.opacity(0.55) : .clear, radius: 6, theme: theme)
                .lineLimit(stackedLayout ? 2 : 1).minimumScaleFactor(0.7)
        }
        let distance = Group {
            if let face {
                Text(face.distance)
                    .font(.nunito(17 * fontScale, .black)).foregroundStyle(theme.accent)
                    .lineLimit(1).minimumScaleFactor(0.7)
            }
        }
        let endButton = Button { app.endGuidance() } label: {
            Text("END")
                .font(.nunito(10 * fontScale, .black)).tracking(0.9)
                .foregroundStyle(theme.accent)
                .fixedSize()
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(Capsule().fill(theme.tint(0.14)))
        }
        .buttonStyle(.plain)

        return Group {
            if stackedLayout {
                // Large text: the title gets the full width and the distance + END move to their own row,
                // so END is never squeezed into "E…".
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 14) { icon; texts; Spacer(minLength: 0) }
                    HStack { distance; Spacer(minLength: 8); endButton }
                }
            } else {
                HStack(spacing: 14) {
                    icon
                    texts
                    Spacer(minLength: 4)
                    VStack(alignment: .trailing, spacing: 10) { distance; endButton }
                }
            }
        }
        .padding(.horizontal, 14 * scale)
        .padding(.vertical, 8)
        .frame(minHeight: cardHeight)
        .background(
            RoundedRectangle(cornerRadius: 24)
                .fill(theme.screen)
                .overlay(RoundedRectangle(cornerRadius: 24).fill(theme.surface(0.07)))
                .matchedGeometryEffect(id: face?.id ?? -1, in: namespace, isSource: !state.expanded)
        )
        .overlay(RoundedRectangle(cornerRadius: 24).stroke(theme.outline(0.35)))
    }
}

/// The stack under the compass while the active card sits above it: the very next instruction,
/// with the ones after it layered behind. When the active instruction is done the next card here
/// slides up into the active slot, the ones behind move forward, and a new one appears at the back.
struct NextCardsStack: View, Equatable {
    let state: NextStackState
    let app: AppModel
    let theme: AppTheme
    let namespace: Namespace.ID

    var density: CGFloat = 1

    static func == (a: NextCardsStack, b: NextCardsStack) -> Bool { a.state == b.state && a.density == b.density }

    private var scale: CGFloat { 1.5 * density }
    private var cardHeight: CGFloat { 68 * scale }
    private var stackHeight: CGFloat { 68 * scale + 30 * density }

    var body: some View {
        let _ = Perf.hit("body.cards")
        VStack(alignment: .leading, spacing: 2) {
            if !state.faces.isEmpty {
                Text("Up next:")
                    .font(.nunito(14, .extraBold))
                    .tracking(0.4)
                    .foregroundStyle(theme.textSecondary)
                    .padding(.leading, 6)
                    .transition(.opacity)
            }
            ZStack(alignment: .top) {
                ForEach(Array(state.faces.enumerated()), id: \.element.id) { offset, face in
                    PeekCard(face: face, depth: offset + 1, theme: theme, namespace: namespace, height: cardHeight,
                             expanded: state.expanded, showsContent: offset == 0, scale: scale, fontScale: 1.5)
                        .transition(.opacity)
                }
            }
            .frame(height: stackHeight, alignment: .top)
        }
        .animation(cardSpring, value: state.faces.first?.id)
        .contentShape(Rectangle())
        .onTapGesture { expand(app) }
        .gesture(
            DragGesture(minimumDistance: 10)
                .onEnded { value in
                    if value.translation.height < -20 { expand(app) }
                }
        )
    }
}

// MARK: - Curtain

struct GuidanceCurtain: View {
    @EnvironmentObject var app: AppModel
    @Environment(\.dynamicTypeSize) private var typeSize
    let theme: AppTheme
    let namespace: Namespace.ID
    /// Once the list has settled, pulling down past its top (the first card already in view, and a
    /// further drag down) puts the cards back — no need to aim for the small handle.
    @State private var pullArmed = false

    var body: some View {
        let routing = app.routingManager
        let cards = routing.cards
        let currentIndex = routing.currentCardIndex ?? cards.count

        // No page, no panel: the cards themselves rise over the screen, and everything behind
        // them (compass, top bar, background) is blurred by CompassScreen while they're up.
        ZStack {
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture { close() }

            VStack(spacing: 0) {
                grabber
                ScrollViewReader { proxy in
                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 10) {
                            ForEach(Array(cards.enumerated()), id: \.element.id) { offset, card in
                                row(card, offset: offset, currentIndex: currentIndex)
                                    .id(card.id)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                    }
                    .onScrollGeometryChange(for: CGFloat.self) { $0.contentOffset.y + $0.contentInsets.top } action: { _, offset in
                        if pullArmed, offset < -55 { close() }
                    }
                    .onAppear {
                        scrollToCurrent(proxy, cards: cards, animated: false)
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { pullArmed = true }
                    }
                    .onDisappear { pullArmed = false }
                    .onChange(of: currentIndex) { _, _ in scrollToCurrent(proxy, cards: cards, animated: true) }
                }
            }
            .padding(.top, 70)
        }
    }

    /// A small handle above the cards — drag it (or the cards' background) down to put them back.
    private var grabber: some View {
        Capsule().fill(theme.ink.opacity(0.35)).frame(width: 40, height: 5)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
            .onTapGesture { close() }
            .gesture(DragGesture(minimumDistance: 8).onEnded { value in
                if value.translation.height > 25 { close() }
            })
    }

    private func close() {
        withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) { app.cardsExpanded = false }
    }

    private func scrollToCurrent(_ proxy: ScrollViewProxy, cards: [GuidanceCard], animated: Bool) {
        guard let id = app.routingManager.upcomingCard?.id ?? cards.last?.id else { return }
        if animated {
            withAnimation(.easeInOut(duration: 0.35)) { proxy.scrollTo(id, anchor: .center) }
        } else {
            proxy.scrollTo(id, anchor: .center)
        }
    }

    private func row(_ card: GuidanceCard, offset: Int, currentIndex: Int) -> some View {
        let isPast = offset < currentIndex
        let isCurrent = offset == currentIndex
        let stackedLayout = typeSize >= .xxxLarge
        let icon = CardIcon(symbol: card.symbolName, theme: theme, highlighted: isCurrent)
        let texts = VStack(alignment: .leading, spacing: 3) {
            Text(card.title)
                .font(.nunito(isCurrent ? 15 : 14, .extraBold)).foregroundStyle(theme.ink)
                .fixedSize(horizontal: false, vertical: true)
            Text(subtitle(for: card))
                .font(.nunito(12, .semibold)).foregroundStyle(theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        let trailing = Group {
            if isPast {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 18)).foregroundStyle(theme.ink.opacity(0.35))
            } else if card.kind != .depart {
                VStack(alignment: stackedLayout ? .leading : .trailing, spacing: 2) {
                    if isCurrent {
                        Text("NEXT").font(.nunito(9, .black)).tracking(1).foregroundStyle(theme.accent)
                    }
                    Text(app.fmt(app.routingManager.distanceTo(card)))
                    .font(.nunito(isCurrent ? 18 : 15, .black))
                    .foregroundStyle(isCurrent ? theme.accent : theme.ink.opacity(0.8))
                }
            }
        }
        return Group {
            if stackedLayout {
                // Large text: the instruction gets the full width and the distance sits on its own line below it.
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .top, spacing: 12) { icon; texts; Spacer(minLength: 0) }
                    HStack { trailing; Spacer(minLength: 0) }
                }
            } else {
                HStack(spacing: 12) { icon; texts; Spacer(minLength: 6); trailing }
            }
        }
        .padding(.horizontal, 14).padding(.vertical, isCurrent ? 14 : 11)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(theme.screen.opacity(0.88))
                .overlay(RoundedRectangle(cornerRadius: 20).fill(isCurrent ? theme.tint(0.14) : theme.surface(0.05)))
                .matchedGeometryEffect(id: card.id, in: namespace, isSource: app.cardsExpanded)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(isCurrent ? theme.outline(0.7) : theme.borderColor, lineWidth: isCurrent ? 1.5 : 1)
        )
        .glow(isCurrent ? theme.accent.opacity(0.25) : .clear, radius: 10, theme: theme)
        .opacity(isPast ? 0.45 : 1)
        // The glow glides from one card to the next as the trip advances.
        .animation(.easeInOut(duration: 0.4), value: isCurrent)
    }

    private func subtitle(for card: GuidanceCard) -> String {
        switch card.kind {
        case .arrive:
            return app.dest.isEmpty ? "Your destination" : app.dest
        default:
            let leg = app.fmt(card.legLength)
            if card.roadName.isEmpty || card.kind == .depart {
                return card.legLength > 0 ? "Then continue for \(leg)" : ""
            }
            return card.legLength > 0 ? "Follow \(card.roadName) for \(leg)" : card.roadName
        }
    }
}
