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
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ZStack {
            app.currentTheme.screen.ignoresSafeArea()

            if !Config.backendEnabled {
                // See Config.backendEnabled — the AWS backend isn't provisioned yet, so skip
                // the sign-in gate entirely rather than block the rest of the app on it.
                signedInContent
            } else {
                switch app.authManager.authState {
                case .restoring:
                    EmptyView()
                case .signedOut, .needsConfirmation, .needsAppleUsername:
                    AuthScreen()
                case .signedIn:
                    signedInContent
                }
            }
        }
        .onChange(of: scenePhase) { _, phase in app.setSceneActive(phase == .active) }
        .environmentObject(app)
        .environmentObject(app.routingManager)
        .environmentObject(app.routeDataGenerator)
        .environmentObject(app.authManager)
        .environmentObject(app.friendsManager)
        .animation(.easeInOut(duration: 0.25), value: app.avatarSheet)
        .animation(.easeInOut(duration: 0.5), value: app.theme)
        .preferredColorScheme(app.currentTheme.light ? .light : .dark)
    }

    @ViewBuilder
    private var signedInContent: some View {
        ZStack {
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
        // On a wide screen (iPad, an unfolded foldable) the app stays a phone-width column in the
        // middle rather than stretching every control to fit.
        .frame(maxWidth: 480)
    }
}

private struct TabBar: View {
    @EnvironmentObject var app: AppModel

    /// Phones with a Home button (iPhone SE) have no bottom safe-area inset, so the bar's labels sat
    /// right on the screen's edge; lift the bar a little there. Face ID phones already clear the
    /// home indicator and get none.
    private var bottomLeeway: CGFloat {
        let inset = UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.keyWindow?.safeAreaInsets.bottom }.first
        return inset == 0 ? 6 : 0   // unknown (no window yet) counts as none
    }

    var body: some View {
        let theme = app.currentTheme
        HStack(spacing: 18) {
            ForEach(AppScreen.allCases) { s in
                Button { app.selectTab(s) } label: {
                    VStack(spacing: 6) {
                        Image(systemName: s.symbolName)
                            .font(.system(size: 19, weight: .semibold))
                            .foregroundStyle(app.screen == s ? theme.accent : theme.ink)
                        Text(s.label).font(.nunito(11, .extraBold)).tracking(0.6).foregroundStyle(theme.ink)
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
        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
        .background(
            LinearGradient(colors: [.clear, theme.screen], startPoint: .top, endPoint: .init(x: 0.5, y: 0.42))
                .ignoresSafeArea(edges: .bottom)
        )
        .opacity(app.avatarSheet || app.searchOpen || app.cardsExpanded ? 0 : 1)
        .offset(y: 20 - bottomLeeway)
        .sensoryFeedback(.selection, trigger: app.screen)
    }
}
