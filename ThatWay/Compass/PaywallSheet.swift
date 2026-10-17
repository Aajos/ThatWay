//
//  PaywallSheet.swift
//  ThatWay
//
//  A placeholder paywall. Nothing is charged: "Unlock" flips the dummy entitlement so the whole flow can be tried.
//

import SwiftUI
import ThatWayCore
import ThatWayUI

struct PaywallSheet: View {
    @ObservedObject var entitlements: Entitlements
    let theme: AppTheme
    let close: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "person.2.wave.2.fill").font(.system(size: 40, weight: .bold)).foregroundStyle(theme.accent)
                .padding(.top, 28).accessibilityHidden(true)
            Text("Trace your friends").font(.nunito(24, .black)).foregroundStyle(theme.ink)
            VStack(alignment: .leading, spacing: 10) {
                benefit("location.north.line", "Point the compass at a friend, at any distance")
                benefit("arrowshape.turn.up.right", "Get turn-by-turn directions to them, even as they move")
                benefit("lock.shield", "Only with their say-so: they accept, and either of you can stop")
            }
            .padding(.horizontal, 24)
            Text("Adding friends is always free.").font(.nunito(12, .semibold)).foregroundStyle(theme.textSecondary)
            Spacer(minLength: 8)
            Button {
                entitlements.unlockForTesting(); close()
            } label: {
                Text("UNLOCK (TEST, NO CHARGE)").font(.nunito(14, .black)).tracking(0.6).foregroundStyle(theme.onAccent)
                    .frame(maxWidth: .infinity).frame(height: 52)
                    .background(RoundedRectangle(cornerRadius: 16).fill(theme.accent))
            }
            .buttonStyle(.plain)
            Button("Not now", action: close).font(.nunito(13, .extraBold)).foregroundStyle(theme.textSecondary).padding(.bottom, 12)
        }
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme.screen.ignoresSafeArea())
        .presentationDetents([.medium, .large])
    }

    private func benefit(_ icon: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon).foregroundStyle(theme.accent).frame(width: 24)
            Text(text).font(.nunito(14, .semibold)).foregroundStyle(theme.ink).fixedSize(horizontal: false, vertical: true)
        }
    }
}
