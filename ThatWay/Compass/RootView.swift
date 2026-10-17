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
    @State private var showLockHelp = false
    @State private var closingAccount = false

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
                    if app.safetyManager.needsReactivation {
                        // A deactivated account that signs in must choose before anything else.
                        ReactivationScreen(safety: app.safetyManager, theme: app.currentTheme,
                                           deleteInstead: { closingAccount = true }, signOut: { app.signOutEverywhere() })
                            .sheet(isPresented: $closingAccount) { closeAccountSheet }
                    } else {
                        signedInContent
                    }
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
            VStack(spacing: 6) {
                // Banners that stay for as long as they are true, on every tab: who can trace you, and a phone with no lock.
                StatusBanners(trace: app.traceManager, lock: app.screenLock, theme: app.currentTheme,
                              openTraced: { app.selectTab(.profile) }, openLockHelp: { showLockHelp = true })
                    .zIndex(1)         // above the compass backdrop, which paints past its own edges
                Group {
                    switch app.screen {
                    case .compass: CompassScreen()
                    case .map: MapScreen()
                    case .store: StoreScreen()
                    case .profile: ProfileScreen()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .foregroundStyle(app.currentTheme.ink)

            VStack {
                Spacer()
                // The selection is passed in (not read from the environment inside the bar): RootView is what re-renders
                // when the screen changes, and the bar used to keep showing WAY as selected while another tab was open.
                TabBar(selected: app.screen, navigating: !app.isIdle, friends: app.friendsManager, trace: app.traceManager, themeID: app.theme)
                    .id("\(app.screen)-\(app.theme.rawValue)")      // rebuilt on every tab or theme change: without this the bar kept showing WAY as selected
            }

            if app.avatarSheet {
                AvatarSheet().transition(.move(edge: .bottom))
            }
        }
        // On a wide screen (iPad, an unfolded foldable) the app stays a phone-width column in the
        // middle rather than stretching every control to fit.
        .frame(maxWidth: 480)
        .sheet(isPresented: $showLockHelp) {
            ScreenLockHelpSheet(theme: app.currentTheme, hasAppPasscode: app.authManager.currentUser.map { app.ownerAuth.appPasscode.isSet(for: $0.id) } ?? false) { showLockHelp = false }
        }
        // "X is still tracing you. Want to stop?" (at most every 30 minutes while they keep looking.)
        .alert(
            app.traceManager.stillTracing.map { TraceCopy.stillTracing(name: $0.username) } ?? "",
            isPresented: Binding(get: { app.traceManager.stillTracing != nil }, set: { if !$0 { app.traceManager.dismissStillTracing() } })
        ) {
            Button("Stop tracing", role: .destructive) {
                if let friend = app.traceManager.stillTracing, let watcher = app.traceManager.watchers.first(where: { $0.id == friend.id }) {
                    Task { await app.traceManager.revoke(watcher) }
                }
                app.traceManager.dismissStillTracing()
            }
            Button("Keep allowing", role: .cancel) { app.traceManager.dismissStillTracing() }
        } message: {
            Text("Do you want to stop them?")
        }
    }

    private var closeAccountSheet: some View {
        CloseAccountSheet(safety: app.safetyManager, owner: app.ownerAuth, email: app.authManager, theme: app.currentTheme) { closingAccount = false }
    }
}

private struct TabBar: View {
    @EnvironmentObject var app: AppModel

    private var bottomLeeway: CGFloat { TabBarMetrics.leeway }

    let selected: AppScreen
    let navigating: Bool
    @ObservedObject var friends: FriendsManager
    @ObservedObject var trace: TraceManager
    /// Changes with the theme so the bar is rebuilt in the new colours.
    let themeID: ThemeID
    @Namespace private var bubble

    /// Something on the You tab needs an answer: a friend request held for a decision, or a request to trace you.
    private var waiting: Bool {
        (friends.requestPolicy == .requestsOnly && !friends.incomingRequests.isEmpty) || !trace.incoming.isEmpty
    }

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
                            // A friend request is waiting (only when they are held for a decision), or someone has asked to trace you: a dot on YOU.
                            if s == .profile, waiting {
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
                .accessibilityLabel(s.label.capitalized + (s == .compass && navigating ? ", navigating" : "") + (s == .profile && waiting ? ", something is waiting for your answer" : ""))
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

/// Phones with a Home button (iPhone SE) have no bottom safe-area inset, so the bar's selected bubble was cut off by the screen's
/// edge and crowded the content above it. The bar is lifted by this much there, and screens that sit above it reserve the same.
/// Face ID phones already clear the home indicator and get none.
enum TabBarMetrics {
    static var leeway: CGFloat {
        let inset = UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.keyWindow?.safeAreaInsets.bottom }.first
        return inset == 0 ? 22 : 0      // unknown (no window yet) counts as none
    }
}
