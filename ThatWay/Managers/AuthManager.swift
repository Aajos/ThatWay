//
//  AuthManager.swift
//  ThatWay
//
//  Talks to Cognito's own JSON API directly over URLSession (same plain-REST pattern as
//  RoutingManager) rather than pulling in the Amplify SDK. Cognito's SignUp/InitiateAuth/
//  ConfirmSignUp operations are public — they take the app client id, not a signed request —
//  so a fixed X-Amz-Target header plus a JSON body is all that's needed.
//

import Foundation
import Combine

enum AuthState: Equatable {
    case restoring
    case signedOut
    case needsConfirmation(username: String)
    /// First-ever Sign in with Apple for this person — the backend has a verified identity
    /// but no handle to search/display them by yet, so the app needs to collect one.
    case needsAppleUsername
    case signedIn
}

struct AuthUser: Equatable {
    let id: String
    let username: String
}

enum AuthError: LocalizedError {
    case cognito(type: String, message: String)
    case unexpectedResponse

    var errorDescription: String? {
        switch self {
        case .cognito(_, let message): return message
        case .unexpectedResponse: return "Unexpected response from the server."
        }
    }
}

@MainActor
final class AuthManager: ObservableObject {
    @Published var authState: AuthState = .restoring
    @Published var currentUser: AuthUser?
    @Published var isLoading = false
    @Published var errorMessage: String?

    /// Used only to read identity claims (`sub`, `cognito:username`) for `currentUser` — the
    /// friends API checks the access token, not this one (see `bearerToken`).
    private var idToken: String?
    /// What actually goes on `/friends/*` calls. The API Gateway JWT authorizer validates
    /// Cognito access tokens (matching its Audience against the token's `client_id` claim),
    /// not ID tokens.
    private var accessToken: String?
    private var refreshToken: String?
    /// Stashed only while waiting on `.needsAppleUsername` — retried once the person picks a
    /// handle. Apple identity tokens are short-lived but comfortably outlast that round trip.
    private var pendingAppleIdentityToken: String?

    private let idTokenKey = "idToken"
    private let accessTokenKey = "accessToken"
    private let refreshTokenKey = "refreshToken"

    /// Attach to outgoing API Gateway requests as `Authorization: Bearer <token>`.
    var bearerToken: String? { accessToken }

    init() {
        if let refresh = KeychainStore.get(refreshTokenKey) {
            refreshToken = refresh
            Task { await refreshAccessToken() }
        } else {
            authState = .signedOut
        }
    }

