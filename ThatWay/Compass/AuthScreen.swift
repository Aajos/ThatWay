//
//  AuthScreen.swift
//  ThatWay
//
//  Sign in / sign up / email-confirmation, shown by RootView whenever AuthManager isn't
//  signed in. Styled to match the rest of the app (ProfileScreen's field/button conventions).
//

import SwiftUI
import AuthenticationServices
import ThatWayUI

struct AuthScreen: View {
    @EnvironmentObject var app: AppModel
    @EnvironmentObject var auth: AuthManager

    private enum Mode { case signIn, signUp }
    @State private var mode: Mode = .signIn
    @State private var username = ""
    @State private var email = ""
    @State private var password = ""
    @State private var confirmationCode = ""
    @State private var appleUsername = ""

    var body: some View {
        let theme = app.currentTheme

        ScrollView {
            VStack(spacing: 22) {
                VStack(spacing: 6) {
                    Text("ThatWay").font(.nunito(28, .black)).foregroundStyle(theme.ink)
                    Text(headline).font(.nunito(13, .semibold)).foregroundStyle(theme.textSecondary)
                }
                .padding(.top, 90)

                if case .needsConfirmation(let pendingUsername) = auth.authState {
                    confirmSection(theme: theme, username: pendingUsername)
                } else if case .needsAppleUsername = auth.authState {
                    appleUsernameSection(theme: theme)
                } else {
                    modePicker(theme: theme)
                    fields(theme: theme)
                    primaryButton(theme: theme)
                    if Config.appleSignInEnabled {
                        orDivider(theme: theme)
                        appleButton(theme: theme)
                    }
                }

                if let notice = auth.noticeMessage {
                    Text(notice)
                        .font(.nunito(13, .semibold))
                        .foregroundStyle(theme.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 8)
                }

                if let error = auth.errorMessage {
                    Text(error)
                        .font(.nunito(13, .semibold))
                        .foregroundStyle(theme.needleRed)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 8)
                }
            }
            .padding(.horizontal, 28)
            .padding(.bottom, 60)
            .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(theme.screen.ignoresSafeArea())
        .foregroundStyle(theme.ink)
    }

    private var headline: String {
        if case .needsConfirmation = auth.authState {
            if let destination = auth.codeDestination { return "We sent a 6-digit code to \(destination)" }
            return "Check your email for a code"
        }
        if case .needsAppleUsername = auth.authState { return "Pick a username for your friends" }
        return mode == .signIn ? "Sign in to find your friends" : "Create an account"
    }

    @ViewBuilder
    private func modePicker(theme: AppTheme) -> some View {
        HStack(spacing: 0) {
            modeTab("Sign in", isOn: mode == .signIn, theme: theme) { mode = .signIn; auth.errorMessage = nil }
            modeTab("Sign up", isOn: mode == .signUp, theme: theme) { mode = .signUp; auth.errorMessage = nil }
        }
        .padding(4)
        .background(RoundedRectangle(cornerRadius: 16).fill(theme.ink.opacity(0.05)))
    }

    @ViewBuilder
    private func modeTab(_ title: String, isOn: Bool, theme: AppTheme, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.nunito(13, .extraBold))
                .foregroundStyle(isOn ? theme.onAccent : theme.ink.opacity(0.6))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(RoundedRectangle(cornerRadius: 13).fill(isOn ? theme.accent : .clear))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func fields(theme: AppTheme) -> some View {
        VStack(spacing: 10) {
            field("Username", text: $username, theme: theme, autocapitalization: .never)
            if mode == .signUp {
                field("Email", text: $email, theme: theme, keyboard: .emailAddress, autocapitalization: .never)
            }
            field("Password", text: $password, theme: theme, isSecure: true)
        }
    }

