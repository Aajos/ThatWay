//
//  SafetySheets.swift
//  ThatWay
//
//  Everything a person can do to protect themselves from another person, or from the app, in plain words:
//    FriendSafetySheet   block, report, and the emergency control (which only opens the phone's dialler)
//    ReportSheet         what happened, in the person's words; stored for a person to read; never carries a location
//    BlockedPeopleSection  who is blocked, with a way back
//    CloseAccountSheet   delete everything, or deactivate and keep the plan: two different things, never merged
//    ReactivationScreen  what a returning deactivated account must choose before anything else
//
//  None of these ask the owner check except deleting an account (destroying an account is not a safety action for anyone
//  else, and it must be the owner who does it).
//

import SwiftUI
import ThatWayCore
import ThatWayUI

// MARK: - Emergency

/// Opens the phone's dialler with the local emergency number in it. It does NOT call: the person presses call. ThatWay is not
/// an emergency service and says so right here.
struct EmergencyButton: View {
    let theme: AppTheme
    private var number: String { EmergencyNumber.forRegion(Locale.current.region?.identifier) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                if let url = URL(string: "tel://\(number)") { UIApplication.shared.open(url) }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "phone.fill")
                    Text("Open the dialler: \(number)").font(.nunito(14, .black))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity).frame(height: 50)
                .background(RoundedRectangle(cornerRadius: 16).fill(Color(hex: "D6362F")))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open the phone dialler with \(number)")
            Text(TraceCopy.emergencyDisclosure).font(.nunito(11, .semibold)).foregroundStyle(theme.textSecondary)
        }
    }
}

// MARK: - A friend: block, report

struct FriendSafetySheet: View {
    @ObservedObject var safety: SafetyManager
    let friend: Friend
    let theme: AppTheme
    let close: () -> Void
    @State private var confirmingBlock = false
    @State private var reporting = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text(friend.username).font(.nunito(24, .black)).foregroundStyle(theme.ink)

                VStack(alignment: .leading, spacing: 8) {
                    Text("IF YOU ARE IN DANGER").font(.nunito(10, .extraBold)).tracking(1.8).foregroundStyle(theme.ink.opacity(0.68))
                    EmergencyButton(theme: theme)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("BLOCK").font(.nunito(10, .extraBold)).tracking(1.8).foregroundStyle(theme.ink.opacity(0.68))
                    Text(TraceCopy.blockExplanation(name: friend.username)).font(.nunito(13, .semibold)).foregroundStyle(theme.ink)
                    Button { confirmingBlock = true } label: {
                        Text("Block \(friend.username)").font(.nunito(14, .black)).foregroundStyle(theme.needleRed)
                            .frame(maxWidth: .infinity).frame(height: 48)
                            .background(RoundedRectangle(cornerRadius: 16).fill(theme.needleRed.opacity(0.12)))
                    }
                    .buttonStyle(.plain)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("REPORT").font(.nunito(10, .extraBold)).tracking(1.8).foregroundStyle(theme.ink.opacity(0.68))
                    Text(TraceCopy.reportDisclosure).font(.nunito(13, .semibold)).foregroundStyle(theme.ink)
                    Button { reporting = true } label: {
                        Text("Report \(friend.username)…").font(.nunito(14, .extraBold)).foregroundStyle(theme.ink)
                            .frame(maxWidth: .infinity).frame(height: 48)
                            .background(RoundedRectangle(cornerRadius: 16).fill(theme.ink.opacity(0.08)))
                    }
                    .buttonStyle(.plain)
                }

                if let error = safety.errorMessage { Text(error).font(.nunito(13, .extraBold)).foregroundStyle(theme.needleRed) }
                Button("Close", action: close).font(.nunito(14, .extraBold)).foregroundStyle(theme.textSecondary).frame(maxWidth: .infinity)
            }
            .padding(24)
        }
        .background(theme.screen.ignoresSafeArea())
        .presentationDetents([.large])
        .confirmationDialog("Block \(friend.username)?", isPresented: $confirmingBlock, titleVisibility: .visible) {
            Button("Block \(friend.username)", role: .destructive) { Task { if await safety.block(friend) { close() } } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(TraceCopy.blockExplanation(name: friend.username))
        }
        .sheet(isPresented: $reporting) {
            ReportSheet(safety: safety, friend: friend, theme: theme) { reporting = false; if safety.errorMessage == nil { close() } }
        }
    }
}

