//
//  PaywallSheet.swift
//  ThatWay
//
//  The plans, as StoreKit reports them (real prices in the person's own store), with what each one is in plain words. In test
//  builds two extra buttons unlock without a purchase so the flow can be tried; they do not exist in a release build.
//  Nothing is pre-selected and nothing is bought without Apple's own confirmation sheet.
//

import SwiftUI
import ThatWayCore
import ThatWayUI

struct PaywallSheet: View {
    @ObservedObject var entitlements: Entitlements
    @ObservedObject var store: PlanStore
    let theme: AppTheme
    let close: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                Image(systemName: "person.2.wave.2.fill").font(.system(size: 40, weight: .bold)).foregroundStyle(theme.accent)
                    .padding(.top, 28).accessibilityHidden(true)
                Text("Trace your friends").font(.nunito(24, .black)).foregroundStyle(theme.ink)
                VStack(alignment: .leading, spacing: 10) {
                    benefit("location.north.line", "Point the compass at a friend, at any distance")
                    benefit("arrowshape.turn.up.right", "Get turn-by-turn directions to where they were last seen")
                    benefit("lock.shield", "Only with their say-so: they choose how long, and they can stop it at any time")
                }
                Text("Adding friends is always free, and so is saying yes when a friend asks to trace you.")
                    .font(.nunito(12, .semibold)).foregroundStyle(theme.textSecondary).multilineTextAlignment(.center)

                if store.offers.isEmpty {
                    Text(store.loaded ? "Plans aren’t on sale yet." : "Loading plans…")
                        .font(.nunito(13, .extraBold)).foregroundStyle(theme.textSecondary).padding(.vertical, 8)
                } else {
                    VStack(spacing: 10) { ForEach(store.offers) { offer in offerRow(offer) } }
                }

                if let message = store.message {
                    Text(message).font(.nunito(12, .extraBold)).foregroundStyle(theme.ink).multilineTextAlignment(.center)
                }

                #if DEBUG
                VStack(spacing: 8) {
                    testButton("UNLOCK (TEST, NO CHARGE)") { entitlements.unlockForTesting(); close() }
                    testButton("3-HOUR PASS (TEST, ENDS IN 3 H)") { entitlements.unlockForTesting(hours: 3); close() }
                }
                #endif

                Button("Restore purchases") { Task { await store.restore() } }
                    .font(.nunito(13, .extraBold)).foregroundStyle(theme.accent).disabled(store.isWorking)
                Text("Purchases are processed by Apple. Refunds are decided by Apple, and a subscription is cancelled in your Apple ID settings. A pass starts as soon as you buy it, and buying another adds to the time left. A trace plan ends when its time is up, and tracing ends with it.")
                    .font(.nunito(11, .semibold)).foregroundStyle(theme.textSecondary).multilineTextAlignment(.center)
                Button("Not now", action: close).font(.nunito(13, .extraBold)).foregroundStyle(theme.textSecondary).padding(.bottom, 12)
            }
            .padding(.horizontal, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme.screen.ignoresSafeArea())
        .presentationDetents([.medium, .large])
        .task { await store.loadOffers() }
        // A plan that arrives (bought here, or approved later) closes the sheet.
        .onChange(of: entitlements.canTraceFriends) { _, now in if now { close() } }
    }

    private func offerRow(_ offer: PlanOffer) -> some View {
        Button { Task { await store.buy(offer.plan) } } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(offer.plan.title).font(.nunito(16, .black)).foregroundStyle(theme.ink)
                    Text(offer.plan.detail).font(.nunito(11, .semibold)).foregroundStyle(theme.textSecondary)
                        .multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                Text(offer.price).font(.nunito(15, .black)).foregroundStyle(theme.onAccent)
                    .padding(.horizontal, 14).padding(.vertical, 9).background(Capsule().fill(theme.accent))
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 16).fill(theme.ink.opacity(0.06)))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(theme.ink.opacity(0.1)))
        }
        .buttonStyle(.plain)
        .disabled(store.isWorking)
        .accessibilityLabel("\(offer.plan.title), \(offer.price). \(offer.plan.detail)")
    }

    #if DEBUG
    private func testButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.nunito(12, .black)).tracking(0.6).foregroundStyle(theme.ink)
                .frame(maxWidth: .infinity).frame(height: 44)
                .background(RoundedRectangle(cornerRadius: 14).fill(theme.ink.opacity(0.08)))
        }
        .buttonStyle(.plain)
    }
    #endif

    private func benefit(_ icon: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon).foregroundStyle(theme.accent).frame(width: 24)
            Text(text).font(.nunito(14, .semibold)).foregroundStyle(theme.ink).fixedSize(horizontal: false, vertical: true)
        }
    }
}