    @ViewBuilder
    private func field(_ placeholder: String, text: Binding<String>, theme: AppTheme,
                        keyboard: UIKeyboardType = .default, autocapitalization: TextInputAutocapitalization = .sentences,
                        isSecure: Bool = false) -> some View {
        Group {
            if isSecure {
                SecureField(placeholder, text: text)
            } else {
                TextField(placeholder, text: text)
                    .keyboardType(keyboard)
                    .textInputAutocapitalization(autocapitalization)
                    .autocorrectionDisabled()
            }
        }
        .font(.nunito(15, .semibold))
        .padding(.horizontal, 14)
        .frame(height: 48)
        .background(RoundedRectangle(cornerRadius: 14).fill(theme.ink.opacity(0.05)))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(theme.ink.opacity(0.1)))
    }

    @ViewBuilder
    private func primaryButton(theme: AppTheme) -> some View {
        Button(action: submit) {
            ZStack {
                if auth.isLoading {
                    ProgressView().tint(theme.onAccent)
                } else {
                    Text(mode == .signIn ? "SIGN IN" : "CREATE ACCOUNT")
                        .font(.nunito(14, .black)).tracking(0.8)
                }
            }
            .foregroundStyle(theme.onAccent)
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .background(RoundedRectangle(cornerRadius: 16).fill(theme.accent))
            .opacity(canSubmit ? 1 : 0.5)
        }
        .buttonStyle(.plain)
        .disabled(!canSubmit || auth.isLoading)
        .padding(.top, 4)
    }

    private var canSubmit: Bool {
        let trimmedUsername = username.trimmingCharacters(in: .whitespaces)
        guard !trimmedUsername.isEmpty, !password.isEmpty else { return false }
        if mode == .signUp {
            return email.contains("@") && password.count >= 8
        }
        return true
    }

    private func submit() {
        let trimmedUsername = username.trimmingCharacters(in: .whitespaces)
        Task {
            if mode == .signIn {
                await auth.signIn(username: trimmedUsername, password: password)
            } else {
                await auth.signUp(username: trimmedUsername, email: email.trimmingCharacters(in: .whitespaces), password: password)
            }
        }
    }

    @ViewBuilder
    private func confirmSection(theme: AppTheme, username pendingUsername: String) -> some View {
        VStack(spacing: 14) {
            field("6-digit code", text: $confirmationCode, theme: theme, keyboard: .numberPad)

            Button {
                Task {
                    await auth.confirmSignUp(username: pendingUsername, code: confirmationCode)
                    if case .signedOut = auth.authState {
                        username = pendingUsername
                        password = ""
                        mode = .signIn
                        confirmationCode = ""
                    }
                }
            } label: {
                ZStack {
                    if auth.isLoading {
                        ProgressView().tint(theme.onAccent)
                    } else {
                        Text("CONFIRM").font(.nunito(14, .black)).tracking(0.8)
                    }
                }
                .foregroundStyle(theme.onAccent)
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background(RoundedRectangle(cornerRadius: 16).fill(theme.accent))
                .opacity(confirmationCode.count == 6 ? 1 : 0.5)
            }
            .buttonStyle(.plain)
            .disabled(confirmationCode.count != 6 || auth.isLoading)

            Button("Send a new code") {
                Task { await auth.resendConfirmationCode(username: pendingUsername) }
            }
            .font(.nunito(13, .extraBold))
            .foregroundStyle(theme.accent)
            .disabled(auth.isLoading)

            Button("Wrong email? Start over") {
                confirmationCode = ""
                auth.cancelConfirmation()
                mode = .signUp
            }
            .font(.nunito(12, .semibold))
            .foregroundStyle(theme.textSecondary)
            .disabled(auth.isLoading)

            Text("The email is sent automatically and can take a minute. Check your spam or junk folder if it isn't in your inbox.")
                .font(.nunito(11, .semibold))
                .foregroundStyle(theme.textSecondary)
                .multilineTextAlignment(.center)
        }
    }

    @ViewBuilder
    private func orDivider(theme: AppTheme) -> some View {
        HStack(spacing: 10) {
            Rectangle().fill(theme.borderColor).frame(height: 1)
            Text("OR").font(.nunito(11, .extraBold)).foregroundStyle(theme.textSecondary)
            Rectangle().fill(theme.borderColor).frame(height: 1)
        }
    }

    @ViewBuilder
    private func appleButton(theme: AppTheme) -> some View {
        SignInWithAppleButton(.signIn) { request in
            request.requestedScopes = [.fullName, .email]
        } onCompletion: { result in
            guard case .success(let authorization) = result,
                  let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                  let tokenData = credential.identityToken,
                  let token = String(data: tokenData, encoding: .utf8) else { return }
            appleUsername = credential.fullName?.givenName ?? ""
            Task { await auth.signInWithApple(identityToken: token) }
        }
        .signInWithAppleButtonStyle(theme.light ? .white : .black)
        .frame(height: 50)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .disabled(auth.isLoading)
    }

    @ViewBuilder
    private func appleUsernameSection(theme: AppTheme) -> some View {
        VStack(spacing: 14) {
            field("Username", text: $appleUsername, theme: theme, autocapitalization: .never)

            Button {
                let trimmed = appleUsername.trimmingCharacters(in: .whitespaces)
                Task { await auth.submitAppleUsername(trimmed) }
            } label: {
                ZStack {
                    if auth.isLoading {
                        ProgressView().tint(theme.onAccent)
                    } else {
                        Text("CONTINUE").font(.nunito(14, .black)).tracking(0.8)
                    }
                }
                .foregroundStyle(theme.onAccent)
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background(RoundedRectangle(cornerRadius: 16).fill(theme.accent))
                .opacity(appleUsername.trimmingCharacters(in: .whitespaces).isEmpty ? 0.5 : 1)
            }
            .buttonStyle(.plain)
            .disabled(appleUsername.trimmingCharacters(in: .whitespaces).isEmpty || auth.isLoading)
        }
    }
}
