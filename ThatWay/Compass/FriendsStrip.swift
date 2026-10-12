//
//  FriendsStrip.swift
//  ThatWay
//
//  The friends bar on the compass screen. Friends sit in a row; swipe left and a round search icon is revealed at the end.
//  Tap it and the bar opens into a search field that searches *your friends* as you type. If nothing among them matches and
//  you stop typing for three quarters of a second, the app looks up that exact username and offers "+ Add", so a request can
//  be sent from here too. Tapping a friend asks to trace them (the caller confirms; nothing is shared until they accept).
//

import SwiftUI
import ThatWayCore
import ThatWayUI

struct FriendsStrip: View {
    @ObservedObject var friendsManager: FriendsManager
    let theme: AppTheme
    let k: CGFloat
    let myId: String?
    let onTrace: (Friend) -> Void

    @State private var searching = false
    @State private var query = ""
    @State private var settledFor: String?          // the query the server last answered
    @State private var lookingUp = false
    @State private var requested = Set<String>()    // ids asked this session (until the lists refresh)
    @State private var viewWidth: CGFloat = 0
    @FocusState private var focused: Bool

    /// How long the person has to stop typing, with no friend matching, before the server is asked.
    static let idleBeforeLookup: Duration = .milliseconds(750)

    private var trimmed: String { query.trimmingCharacters(in: .whitespaces) }
    private var matches: [Friend] {
        trimmed.isEmpty ? friendsManager.friends : friendsManager.friends.filter { $0.username.localizedCaseInsensitiveContains(trimmed) }
    }

    var body: some View {
        Group {
            if searching { searchPanel } else { row }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: searching)
    }

    // MARK: The row

