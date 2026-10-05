//
//  ProfileScreen.swift
//  ThatWay
//

import SwiftUI

struct ProfileScreen: View {
    @EnvironmentObject var app: AppModel
    @EnvironmentObject var friendsManager: FriendsManager
    @State private var friendQuery = ""
    @FocusState private var friendFieldFocused: Bool

    var body: some View {
        let theme = app.currentTheme

        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header(theme: theme)
                if Config.backendEnabled {
                    addFriendSection(theme: theme)
                    friendRequestsSection(theme: theme)
                } else {
                    backendDisabledNotice(theme: theme)
                }
                visibilitySection(theme: theme)
                defaultNavModeSection(theme: theme)
                achievementsSection(theme: theme)
                settingsSection(theme: theme)
                if Config.backendEnabled {
                    signOutSection(theme: theme)
                }
                donateBanner(theme: theme)
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 100)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(.top, 8)
        .background(theme.screen)
    }

    /// Which mode a newly-picked destination drops straight into.
    @ViewBuilder
    private func defaultNavModeSection(theme: AppTheme) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("DEFAULT MODE").font(.nunito(10, .extraBold)).tracking(1.8).foregroundStyle(theme.ink.opacity(0.68))
            HStack(spacing: 10) {
                navModeCard(.point, title: "Point", icon: "location.north.line", detail: "Power-efficient", theme: theme)
                navModeCard(.guidance, title: "Guidance", icon: "arrow.triangle.turn.up.right.diamond.fill", detail: "Live turns", theme: theme)
            }
        }
    }

    @ViewBuilder
    private func navModeCard(_ mode: NavMode, title: String, icon: String, detail: String, theme: AppTheme) -> some View {
        let selected = app.defaultNavMode == mode
        Button { app.defaultNavMode = mode } label: {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(selected ? theme.accent : theme.ink.opacity(0.5))
                    .frame(width: 40, height: 40)
                    .background(RoundedRectangle(cornerRadius: 12).fill(selected ? theme.accent.opacity(0.16) : theme.ink.opacity(0.06)))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.nunito(15, .extraBold)).foregroundStyle(theme.ink)
                    Text(detail).font(.nunito(11, .semibold)).foregroundStyle(theme.ink.opacity(0.62)).lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 16).fill(selected ? theme.accent.opacity(0.14) : theme.ink.opacity(0.05)))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(selected ? theme.accent.opacity(0.5) : theme.ink.opacity(0.09), lineWidth: selected ? 1.5 : 1))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func backendDisabledNotice(theme: AppTheme) -> some View {
        Text("Accounts & friends are temporarily off while the backend is being set up.")
            .font(.nunito(12, .semibold))
            .foregroundStyle(theme.textSecondary)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 14).fill(theme.ink.opacity(0.05)))
    }

    @ViewBuilder
    private func addFriendSection(theme: AppTheme) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("ADD A FRIEND").font(.nunito(10, .extraBold)).tracking(1.8).foregroundStyle(theme.ink.opacity(0.68))
            HStack(spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").font(.system(size: 14, weight: .semibold)).foregroundStyle(theme.ink.opacity(0.5))
                    TextField("Username", text: $friendQuery)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($friendFieldFocused)
                        .font(.nunito(15, .semibold))
                        .onSubmit(runSearch)
                }
                .padding(.horizontal, 14).frame(height: 46)
                .background(RoundedRectangle(cornerRadius: 14).fill(theme.ink.opacity(0.05)))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(theme.ink.opacity(0.1)))

                Button(action: runSearch) {
                    Text("SEARCH")
                        .font(.nunito(12, .black)).tracking(0.6)
                        .foregroundStyle(theme.onAccent)
                        .padding(.horizontal, 16).frame(height: 46)
                        .background(RoundedRectangle(cornerRadius: 14).fill(theme.accent))
                        .opacity(friendQuery.trimmingCharacters(in: .whitespaces).isEmpty ? 0.5 : 1)
                }
                .buttonStyle(.plain)
                .disabled(friendQuery.trimmingCharacters(in: .whitespaces).isEmpty)
            }

            ForEach(friendsManager.searchResults) { result in
                HStack {
                    Text(result.username).font(.nunito(14, .semibold))
                    Spacer()
                    Button {
                        Task {
                            if await friendsManager.sendRequest(to: result.id) {
                                friendsManager.searchResults.removeAll { $0.id == result.id }
                                friendQuery = ""
                                friendFieldFocused = false
                            }
                        }
                    } label: {
                        Text("ADD").font(.nunito(11, .black)).tracking(0.6)
                            .foregroundStyle(theme.onAccent)
                            .padding(.horizontal, 14).padding(.vertical, 7)
                            .background(Capsule().fill(theme.accent))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 14).padding(.vertical, 4)
            }

            if let error = friendsManager.errorMessage {
                Text(error).font(.nunito(12, .semibold)).foregroundStyle(theme.needleRed)
            }
        }
    }

    private func runSearch() {
        let query = friendQuery.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return }
        Task { await friendsManager.searchUsers(query: query) }
    }

    @ViewBuilder
    private func friendRequestsSection(theme: AppTheme) -> some View {
        if !friendsManager.incomingRequests.isEmpty || !friendsManager.outgoingRequests.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("FRIEND REQUESTS").font(.nunito(10, .extraBold)).tracking(1.8).foregroundStyle(theme.ink.opacity(0.68))
                VStack(spacing: 8) {
                    ForEach(friendsManager.incomingRequests) { req in
                        HStack {
                            Text(req.username).font(.nunito(14, .semibold))
                            Spacer()
                            Button { Task { await friendsManager.respond(to: req.id, accept: false) } } label: {
                                Image(systemName: "xmark").font(.system(size: 12, weight: .bold)).foregroundStyle(theme.ink.opacity(0.6))
                                    .frame(width: 32, height: 32)
                                    .background(Circle().fill(theme.ink.opacity(0.08)))
                            }.buttonStyle(.plain)
                            Button { Task { await friendsManager.respond(to: req.id, accept: true) } } label: {
                                Image(systemName: "checkmark").font(.system(size: 12, weight: .bold)).foregroundStyle(theme.onAccent)
                                    .frame(width: 32, height: 32)
                                    .background(Circle().fill(theme.accent))
                            }.buttonStyle(.plain)
                        }
                    }
                    ForEach(friendsManager.outgoingRequests) { req in
                        HStack {
                            Text(req.username).font(.nunito(14, .semibold))
                            Spacer()
                            Text("Pending").font(.nunito(11, .semibold)).foregroundStyle(theme.textSecondary)
                        }
                    }
                }
                .padding(14)
                .background(RoundedRectangle(cornerRadius: 16).fill(theme.ink.opacity(0.05)))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(theme.ink.opacity(0.09)))
            }
        }
    }

    @ViewBuilder
    private func signOutSection(theme: AppTheme) -> some View {
        Button {
            app.authManager.signOut()
        } label: {
            Text("SIGN OUT")
                .font(.nunito(12, .black)).tracking(0.6)
                .foregroundStyle(theme.needleRed)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(RoundedRectangle(cornerRadius: 16).fill(theme.needleRed.opacity(0.1)))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(theme.needleRed.opacity(0.3)))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func header(theme: AppTheme) -> some View {
        HStack(spacing: 14) {
            Button { app.avatarSheet = true } label: {
                ZStack(alignment: .bottomTrailing) {
                    Circle()
                        .fill(app.currentAvatar.bg)
                        .frame(width: 64, height: 64)
                        .overlay(Text(app.currentAvatar.glyph).font(.nunito(22, .black)).foregroundStyle(Color(hex: "241A14")))
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 22, weight: .black))
                        .foregroundStyle(theme.onAccent, theme.accent)
                        .background(Circle().fill(theme.screen).padding(2))
                }
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 4) {
                Text(app.authManager.currentUser?.username ?? "You").font(.nunito(20, .black))
                Text(visLine).font(.nunito(13, .semibold)).foregroundStyle(theme.ink.opacity(0.68))
                Button { app.avatarSheet = true } label: {
                    Text("EDIT PICTURE & AVATARS")
                        .font(.nunito(11, .extraBold)).tracking(0.6)
                        .foregroundStyle(theme.accent)
                }
                .padding(.top, 4)
            }
        }
    }

    private var visLine: String {
        switch app.vis {
        case .nobody: return "Invisible on the map"
        case .close: return "Visible to close ones within \(Int(app.closeKm)) km"
        case .friends: return "Visible to friends"
        }
    }

    @ViewBuilder
    private func visibilitySection(theme: AppTheme) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("VISIBLE TO").font(.nunito(10, .extraBold)).tracking(1.8).foregroundStyle(theme.ink.opacity(0.68))
            HStack(spacing: 6) {
                ForEach(Visibility.allCases) { v in
                    Button { app.vis = v } label: {
                        Text(v.rawValue)
                            .font(.nunito(13, .extraBold))
                            .foregroundStyle(theme.ink)
                            .opacity(app.vis == v ? 1 : 0.45)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 9)
                            .background(RoundedRectangle(cornerRadius: 12).fill(app.vis == v ? theme.accent.opacity(0.22) : .clear))
                    }
                }
            }
            .padding(4)
            .background(RoundedRectangle(cornerRadius: 16).fill(theme.ink.opacity(0.05)))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(theme.ink.opacity(0.09)))

            if app.vis == .close {
                VStack(spacing: 12) {
                    HStack {
                        Text("Close ones within").font(.nunito(12, .semibold)).foregroundStyle(theme.ink.opacity(0.7))
                        Spacer()
                        Text("\(Int(app.closeKm)) km").font(.nunito(15, .black)).foregroundStyle(theme.accent)
                    }
                    Slider(value: $app.closeKm, in: 2...20, step: 1).tint(theme.accent)
                    HStack {
                        Text("2 km").font(.nunito(10, .semibold)).foregroundStyle(theme.ink.opacity(0.6))
                        Spacer()
                        Text("20 km").font(.nunito(10, .semibold)).foregroundStyle(theme.ink.opacity(0.6))
                    }
                }
                .padding(14)
                .background(RoundedRectangle(cornerRadius: 18).fill(theme.ink.opacity(0.05)))
                .overlay(RoundedRectangle(cornerRadius: 18).stroke(theme.ink.opacity(0.09)))
            }
        }
    }

    @ViewBuilder
    private func achievementsSection(theme: AppTheme) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("ACHIEVEMENTS").font(.nunito(10, .extraBold)).tracking(1.8).foregroundStyle(theme.ink.opacity(0.68))
            HStack(spacing: 10) {
                badge("✦", "First 10 km", 1, theme: theme)
                badge("◔", "Dawn run", 1, theme: theme)
                badge("◇", "No wrong turns", 0.4, theme: theme)
            }
        }
    }

    @ViewBuilder
    private func badge(_ glyph: String, _ name: String, _ op: Double, theme: AppTheme) -> some View {
        VStack(spacing: 8) {
            Circle()
                .strokeBorder(theme.accent, lineWidth: 2)
                .frame(width: 34, height: 34)
                .overlay(Text(glyph).font(.nunito(14, .extraBold)).foregroundStyle(theme.accent))
            Text(name).font(.nunito(10, .semibold)).foregroundStyle(theme.ink.opacity(0.78)).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14).padding(.horizontal, 10)
        .background(RoundedRectangle(cornerRadius: 18).fill(theme.ink.opacity(0.05)))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(theme.ink.opacity(0.09)))
        .opacity(op)
    }

    @ViewBuilder
    private func settingsSection(theme: AppTheme) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "gear").font(.system(size: 11, weight: .heavy))
                Text("SETTINGS").font(.nunito(10, .extraBold)).tracking(1.8)
            }
            .foregroundStyle(theme.ink.opacity(0.68))
            VStack(spacing: 0) {
                SettingsRow("Compass skin", value: app.currentSkin.name,
                            options: Skin.all.filter { app.ownedSkins.contains($0.id) }.map(\.name), theme: theme) { v in
                    if let id = Skin.all.first(where: { $0.name == v })?.id { app.skin = id }
                }
                SettingsRow("Theme", value: theme.name, options: AppTheme.all.map(\.name), theme: theme) { v in
                    if let id = AppTheme.all.first(where: { $0.name == v })?.id { app.setTheme(id) }
                }
                SettingsRow("Compass tilt", value: app.opts.tilt, options: ["Off", "Slight", "Hard"], theme: theme) { app.opts.tilt = $0 }
                SettingsRow("Audio guidance", value: app.audioStyle.displayName, options: AudioGuidanceStyle.allCases.map(\.displayName), theme: theme) { v in
                    app.audioStyle = AudioGuidanceStyle.allCases.first { $0.displayName == v } ?? .tone
                }
                SettingsRow("Voice of directions", value: app.opts.voice, options: ["Friendly", "Terse", "Cheeky"], theme: theme) { app.opts.voice = $0 }
                SettingsRow("Haptics on turns", value: app.opts.haptics, options: ["Off", "Light", "Strong"], theme: theme) { app.opts.haptics = $0 }
                SettingsRow("Share destination", value: app.opts.share, options: ["Off", "Friends only", "Everyone"], theme: theme) { app.opts.share = $0 }
                SettingsRow("Units", value: app.opts.units, options: ["Kilometres", "Miles"], theme: theme, isLast: true) { app.opts.units = $0 }
            }
            .background(RoundedRectangle(cornerRadius: 20).fill(theme.ink.opacity(0.05)))
            .overlay(RoundedRectangle(cornerRadius: 20).stroke(theme.ink.opacity(0.09)))
        }
    }

    @ViewBuilder
    private func donateBanner(theme: AppTheme) -> some View {
        Button { app.goDonate() } label: {
            VStack(alignment: .leading, spacing: 6) {
                Text("Free forever, no ads").font(.nunito(15, .extraBold)).foregroundStyle(theme.accent)
                Text("If the compass made your commute better, consider leaving a review in the app store or donating some spare change to help us run the servers :)")
                    .font(.nunito(13, .semibold)).foregroundStyle(theme.ink.opacity(0.76))
                Text("LEAVE A TIP")
                    .font(.nunito(12, .black)).tracking(0.6)
                    .foregroundStyle(theme.onAccent)
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    .background(RoundedRectangle(cornerRadius: 13).fill(theme.accent))
                    .padding(.top, 8)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(18)
            .background(RoundedRectangle(cornerRadius: 20).fill(theme.accent.opacity(0.12)))
            .overlay(RoundedRectangle(cornerRadius: 20).stroke(theme.accent.opacity(0.32)))
        }
        .buttonStyle(.plain)
    }
}

