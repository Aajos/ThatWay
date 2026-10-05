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
        TabView {
            DebugView()
            SessionView()
            HapticsView()
        }
        .tabViewStyle(.page)
    }
}
