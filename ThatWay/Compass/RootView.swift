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
            if app.searchOpen {
                SearchSheet().transition(.move(edge: .bottom))
            }
        }
        .environmentObject(app)
        .animation(.easeInOut(duration: 0.25), value: app.avatarSheet)
        .animation(.easeInOut(duration: 0.25), value: app.searchOpen)
        .animation(.easeInOut(duration: 0.5), value: app.theme)
        .preferredColorScheme(app.currentTheme.light ? .light : .dark)
    }
}

private struct TabBar: View {
    @EnvironmentObject var app: AppModel

    var body: some View {
        let theme = app.currentTheme
        HStack(spacing: 6) {
            ForEach(AppScreen.allCases) { s in
                Button { app.selectTab(s) } label: {
                    VStack(spacing: 6) {
                        TabGlyph(screen: s).stroke(theme.ink, lineWidth: 1.8).frame(width: 20, height: 20)
                        Text(s.label).font(.system(size: 10, weight: .heavy)).tracking(0.6).foregroundStyle(theme.ink)
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
    }
}

/// A small shape per tab echoing the design's per-tab corner radii
/// (circle for Compass, square for Map, asymmetric for Store/You).
private struct TabGlyph: Shape {
    let screen: AppScreen

    func path(in rect: CGRect) -> Path {
        switch screen {
        case .compass:
            return Circle().path(in: rect)
        case .map:
            return RoundedRectangle(cornerRadius: 4).path(in: rect)
        case .store:
            return UnevenRoundedRectangle(topLeadingRadius: 4, bottomLeadingRadius: 12, bottomTrailingRadius: 4, topTrailingRadius: 12).path(in: rect)
        case .profile:
            return UnevenRoundedRectangle(topLeadingRadius: 10, bottomLeadingRadius: 8, bottomTrailingRadius: 8, topTrailingRadius: 10).path(in: rect)
        }
    }
}
