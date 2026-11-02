//
//  OwnerPromptSheet.swift
//  ThatWay
//
//  The screens behind the owner check, for the one case the system cannot cover: a phone with no Face ID, Touch ID or passcode.
//    - enter the ThatWay passcode (six digits), or
//    - set one up: prove the account's email with a code first (so a stranger holding an unlocked, lock-less phone cannot
//      set a passcode of their own), then choose and confirm six digits.
//  The sheet cannot be swiped away by accident: it ends with an explicit Cancel, which allows nothing.
//

import SwiftUI
import ThatWayUI

struct OwnerPromptSheet: View {
    @ObservedObject var owner: OwnerAuthCoordinator
    let prompt: OwnerPrompt
    let email: EmailVerifying
    let theme: AppTheme
    @State private var resetting = false

    var body: some View {
        Group {
            switch prompt {
            case .enterPasscode(let reason):
                if resetting { setup(reason: "Verify your email to choose a new passcode.") } else { enter(reason: reason) }
            case .setUpPasscode(let reason):
                setup(reason: reason)
            }
        }
        .background(theme.screen.ignoresSafeArea())
        .interactiveDismissDisabled()
        .onDisappear { owner.resolve(.cancelled) }
    }

    private func enter(reason: String) -> some View {
        EnterPasscodeView(owner: owner, reason: reason, theme: theme, forgot: { resetting = true }, cancel: { owner.resolve(.cancelled) })
    }

    private func setup(reason: String) -> some View {
        PasscodeSetupFlow(owner: owner, email: email, reason: reason, theme: theme)
    }
}

// MARK: - Six digits

struct PinField: View {
    @Binding var pin: String
    let theme: AppTheme
    let label: String
    let onComplete: (String) -> Void
    @FocusState private var focused: Bool

    var body: some View {
        ZStack {
            HStack(spacing: 14) {
                ForEach(0..<PasscodeRules.length, id: \.self) { i in
                    Circle()
                        .fill(i < pin.count ? theme.accent : theme.ink.opacity(0.12))
                        .overlay(Circle().stroke(theme.ink.opacity(0.25), lineWidth: 1))
                        .frame(width: 18, height: 18)
                }
            }
            .accessibilityHidden(true)
            // The real field is invisible but covers the dots, so a tap anywhere on them raises the keyboard.
            TextField("", text: $pin)
                .keyboardType(.numberPad)
                .textContentType(.oneTimeCode)
                .focused($focused)
                .foregroundStyle(.clear).tint(.clear)
                .frame(maxWidth: .infinity).frame(height: 44)
                .contentShape(Rectangle())
                .accessibilityLabel(label)
                .accessibilityValue("\(pin.count) of \(PasscodeRules.length) digits")
                .onChange(of: pin) { _, new in
                    let digits = String(new.filter { $0.isASCII && $0.isNumber }.prefix(PasscodeRules.length))
                    if digits != new { pin = digits }
                    if digits.count == PasscodeRules.length { onComplete(digits) }
                }
        }
        .frame(height: 44)
        .onAppear { focused = true }
    }
}

private struct EnterPasscodeView: View {
    @ObservedObject var owner: OwnerAuthCoordinator
    let reason: String
    let theme: AppTheme
    let forgot: () -> Void
    let cancel: () -> Void
    @State private var pin = ""
    @State private var message: String?

    var body: some View {
        VStack(spacing: 18) {
            Spacer(minLength: 24)
            Image(systemName: "lock.fill").font(.system(size: 34, weight: .bold)).foregroundStyle(theme.accent).accessibilityHidden(true)
            Text("Enter your ThatWay passcode").font(.nunito(22, .black)).foregroundStyle(theme.ink)
            Text(reason).font(.nunito(14, .semibold)).foregroundStyle(theme.textSecondary).multilineTextAlignment(.center)
            PinField(pin: $pin, theme: theme, label: "ThatWay passcode", onComplete: check)
                .padding(.top, 8)
            if let message {
                Text(message).font(.nunito(13, .extraBold)).foregroundStyle(theme.needleRed).multilineTextAlignment(.center)
            }
            Button("Forgot your passcode?", action: forgot).font(.nunito(13, .extraBold)).foregroundStyle(theme.accent)
            Spacer()
            Button("Cancel", action: cancel).font(.nunito(14, .extraBold)).foregroundStyle(theme.textSecondary).padding(.bottom, 12)
        }
        .padding(.horizontal, 24)
    }

    private func check(_ entered: String) {
        guard let user = owner.currentUserId else { cancel(); return }
        switch owner.appPasscode.verify(entered, for: user) {
        case .correct: owner.resolve(.success)
        case .wrong(let left):
            pin = ""
            message = "That isn’t right. \(left) \(left == 1 ? "try" : "tries") left before it locks for a while."
        case .lockedOut(let until):
            pin = ""
            let minutes = max(1, Int((until.timeIntervalSinceNow / 60).rounded(.up)))
            message = "Too many wrong tries. Try again in about \(minutes) \(minutes == 1 ? "minute" : "minutes")."
        case .notSet:
            owner.resolve(.failed)
        }
    }
}

// MARK: - Setting one up

private struct PasscodeSetupFlow: View {
    @ObservedObject var owner: OwnerAuthCoordinator
    let reason: String
    let theme: AppTheme
    @StateObject private var setup: AppPasscodeSetup
    @State private var code = ""
    @State private var pin = ""