struct ReportSheet: View {
    @ObservedObject var safety: SafetyManager
    let friend: Friend
    let theme: AppTheme
    let done: () -> Void
    @State private var category: ReportCategory?
    @State private var details = ""
    @State private var alsoBlock = false
    @State private var sending = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Report \(friend.username)").font(.nunito(24, .black)).foregroundStyle(theme.ink)
                Text("What happened?").font(.nunito(14, .extraBold)).foregroundStyle(theme.ink)
                VStack(spacing: 8) {
                    ForEach(ReportCategory.allCases) { option in
                        Button { category = option } label: {
                            HStack(spacing: 10) {
                                Image(systemName: category == option ? "largecircle.fill.circle" : "circle")
                                    .foregroundStyle(category == option ? theme.accent : theme.ink.opacity(0.4))
                                Text(option.title).font(.nunito(13, .semibold)).foregroundStyle(theme.ink).multilineTextAlignment(.leading)
                                Spacer(minLength: 0)
                            }
                            .padding(12)
                            .background(RoundedRectangle(cornerRadius: 14).fill(theme.ink.opacity(category == option ? 0.1 : 0.05)))
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(category == option ? .isSelected : [])
                    }
                }
                if category?.isUrgent == true {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("If you are in danger right now, call for help first.").font(.nunito(13, .extraBold)).foregroundStyle(theme.needleRed)
                        EmergencyButton(theme: theme)
                    }
                }
                TextField("Anything else we should know? (optional)", text: $details, axis: .vertical)
                    .lineLimit(3...6)
                    .font(.nunito(14, .semibold))
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 14).fill(theme.ink.opacity(0.06)))
                    .onChange(of: details) { _, new in if new.count > 500 { details = String(new.prefix(500)) } }
                Text("\(details.count)/500 · Don’t include passwords or anyone’s exact location.").font(.nunito(11, .semibold)).foregroundStyle(theme.textSecondary)
                Toggle(isOn: $alsoBlock) {
                    Text("Also block \(friend.username)").font(.nunito(14, .extraBold)).foregroundStyle(theme.ink)
                }
                .tint(theme.accent)
                Text(TraceCopy.reportDisclosure).font(.nunito(12, .semibold)).foregroundStyle(theme.textSecondary)
                if let error = safety.errorMessage { Text(error).font(.nunito(13, .extraBold)).foregroundStyle(theme.needleRed) }
                Button {
                    guard let category else { return }
                    sending = true
                    Task { _ = await safety.report(friend, category: category, details: details, alsoBlock: alsoBlock); sending = false; done() }
                } label: {
                    Text(sending ? "Sending…" : "Send report").font(.nunito(15, .black)).foregroundStyle(theme.onAccent)
                        .frame(maxWidth: .infinity).frame(height: 52)
                        .background(RoundedRectangle(cornerRadius: 16).fill(theme.accent))
                        .opacity(category == nil || sending ? 0.4 : 1)
                }
                .buttonStyle(.plain)
                .disabled(category == nil || sending)
                Button("Cancel", action: done).font(.nunito(14, .extraBold)).foregroundStyle(theme.textSecondary).frame(maxWidth: .infinity)
            }
            .padding(24)
        }
        .background(theme.screen.ignoresSafeArea())
        .presentationDetents([.large])
    }
}

// MARK: - Who I have blocked

struct BlockedPeopleSection: View {
    @ObservedObject var safety: SafetyManager
    let theme: AppTheme

    var body: some View {
        if !safety.blocked.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("BLOCKED PEOPLE").font(.nunito(10, .extraBold)).tracking(1.8).foregroundStyle(theme.ink.opacity(0.68))
                VStack(spacing: 0) {
                    ForEach(safety.blocked) { user in
                        HStack {
                            Text(user.displayName).font(.nunito(14, .semibold)).foregroundStyle(theme.ink)
                            Spacer()
                            Button { Task { await safety.unblock(user) } } label: {
                                Text("UNBLOCK").font(.nunito(11, .black)).tracking(0.6).foregroundStyle(theme.accent)
                                    .padding(.horizontal, 12).padding(.vertical, 7).background(Capsule().fill(theme.tint(0.14)))
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 14).padding(.vertical, 9)
                    }
                }
                .background(RoundedRectangle(cornerRadius: 16).fill(theme.ink.opacity(0.05)))
                if let notice = safety.notice { Text(notice).font(.nunito(12, .semibold)).foregroundStyle(theme.textSecondary) }
            }
        }
    }
}

// MARK: - Closing the account

struct CloseAccountSheet: View {
    @ObservedObject var safety: SafetyManager
    @ObservedObject var owner: OwnerAuthCoordinator
    let email: EmailVerifying
    let theme: AppTheme
    let close: () -> Void

    private enum Choice { case delete, deactivate }
    @State private var choice: Choice?
    @State private var typed = ""
    @State private var verified = false
    @State private var verifying = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Close your account").font(.nunito(24, .black)).foregroundStyle(theme.ink)
                Text("There are two different ways, and they are not the same. Read both.").font(.nunito(14, .semibold)).foregroundStyle(theme.ink)

                option(.deactivate, title: "Deactivate and keep my plan", body: TraceCopy.deactivateWarning, tint: theme.accent)
                option(.delete, title: "Delete everything", body: TraceCopy.deleteWarning, tint: theme.needleRed)

