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
    let card: GuidanceCard
    let theme: AppTheme
    var highlighted = true
    var scale: CGFloat = 1

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12 * scale)
                .fill(highlighted ? theme.accent.opacity(0.16) : theme.ink.opacity(0.08))
            Image(systemName: card.symbolName)
                .font(.system(size: 19 * scale, weight: .bold))
                .foregroundStyle(highlighted ? theme.accent : theme.ink.opacity(0.7))
        }
        .frame(width: 42 * scale, height: 42 * scale)
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
    @EnvironmentObject var app: AppModel
    let card: GuidanceCard
    let depth: Int
    let theme: AppTheme
    let namespace: Namespace.ID
    let height: CGFloat
    /// Which way the stack fans: down (the usual — behind cards peek out below) or up.
    var showsContent = false
    var scale: CGFloat = 1

    var body: some View {
        HStack(spacing: 14) {
            if showsContent {
                CardIcon(card: card, theme: theme, highlighted: false, scale: scale)
                VStack(alignment: .leading, spacing: 2) {
                    Text(card.shortTitle)
                        .font(.nunito(14 * scale, .extraBold)).foregroundStyle(theme.ink)
                        .lineLimit(1).minimumScaleFactor(0.6)
                    let road = card.kind == .arrive ? app.dest : card.shortRoad
                    if !road.isEmpty {
                        Text(road)
                            .font(.nunito(11.5 * scale, .semibold)).foregroundStyle(theme.ink.opacity(0.75))
                            .lineLimit(1).minimumScaleFactor(0.6)
                    }
                }
                Spacer(minLength: 4)
                Text(app.fmt(app.routingManager.distanceTo(card)))
                    .font(.nunito(15 * scale, .black)).foregroundStyle(theme.ink.opacity(0.85))
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
                .overlay(RoundedRectangle(cornerRadius: 20).fill(theme.ink.opacity(0.05)))
                .matchedGeometryEffect(id: card.id, in: namespace, isSource: !app.cardsExpanded)
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
struct GuidanceCardStack: View {
    @EnvironmentObject var app: AppModel
    let theme: AppTheme
    let namespace: Namespace.ID
    var showsPeeks = true
    /// The top stack also opens when it's pulled *down* (there's nothing above it to scroll).
    var opensOnPullDown = false

    /// The cards are 1.5× their original size for readability at a glance.
    private let scale: CGFloat = 1.5
    private var cardHeight: CGFloat { 84 * scale }

    var body: some View {
        let routing = app.routingManager
        let cards = routing.cards
        let index = routing.currentCardIndex
        let peeks: [(card: GuidanceCard, depth: Int)] = showsPeeks && index != nil
            ? (1...2).compactMap { d in (index! + d < cards.count) ? (cards[index! + d], d + 1) : nil }
            : []

        ZStack(alignment: .top) {
            ForEach(peeks, id: \.card.id) { item in
                PeekCard(card: item.card, depth: item.depth, theme: theme, namespace: namespace, height: cardHeight, scale: scale)
                    .transition(.opacity)
            }
            front(card: index.map { cards[$0] })
                .id(index.map { cards[$0].id } ?? -1)
                .transition(.asymmetric(insertion: .opacity, removal: .opacity.combined(with: .scale(scale: 0.94))))
                .zIndex(20)
        }
        .frame(height: cardHeight + (showsPeeks ? 22 : 0), alignment: .top)
        .animation(cardSpring, value: index)
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

    private func front(card: GuidanceCard?) -> some View {
        HStack(spacing: 14) {
            CardIcon(card: card ?? arrivedPlaceholder, theme: theme, scale: scale)
            VStack(alignment: .leading, spacing: 3) {
                Text(card?.shortTitle ?? "Arrived")
                    .font(.nunito(15 * scale, .extraBold)).foregroundStyle(theme.ink)
                    .lineLimit(1).minimumScaleFactor(0.6)
                let road = card?.kind == .arrive ? app.dest : (card?.shortRoad ?? "")
                if !road.isEmpty {
                    Text(road)
                        .font(.nunito(12 * scale, .bold)).foregroundStyle(theme.ink.opacity(0.85))
                        .lineLimit(1).minimumScaleFactor(0.6)
                }
                Text(app.currentPhaseText)
                    .font(.nunito(10 * scale, app.currentPhaseHighlighted ? .black : .semibold))
                    .foregroundStyle(app.currentPhaseHighlighted ? theme.accent : theme.textSecondary)
                    .shadow(color: app.currentPhaseHighlighted ? theme.accent.opacity(0.55) : .clear, radius: 6)
                    .lineLimit(1).minimumScaleFactor(0.7)
            }
            Spacer(minLength: 4)
            VStack(alignment: .trailing, spacing: 10) {
                if card != nil {
                    Text(app.fmt(app.distanceToManeuver))
                        .font(.nunito(17 * scale, .black)).foregroundStyle(theme.accent)
                        .lineLimit(1).minimumScaleFactor(0.7)
                }
                Button { app.endGuidance() } label: {
                    Text("END")
                        .font(.nunito(10 * scale, .black)).tracking(0.9)
                        .foregroundStyle(theme.accent)
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(Capsule().fill(theme.accent.opacity(0.14)))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14 * scale)
        .frame(height: cardHeight)
        .background(
            RoundedRectangle(cornerRadius: 24)
                .fill(theme.screen)
                .overlay(RoundedRectangle(cornerRadius: 24).fill(theme.ink.opacity(0.07)))
                .matchedGeometryEffect(id: card?.id ?? -1, in: namespace, isSource: !app.cardsExpanded)
        )
        .overlay(RoundedRectangle(cornerRadius: 24).stroke(theme.accent.opacity(0.35)))
    }

    private var arrivedPlaceholder: GuidanceCard {
        GuidanceCard(id: -1, kind: .arrive, title: "", shortTitle: "", shortRoad: "", roadName: "", turn: .straight, exitNumber: nil,
                     coordinate: app.currentPosition, exitCoordinate: app.currentPosition,
                     startAlong: 0, completeAlong: 0, legLength: 0)
    }
}

/// The stack under the compass while the active card sits above it: the very next instruction,
/// with the ones after it layered behind. When the active instruction is done the next card here
/// slides up into the active slot, the ones behind move forward, and a new one appears at the back.
struct NextCardsStack: View {
    @EnvironmentObject var app: AppModel
    let theme: AppTheme
    let namespace: Namespace.ID

    private let scale: CGFloat = 1.5
    private var cardHeight: CGFloat { 68 * scale }
    static let stackHeight: CGFloat = 68 * 1.5 + 30

    var body: some View {
        let routing = app.routingManager
        let cards = routing.cards
        let index = routing.currentCardIndex
        let visible: [(card: GuidanceCard, depth: Int)] = index == nil ? [] :
            (1...3).compactMap { d in (index! + d < cards.count) ? (cards[index! + d], d) : nil }

        ZStack(alignment: .top) {
            ForEach(visible, id: \.card.id) { item in
                PeekCard(card: item.card, depth: item.depth, theme: theme, namespace: namespace,
                         height: cardHeight, showsContent: item.depth == 1, scale: scale)
                    .transition(.opacity)
            }
        }
        .frame(height: Self.stackHeight, alignment: .top)
        .animation(cardSpring, value: index)
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
        return HStack(spacing: 12) {
            CardIcon(card: card, theme: theme, highlighted: isCurrent)
            VStack(alignment: .leading, spacing: 3) {
                Text(card.title)
                    .font(.nunito(isCurrent ? 15 : 14, .extraBold)).foregroundStyle(theme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Text(subtitle(for: card))
                    .font(.nunito(12, .semibold)).foregroundStyle(theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 6)
            if isPast {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 18)).foregroundStyle(theme.ink.opacity(0.35))
            } else if card.kind != .depart {
                VStack(alignment: .trailing, spacing: 2) {
                    if isCurrent {
                        Text("NEXT").font(.nunito(9, .black)).tracking(1).foregroundStyle(theme.accent)
                    }
                    Text(app.fmt(app.routingManager.distanceTo(card)))
                    .font(.nunito(isCurrent ? 18 : 15, .black))
                    .foregroundStyle(isCurrent ? theme.accent : theme.ink.opacity(0.8))
                }
            }
        }
        .padding(.horizontal, 14).padding(.vertical, isCurrent ? 14 : 11)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(theme.screen.opacity(0.88))
                .overlay(RoundedRectangle(cornerRadius: 20).fill(isCurrent ? theme.accent.opacity(0.14) : theme.ink.opacity(0.05)))
                .matchedGeometryEffect(id: card.id, in: namespace, isSource: app.cardsExpanded)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(isCurrent ? theme.accent.opacity(0.7) : theme.borderColor, lineWidth: isCurrent ? 1.5 : 1)
        )
        .shadow(color: isCurrent ? theme.accent.opacity(0.25) : .clear, radius: 10)
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