    init(owner: OwnerAuthCoordinator, email: EmailVerifying, reason: String, theme: AppTheme) {
        self.owner = owner; self.reason = reason; self.theme = theme
        _setup = StateObject(wrappedValue: AppPasscodeSetup(email: email, passcode: owner.appPasscode, userId: owner.currentUserId ?? ""))
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                switch setup.step {
                case .intro: intro
                case .emailCode(let destination): emailCode(destination)
                case .choose: choose
                case .confirm: confirm
                case .done: done
                }
                if let message = setup.message {
                    Text(message).font(.nunito(13, .extraBold)).foregroundStyle(theme.needleRed).multilineTextAlignment(.center)
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    private var intro: some View {
        VStack(spacing: 14) {
            Image(systemName: "lock.shield.fill").font(.system(size: 34, weight: .bold)).foregroundStyle(theme.accent).accessibilityHidden(true)
            Text("Lock this first").font(.nunito(22, .black)).foregroundStyle(theme.ink)
            Text(reason).font(.nunito(14, .semibold)).foregroundStyle(theme.ink).multilineTextAlignment(.center)
            VStack(alignment: .leading, spacing: 10) {
                Text("To allow someone to see where you are, ThatWay needs to know it’s really you holding the phone. In order of how good they are:")
                    .font(.nunito(13, .semibold)).foregroundStyle(theme.textSecondary)
                bullet("1", "Face ID or Touch ID: the best. Turn it on in Settings, Face ID & Passcode.")
                bullet("2", "Your phone’s passcode: next best.")
                bullet("3", "A ThatWay passcode: the last resort, and the only one we can offer here, because your phone has neither. To set it up we email you a code first, so only the owner of this account can.")
            }
            Text("A ThatWay passcode only guards ThatWay, not your phone. A reminder stays on screen until you turn on a real phone lock. Nothing else in the app is blocked.")
                .font(.nunito(12, .semibold)).foregroundStyle(theme.textSecondary).multilineTextAlignment(.center)
            primary("Email me a code") { Task { await setup.sendCode() } }
            Button("Not now") { owner.resolve(.cancelled) }.font(.nunito(14, .extraBold)).foregroundStyle(theme.textSecondary)
        }
    }

    private func emailCode(_ destination: String?) -> some View {
        VStack(spacing: 14) {
            Text("Check your email").font(.nunito(22, .black)).foregroundStyle(theme.ink)
            Text("We sent a code to \(destination ?? "your email address"). It can take a minute, and may land in spam.")
                .font(.nunito(14, .semibold)).foregroundStyle(theme.ink).multilineTextAlignment(.center)
            TextField("Code", text: $code)
                .keyboardType(.numberPad).textContentType(.oneTimeCode)
                .font(.nunito(20, .extraBold)).multilineTextAlignment(.center)
                .padding(.vertical, 12)
                .background(RoundedRectangle(cornerRadius: 14).fill(theme.ink.opacity(0.06)))
            primary(setup.isWorking ? "Checking…" : "Verify") { Task { await setup.verify(code: code) } }
                .disabled(setup.isWorking || code.isEmpty)
            Button("Send a new code") { Task { await setup.sendCode() } }.font(.nunito(13, .extraBold)).foregroundStyle(theme.accent)
            Button("Cancel") { owner.resolve(.cancelled) }.font(.nunito(14, .extraBold)).foregroundStyle(theme.textSecondary)
        }
    }

    private var choose: some View {
        VStack(spacing: 14) {
            Text("Choose a passcode").font(.nunito(22, .black)).foregroundStyle(theme.ink)
            Text("Six digits. Don’t use your phone’s passcode, a birthday, or a run like 123456.")
                .font(.nunito(14, .semibold)).foregroundStyle(theme.textSecondary).multilineTextAlignment(.center)
            PinField(pin: $pin, theme: theme, label: "New passcode") { entered in setup.choose(entered); pin = "" }
            Button("Cancel") { owner.resolve(.cancelled) }.font(.nunito(14, .extraBold)).foregroundStyle(theme.textSecondary)
        }
    }

    private var confirm: some View {
        VStack(spacing: 14) {
            Text("Enter it again").font(.nunito(22, .black)).foregroundStyle(theme.ink)
            PinField(pin: $pin, theme: theme, label: "Confirm passcode") { entered in setup.confirm(entered); pin = "" }
            Button("Start again") { pin = ""; setup.startChoosingAgain() }.font(.nunito(13, .extraBold)).foregroundStyle(theme.accent)
        }
    }

    private var done: some View {
        VStack(spacing: 14) {
            Image(systemName: "checkmark.circle.fill").font(.system(size: 44)).foregroundStyle(theme.accent).accessibilityHidden(true)
            Text("Passcode set").font(.nunito(22, .black)).foregroundStyle(theme.ink)
            Text("You’ll be asked for it whenever you allow someone to trace you. You can change it any time by choosing “Forgot your passcode?”.")
                .font(.nunito(14, .semibold)).foregroundStyle(theme.textSecondary).multilineTextAlignment(.center)
            primary("Continue") { owner.resolve(.success) }
        }
    }

    private func bullet(_ n: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(n).font(.nunito(12, .black)).foregroundStyle(theme.onAccent).frame(width: 22, height: 22).background(Circle().fill(theme.accent))
            Text(text).font(.nunito(13, .semibold)).foregroundStyle(theme.ink).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func primary(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.nunito(14, .black)).foregroundStyle(theme.onAccent)
                .frame(maxWidth: .infinity).frame(height: 50)
                .background(RoundedRectangle(cornerRadius: 16).fill(theme.accent))
        }
        .buttonStyle(.plain)
    }
}