    private var row: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 12) {
                if friendsManager.friends.isEmpty {
                    Text("No friends yet. Tap the magnifier to find someone")
                        .font(.nunito(12, .semibold))
                        .foregroundStyle(theme.textSecondary)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: 220, alignment: .leading)
                }
                ForEach(friendsManager.friends) { f in
                    VStack(spacing: 6) {
                        avatar(f, size: 52)
                        Text(f.username)
                            .font(.nunito(11, .semibold))
                            .foregroundStyle(theme.textSecondary)
                            .lineLimit(1)
                    }
                    .frame(width: 56)
                    .contentShape(Rectangle())
                    .onTapGesture { onTrace(f) }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Trace \(f.username)")
                    .accessibilityAddTraits(.isButton)
                }
                searchBubble
            }
            .padding(.horizontal, 16 * k)
            // With friends in the row the bubble sits just past the right edge: swipe left to reveal it.
            .frame(minWidth: friendsManager.friends.isEmpty ? 0 : viewWidth + 44, alignment: .leading)
        }
        .scrollClipDisabled()
        .background(GeometryReader { g in
            Color.clear
                .onAppear { viewWidth = g.size.width }
                .onChange(of: g.size.width) { _, w in viewWidth = w }
        })
    }

    private var searchBubble: some View {
        Button {
            searching = true
            focused = true
        } label: {
            ZStack {
                Circle().fill(theme.surface(0.1)).frame(width: 52, height: 52)
                Circle().stroke(theme.accent.opacity(0.7), lineWidth: 1.5).frame(width: 52, height: 52)
                Image(systemName: "magnifyingglass").font(.system(size: 18, weight: .bold)).foregroundStyle(theme.accent)
            }
            .frame(width: 56)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Search friends or add someone by username")
    }

    // MARK: The search panel

    private var searchPanel: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").foregroundStyle(theme.textSecondary)
                    TextField("Search friends or add by username", text: $query)
                        .font(.nunito(14, .semibold))
                        .foregroundStyle(theme.ink)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.search)
                        .focused($focused)
                    if !query.isEmpty {
                        Button { query = "" } label: {
                            Image(systemName: "xmark.circle.fill").foregroundStyle(theme.textSecondary.opacity(0.6))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Clear")
                    }
                }
                .padding(.horizontal, 14).frame(height: 46)
                .background(Capsule().fill(theme.surface(0.07)))
                .overlay(Capsule().stroke(theme.accent.opacity(0.6)))

                Button { close() } label: {
                    Image(systemName: "xmark.circle.fill").font(.system(size: 26)).foregroundStyle(theme.textSecondary.opacity(0.75))
                        .frame(minWidth: 44, minHeight: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close search")
            }

            results
        }
        .padding(.horizontal, 16 * k)
        .task(id: query) { await lookUpIfNeeded() }
        .onAppear { focused = true }
    }

    @ViewBuilder
    private var results: some View {
        let list = matches
        VStack(spacing: 6) {
            ForEach(list.prefix(5)) { f in
                resultRow(avatar: avatar(f, size: 34), name: f.username) {
                    pillButton("Trace", filled: false) { close(); onTrace(f) }
                }
            }
            if list.count > 5 {
                Text("\(list.count - 5) more: keep typing to narrow it down")
                    .font(.nunito(11, .semibold)).foregroundStyle(theme.textSecondary)
            }
            if !trimmed.isEmpty, list.isEmpty { unknown }
        }
    }

    /// Nobody among your friends matches and typing has paused: the exact-username lookup and its "+ Add".
    @ViewBuilder
    private var unknown: some View {
        if lookingUp {
            HStack(spacing: 8) { ProgressView().tint(theme.accent); Text("Looking for “\(trimmed)”…").font(.nunito(12, .semibold)).foregroundStyle(theme.textSecondary) }
                .padding(.vertical, 6)
        } else if settledFor == trimmed {
            let found = friendsManager.searchResults.filter { $0.id != myId }
            if friendsManager.errorMessage != nil && found.isEmpty {
                Text("Couldn't look that up. Check your connection.").font(.nunito(12, .semibold)).foregroundStyle(theme.needleRed)
            } else if found.isEmpty {
                Text("No one is called “\(trimmed)”. Usernames have to match exactly.")
                    .font(.nunito(12, .semibold)).foregroundStyle(theme.textSecondary).multilineTextAlignment(.center)
            } else {
                ForEach(found) { user in
                    resultRow(avatar: initialsAvatar(user.username), name: user.username) { addControl(for: user) }
                }
            }
        }
    }

    @ViewBuilder
    private func addControl(for user: UserSearchResult) -> some View {
        if requested.contains(user.id) || friendsManager.outgoingRequests.contains(where: { $0.id == user.id }) {
            Text("Requested").font(.nunito(12, .extraBold)).foregroundStyle(theme.textSecondary)
        } else if friendsManager.incomingRequests.contains(where: { $0.id == user.id }) {
            pillButton("Accept", filled: true) { Task { await friendsManager.respond(to: user.id, accept: true) } }
        } else {
            pillButton("+ Add", filled: true) {
                Task { if await friendsManager.sendRequest(to: user.id) { requested.insert(user.id) } }
            }
        }
    }

    // MARK: Pieces

    private func resultRow<Trailing: View>(avatar: some View, name: String, @ViewBuilder trailing: () -> Trailing) -> some View {
        HStack(spacing: 10) {
            avatar
            Text(name).font(.nunito(14, .extraBold)).foregroundStyle(theme.ink).lineLimit(1)
            Spacer(minLength: 8)
            trailing()
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 16).fill(theme.surface(0.07)))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(theme.borderColor))
    }

    private func pillButton(_ title: String, filled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.nunito(12, .black))
                .foregroundStyle(filled ? theme.onAccent : theme.ink)
                .padding(.horizontal, 14).padding(.vertical, 7)
                .background(Capsule().fill(filled ? theme.accent : theme.ink.opacity(0.1)))
        }
        .buttonStyle(.plain)
    }

    private func avatar(_ f: Friend, size: CGFloat) -> some View {
        ZStack {
            Circle().fill(LinearGradient(colors: [theme.accent, Color(hex: "34D6A5")], startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: size, height: size)
            Circle().fill(theme.screen).frame(width: size - 4, height: size - 4)
            Circle().fill(f.color).frame(width: size - 10, height: size - 10)
            Text(f.initials).font(.nunito(size * 0.29, .extraBold)).foregroundStyle(Color(hex: "241A14"))
        }
    }

    private func initialsAvatar(_ name: String) -> some View {
        ZStack {
            Circle().fill(theme.ink.opacity(0.12)).frame(width: 34, height: 34)
            Text(String(name.prefix(2)).uppercased()).font(.nunito(10, .extraBold)).foregroundStyle(theme.ink)
        }
    }

    private func close() {
        searching = false
        query = ""
        settledFor = nil
        focused = false
        friendsManager.searchResults = []
    }

    // MARK: The lookup

    /// Runs on every change of the query (and is cancelled by the next one, which is what makes it a debounce).
    private func lookUpIfNeeded() async {
        friendsManager.searchResults = []
        settledFor = nil
        lookingUp = false
        guard !trimmed.isEmpty, matches.isEmpty else { return }
        try? await Task.sleep(for: Self.idleBeforeLookup)
        guard !Task.isCancelled else { return }
        let asked = trimmed
        lookingUp = true
        await friendsManager.searchUsers(query: asked)
        guard !Task.isCancelled else { return }
        lookingUp = false
        settledFor = asked
    }
}
