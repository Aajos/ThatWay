//
//  ToolsView.swift
//  ThatWayWatch
//
//  The test pages (heading debug, wrist-down session, haptic blind test), tucked behind the ⋯ button now that the
//  main screen is driven by swipes.
//

import SwiftUI

struct ToolsView: View {
    var body: some View {
        // Safe-area padding (not plain padding) so each page scrolls full-bleed but its content stays clear of the rounded
        // corners and the page dots.
        TabView {
            DebugView().safeAreaPadding(.horizontal, 8).safeAreaPadding(.bottom, 18)
            SessionView().safeAreaPadding(.horizontal, 8).safeAreaPadding(.bottom, 18)
            HapticsView().safeAreaPadding(.horizontal, 8).safeAreaPadding(.bottom, 18)
        }
        .tabViewStyle(.page)
    }
}