                if choice == .delete {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("To delete everything, type DELETE.").font(.nunito(13, .extraBold)).foregroundStyle(theme.ink)
                        TextField("DELETE", text: $typed)
                            .textInputAutocapitalization(.characters).autocorrectionDisabled()
                            .font(.nunito(16, .extraBold)).padding(12)
                            .background(RoundedRectangle(cornerRadius: 12).fill(theme.ink.opacity(0.06)))
                    }
                }
                if let error = safety.errorMessage { Text(error).font(.nunito(13, .extraBold)).foregroundStyle(theme.needleRed) }

                if let choice {
                    Button { Task { await confirm(choice) } } label: {
                        Text(label(choice)).font(.nunito(15, .black)).foregroundStyle(.white)
                            .frame(maxWidth: .infinity).frame(height: 52)
                            .background(RoundedRectangle(cornerRadius: 16).fill(choice == .delete ? theme.needleRed : theme.accent))
                            .opacity(canConfirm(choice) ? 1 : 0.4)
                    }
                    .buttonStyle(.plain)
                    .disabled(!canConfirm(choice) || safety.isWorking || verifying)
                }
                Button("Keep my account", action: close).font(.nunito(14, .extraBold)).foregroundStyle(theme.textSecondary).frame(maxWidth: .infinity)
            }
            .padding(24)
        }
        .background(theme.screen.ignoresSafeArea())
        .presentationDetents([.large])
        .sheet(item: Binding(get: { owner.prompt }, set: { _ in })) { prompt in
            OwnerPromptSheet(owner: owner, prompt: prompt, email: email, theme: theme)
        }
    }

    private func option(_ value: Choice, title: String, body: String, tint: Color) -> some View {
        Button { choice = value; typed = "" } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: choice == value ? "largecircle.fill.circle" : "circle").foregroundStyle(choice == value ? tint : theme.ink.opacity(0.4))
                    Text(title).font(.nunito(16, .black)).foregroundStyle(value == .delete ? theme.needleRed : theme.ink)
                }
                Text(body).font(.nunito(12, .semibold)).foregroundStyle(theme.ink).multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
            }
            .padding(14).frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 16).fill(theme.ink.opacity(choice == value ? 0.09 : 0.04)))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(choice == value ? tint.opacity(0.7) : .clear, lineWidth: 1.5))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(choice == value ? .isSelected : [])
    }

    private func label(_ choice: Choice) -> String {
        if safety.isWorking || verifying { return "Working…" }
        return choice == .delete ? "Delete everything, for good" : "Deactivate my account"
    }

    private func canConfirm(_ choice: Choice) -> Bool { choice == .deactivate || typed == "DELETE" }

    private func confirm(_ choice: Choice) async {
        verifying = true
        let result = await owner.authenticate(reason: choice == .delete ? "Delete your ThatWay account" : "Deactivate your ThatWay account")
        verifying = false
        guard result == .success else { return }
        if choice == .delete { await safety.deleteAccount() } else { await safety.deactivateAccount() }
    }
}

// MARK: - Coming back to a deactivated account

struct ReactivationScreen: View {
    @ObservedObject var safety: SafetyManager
    let theme: AppTheme
    let deleteInstead: () -> Void
    let signOut: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            Spacer()
            Image(systemName: "person.crop.circle.badge.checkmark").font(.system(size: 44)).foregroundStyle(theme.accent).accessibilityHidden(true)
            Text("Welcome back").font(.nunito(26, .black)).foregroundStyle(theme.ink)
            VStack(spacing: 8) {
                Text("Your account is deactivated. Your plan is kept, and you are hidden from search.").multilineTextAlignment(.center)
                if let deletes = safety.account?.deletesAt {
                    Text("If you don’t reactivate, it is deleted completely on \(Date(timeIntervalSince1970: deletes).formatted(date: .abbreviated, time: .omitted)).").multilineTextAlignment(.center)
                }
                Text("Your friends were removed when you deactivated and are not restored.").multilineTextAlignment(.center)
            }
            .font(.nunito(14, .semibold)).foregroundStyle(theme.ink)
            if let error = safety.errorMessage { Text(error).font(.nunito(13, .extraBold)).foregroundStyle(theme.needleRed) }
            Button { Task { await safety.reactivate() } } label: {
                Text(safety.isWorking ? "Working…" : "Reactivate my account").font(.nunito(15, .black)).foregroundStyle(theme.onAccent)
                    .frame(maxWidth: .infinity).frame(height: 52).background(RoundedRectangle(cornerRadius: 16).fill(theme.accent))
            }
            .buttonStyle(.plain)
            .disabled(safety.isWorking)
            Button("Delete everything instead", action: deleteInstead).font(.nunito(14, .extraBold)).foregroundStyle(theme.needleRed)
            Button("Sign out", action: signOut).font(.nunito(14, .extraBold)).foregroundStyle(theme.textSecondary)
            Spacer()
        }
        .padding(.horizontal, 28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme.screen.ignoresSafeArea())
    }
}