/// A settings row with a native `Menu` dropdown. `Menu` items render through UIKit's own
/// menu chrome rather than anything SwiftUI draws directly, so they ignore custom fonts —
/// but that chrome uses `UIFont.preferredFont(forTextStyle:)` internally, which means it
/// already tracks the system's real Dynamic Type accessibility setting on its own, with
/// no extra plumbing needed here.
private struct SettingsRow: View {
    let label: String
    let value: String
    let options: [String]
    let theme: AppTheme
    var isLast: Bool = false
    let onChange: (String) -> Void

    init(_ label: String, value: String, options: [String], theme: AppTheme, isLast: Bool = false, onChange: @escaping (String) -> Void) {
        self.label = label
        self.value = value
        self.options = options
        self.theme = theme
        self.isLast = isLast
        self.onChange = onChange
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(label).font(.nunito(15, .semibold)).foregroundStyle(theme.ink)
                Spacer()
                Menu {
                    ForEach(options, id: \.self) { opt in
                        Button(opt) { onChange(opt) }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Text(value).font(.nunito(13, .bold)).foregroundStyle(theme.ink)
                        Image(systemName: "chevron.down").font(.system(size: 9, weight: .bold)).foregroundStyle(theme.ink.opacity(0.5))
                    }
                    .padding(.horizontal, 12).padding(.vertical, 9)
                    .background(RoundedRectangle(cornerRadius: 11).fill(theme.ink.opacity(0.08)))
                    .overlay(RoundedRectangle(cornerRadius: 11).stroke(theme.ink.opacity(0.12)))
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 13)
            if !isLast {
                Divider().background(theme.ink.opacity(0.07)).padding(.leading, 16)
            }
        }
    }
}
