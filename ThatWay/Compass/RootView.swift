//
//  RootView.swift
//  ThatWay
//
//  Hosts the four Compass Nav screens, the persistent tab bar, and the
//  full-screen search/avatar overlays.
//

import SwiftUI
import ThatWayUI

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
                case .signedOut, .needsConfirmation, .needsAppleUsername, .resettingPassword:
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
                // The selection is passed in (not read from the environment inside the bar): RootView is what re-renders
                // when the screen changes, and the bar used to keep showing WAY as selected while another tab was open.
                TabBar(selected: app.screen, navigating: !app.isIdle, friends: app.friendsManager)
                    .id(app.screen)      // rebuilt on every change: without this the bar kept showing WAY as selected
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

    let selected: AppScreen
    let navigating: Bool
    @ObservedObject var friends: FriendsManager
    @Namespace private var bubble

    var body: some View {
        let theme = app.currentTheme
        HStack(spacing: 10) {
            ForEach(AppScreen.allCases) { s in
                let isSelected = selected == s
                Button { withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { app.selectTab(s) } } label: {
                    VStack(spacing: 5) {
                        ZStack(alignment: .topTrailing) {
                            Image(systemName: s.symbolName)
                                .font(.system(size: 19, weight: .semibold))
                            // Navigating or pointing is a separate signal from "this tab is open": a small dot on WAY.
                            if s == .compass, navigating {
                                Circle().fill(theme.accent).frame(width: 8, height: 8)
                                    .overlay(Circle().stroke(theme.screen, lineWidth: 1.5))
                                    .offset(x: 6, y: -3)
                                    .accessibilityHidden(true)
                            }
                            // A friend request is waiting (only when they are held for a decision): a dot on YOU.
                            if s == .profile, friends.requestPolicy == .requestsOnly, !friends.incomingRequests.isEmpty {
                                Circle().fill(theme.needleRed).frame(width: 9, height: 9)
                                    .overlay(Circle().stroke(theme.screen, lineWidth: 1.5))
                                    .offset(x: 7, y: -3)
                                    .accessibilityHidden(true)
                            }
                        }
                        Text(s.label).font(.nunito(11, .extraBold)).tracking(0.6)
                    }
                    .foregroundStyle(isSelected ? theme.accent : theme.ink.opacity(0.5))
                    .frame(width: 74)
                    .padding(.vertical, 8)
                    .background {
                        if isSelected {
                            // The bubble slides to whichever tab is open.
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .fill(theme.accent.opacity(theme.light ? 0.16 : 0.2))
                                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(theme.accent.opacity(0.45), lineWidth: 1))
                                .matchedGeometryEffect(id: "tabBubble", in: bubble)
                        }
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(s.label.capitalized + (s == .compass && navigating ? ", navigating" : "") + (s == .profile && friends.requestPolicy == .requestsOnly && !friends.incomingRequests.isEmpty ? ", friend request waiting" : ""))
                .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
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
        .sensoryFeedback(.selection, trigger: selected)
    }
}
