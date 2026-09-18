//
//  RootView.swift
//  ThatWay
//
//  Hosts the four Compass Nav screens, the persistent tab bar, and the
//  full-screen search/avatar overlays.
//

import SwiftUI

struct RootView: View {
    @StateObject private var app = AppModel()

    var body: some View {
        ZStack {
            app.currentTheme.screen.ignoresSafeArea()

            Group {
                switch app.screen {
                case .compass: CompassScreen()
                case .map: MapScreen()
                case .store: StoreScreen()
                case .profile: ProfileScreen()
                }
            }
            .foregroundStyle(app.currentTheme.ink)

            VStack {
                Spacer()
                TabBar()
            }

            if app.avatarSheet {
                AvatarSheet().transition(.move(edge: .bottom))
            }
        }
        .environmentObject(app)
        .environmentObject(app.routingManager)
        .environmentObject(app.routeDataGenerator)
        .animation(.easeInOut(duration: 0.25), value: app.avatarSheet)
        .animation(.easeInOut(duration: 0.5), value: app.theme)
        .preferredColorScheme(app.currentTheme.light ? .light : .dark)
    }
}

private struct TabBar: View {
    @EnvironmentObject var app: AppModel

    var body: some View {
        let theme = app.currentTheme
        HStack(spacing: 18) {
            ForEach(AppScreen.allCases) { s in
                Button { app.selectTab(s) } label: {
                    VStack(spacing: 6) {
                        Image(systemName: s.symbolName)
                            .font(.system(size: 19, weight: .semibold))
                            .foregroundStyle(app.screen == s ? theme.accent : theme.ink)
                        Text(s.label).font(.nunito(10, .extraBold)).tracking(0.6).foregroundStyle(theme.ink)
                    }
                    .opacity(app.screen == s ? 1 : 0.34)
                    .frame(width: 74)
                    .padding(.vertical, 8)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.top, 8)
        .frame(maxWidth: .infinity)
        .frame(height: 82)
        .background(
            LinearGradient(colors: [.clear, theme.screen], startPoint: .top, endPoint: .init(x: 0.5, y: 0.42))
                .ignoresSafeArea(edges: .bottom)
        )
        .opacity(app.avatarSheet || app.searchOpen ? 0 : 1)
        .offset(y: 20)
        .sensoryFeedback(.selection, trigger: app.screen)
    }
}
