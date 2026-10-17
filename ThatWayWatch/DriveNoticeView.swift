//
//  DriveNoticeView.swift
//  ThatWayWatch
//
//  Shown when the iPhone is in Drive mode. Looking at a wrist while driving is unsafe, so the watch stops
//  guiding, says why, and closes itself a few seconds later.
//
//  Note: watchOS has no "quit" for apps; calling `exit` is the only way for the app to close itself. It is fine for
//  this spike but App Review frowns on apps that terminate themselves, so revisit before shipping.
//

import SwiftUI
import ThatWayUI

enum WatchPolicy {
    /// Seconds the notice stays before the app closes itself.
    static let closeAfter: TimeInterval = 6
    static var closesItselfWhenDriving = true
}

struct DriveNoticeView: View {
    let theme: AppTheme
    @State private var secondsLeft = Int(WatchPolicy.closeAfter)

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "car.fill").font(.system(size: 30, weight: .black)).foregroundStyle(theme.accent)
                .glow(theme.accent.opacity(0.5), radius: 8, theme: theme)
            Text("Not while driving").font(.nunito(17, .black)).foregroundStyle(theme.ink).lineLimit(2).minimumScaleFactor(0.7).multilineTextAlignment(.center)
            Text("Watch guidance is unsafe in the car. Use your iPhone.").font(.nunito(13, .semibold))
                .foregroundStyle(theme.textSecondary).multilineTextAlignment(.center).lineLimit(5).minimumScaleFactor(0.8).fixedSize(horizontal: false, vertical: true)
            if WatchPolicy.closesItselfWhenDriving {
                Text("Closing in \(secondsLeft)").font(.nunito(12, .extraBold)).foregroundStyle(theme.ink.opacity(0.6)).padding(.top, 2)
            }
        }
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme.screen)
        .task {
            guard WatchPolicy.closesItselfWhenDriving else { return }
            for remaining in stride(from: Int(WatchPolicy.closeAfter) - 1, through: 0, by: -1) {
                try? await Task.sleep(for: .seconds(1))
                secondsLeft = remaining
            }
            exit(0)
        }
    }
}