    func signUp(username: String, email: String, password: String) async {
        isLoading = true; errorMessage = nil
        defer { isLoading = false }
        do {
            _ = try await cognitoRequest(target: "SignUp", body: [
                "ClientId": Config.cognitoAppClientId,
                "Username": username,
                "Password": password,
                "UserAttributes": [["Name": "email", "Value": email]],
            ])
            authState = .needsConfirmation(username: username)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func confirmSignUp(username: String, code: String) async {
        isLoading = true; errorMessage = nil
        defer { isLoading = false }
        do {
            _ = try await cognitoRequest(target: "ConfirmSignUp", body: [
                "ClientId": Config.cognitoAppClientId,
                "Username": username,
                "ConfirmationCode": code,
            ])
            authState = .signedOut
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func signIn(username: String, password: String) async {
        isLoading = true; errorMessage = nil
        defer { isLoading = false }
        do {
            let json = try await cognitoRequest(target: "InitiateAuth", body: [
                "AuthFlow": "USER_PASSWORD_AUTH",
                "ClientId": Config.cognitoAppClientId,
                "AuthParameters": ["USERNAME": username, "PASSWORD": password],
            ])
            try applyAuthResult(json)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func signOut() {
        idToken = nil
        accessToken = nil
        refreshToken = nil
        pendingAppleIdentityToken = nil
        KeychainStore.delete(idTokenKey)
        KeychainStore.delete(accessTokenKey)
        KeychainStore.delete(refreshTokenKey)
        currentUser = nil
        errorMessage = nil
        authState = .signedOut
    }

    /// Entry point from AuthScreen's native Sign in with Apple button. `username` is only
    /// passed on the retry after `.needsAppleUsername` was resolved.
    func signInWithApple(identityToken: String, username: String? = nil) async {
        isLoading = true; errorMessage = nil
        defer { isLoading = false }
        do {
            let registration = try await appleRegister(identityToken: identityToken, username: username)
            if (registration["needsUsername"] as? Bool) == true {
                pendingAppleIdentityToken = identityToken
                authState = .needsAppleUsername
                return
            }
            guard let cognitoUsername = registration["username"] as? String else {
                throw AuthError.unexpectedResponse
            }

            let initiated = try await cognitoRequest(target: "InitiateAuth", body: [
                "AuthFlow": "CUSTOM_AUTH",
                "ClientId": Config.cognitoAppClientId,
                "AuthParameters": ["USERNAME": cognitoUsername],
            ])
            guard let session = initiated["Session"] as? String else { throw AuthError.unexpectedResponse }

            let responded = try await cognitoRequest(target: "RespondToAuthChallenge", body: [
                "ClientId": Config.cognitoAppClientId,
                "ChallengeName": "CUSTOM_CHALLENGE",
                "Session": session,
                "ChallengeResponses": ["USERNAME": cognitoUsername, "ANSWER": identityToken],
            ])
            try applyAuthResult(responded)
            pendingAppleIdentityToken = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Resolves `.needsAppleUsername` by retrying registration with the chosen handle.
    func submitAppleUsername(_ username: String) async {
        guard let token = pendingAppleIdentityToken else { return }
        await signInWithApple(identityToken: token, username: username)
    }

    private func appleRegister(identityToken: String, username: String?) async throws -> [String: Any] {
        guard let url = URL(string: Config.apiBaseURL + "/auth/apple/register") else {
            throw AuthError.unexpectedResponse
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        var body: [String: Any] = ["identityToken": identityToken]
        if let username { body["username"] = username }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
            let message = (json["message"] as? String) ?? "Couldn't sign in with Apple."
            throw AuthError.cognito(type: "AppleRegister", message: message)
        }
        return json
    }

    /// Called on launch (session restore) and by FriendsManager after a 401 — access tokens
    /// are only valid for 60 minutes. Returns whether a usable access token came out of it.
    @discardableResult
    func refreshAccessToken() async -> Bool {
        guard let refreshToken else { authState = .signedOut; return false }
        do {
            let json = try await cognitoRequest(target: "InitiateAuth", body: [
                "AuthFlow": "REFRESH_TOKEN_AUTH",
                "ClientId": Config.cognitoAppClientId,
                "AuthParameters": ["REFRESH_TOKEN": refreshToken],
            ])
            try applyAuthResult(json, fallbackRefreshToken: refreshToken)
            return true
        } catch {
            signOut()
            return false
        }
    }

    private func applyAuthResult(_ json: [String: Any], fallbackRefreshToken: String? = nil) throws {
        guard let result = json["AuthenticationResult"] as? [String: Any],
              let idTok = result["IdToken"] as? String,
              let accessTok = result["AccessToken"] as? String,
              let claims = Self.decodeJWT(idTok),
              let sub = claims["sub"] as? String else {
            throw AuthError.unexpectedResponse
        }
        let refreshTok = (result["RefreshToken"] as? String) ?? fallbackRefreshToken
        idToken = idTok
        accessToken = accessTok
        refreshToken = refreshTok
        KeychainStore.set(idTok, for: idTokenKey)
        KeychainStore.set(accessTok, for: accessTokenKey)
        if let refreshTok { KeychainStore.set(refreshTok, for: refreshTokenKey) }

        let username = (claims["cognito:username"] as? String) ?? (claims["username"] as? String) ?? sub
        currentUser = AuthUser(id: sub, username: username)
        authState = .signedIn
    }

    private func cognitoRequest(target: String, body: [String: Any]) async throws -> [String: Any] {
        var request = URLRequest(url: URL(string: Config.cognitoEndpoint)!)
        request.httpMethod = "POST"
        request.setValue("application/x-amz-json-1.1", forHTTPHeaderField: "Content-Type")
        request.setValue("AWSCognitoIdentityProviderService.\(target)", forHTTPHeaderField: "X-Amz-Target")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
            let type = (json["__type"] as? String) ?? "Error"
            let message = (json["message"] as? String) ?? "Something went wrong. Please try again."
            throw AuthError.cognito(type: type, message: message)
        }
        return json
    }

    /// Reads the payload only — the app trusts a token because it just got it from Cognito
    /// over HTTPS, not because it re-verified the signature itself.
    private static func decodeJWT(_ token: String) -> [String: Any]? {
        let parts = token.split(separator: ".")
        guard parts.count == 3 else { return nil }
        var base64 = String(parts[1]).replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while base64.count % 4 != 0 { base64 += "=" }
        guard let data = Data(base64Encoded: base64) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }
}
