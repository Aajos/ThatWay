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
        case .cognito(let type, let message): return Self.friendlyMessage(type: type, fallback: message)
        case .unexpectedResponse: return "Unexpected response from the server."
        }
    }

    /// Cognito's own wording ("1 validation error detected: Value at 'password'…") is written for developers; these are
    /// the cases a person can actually act on. Anything unlisted keeps the server's message.
    static func friendlyMessage(type: String, fallback: String) -> String {
        let name = type.split(separator: "#").last.map(String.init) ?? type
        switch name {
        case "UserNotConfirmedException": return "That email isn't confirmed yet."
        case "UsernameExistsException": return "That username is taken."
        case "CodeMismatchException": return "That code isn't right. Check the latest email and try again."
        case "ExpiredCodeException": return "That code has expired. Tap “Send a new code”."
        case "LimitExceededException", "TooManyRequestsException", "TooManyFailedAttemptsException":
            return "Too many attempts. Wait a few minutes and try again."
        case "InvalidPasswordException": return "Use at least 8 characters with a mix of letters, numbers and symbols."
        case "NotAuthorizedException", "UserNotFoundException": return "Wrong username or password."
        case "InvalidParameterException" where fallback.localizedCaseInsensitiveContains("password"):
            return "Use at least 8 characters with a mix of letters, numbers and symbols."
        case "CodeDeliveryFailureException": return "We couldn't send the email. Check the address and try again."
        default: return fallback
        }
    }

    /// The Cognito exception name without any namespace prefix, nil for other errors.
    var cognitoName: String? {
        guard case .cognito(let type, _) = self else { return nil }
        return type.split(separator: "#").last.map(String.init) ?? type
    }
}

@MainActor
final class AuthManager: ObservableObject {
    @Published var authState: AuthState = .restoring
    @Published var currentUser: AuthUser?
    @Published var isLoading = false
    @Published var errorMessage: String?
    /// A neutral line (not an error): "We sent a new code", shown on the confirmation step.
    @Published var noticeMessage: String?
    /// Where Cognito says the confirmation code went, already masked by Cognito ("j***@g***").
    @Published var codeDestination: String?

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

    /// Every network call goes through here so tests can answer with canned Cognito responses.
    typealias Transport = (URLRequest) async throws -> (Data, URLResponse)
    private let transport: Transport

    private let idTokenKey = "idToken"
    private let accessTokenKey = "accessToken"
    private let refreshTokenKey = "refreshToken"

    /// Attach to outgoing API Gateway requests as `Authorization: Bearer <token>`.
    var bearerToken: String? { accessToken }

    init(transport: @escaping Transport = { try await URLSession.shared.data(for: $0) }, restoreSession: Bool = true) {
        self.transport = transport
        guard restoreSession else { authState = .signedOut; return }
        if let refresh = KeychainStore.get(refreshTokenKey) {
            refreshToken = refresh
            // A saved login opens the app straight away from the cached identity, so a slow or missing connection
            // never holds the user on a blank screen (or, worse, in the city with no way in). The tokens are then
            // refreshed quietly in the background.
            if let cachedID = KeychainStore.get(idTokenKey), let claims = Self.decodeJWT(cachedID), let sub = claims["sub"] as? String {
                idToken = cachedID
                accessToken = KeychainStore.get(accessTokenKey)
                let username = (claims["cognito:username"] as? String) ?? (claims["username"] as? String) ?? sub
                currentUser = AuthUser(id: sub, username: username)
                authState = .signedIn
            }
            Task { await refreshAccessToken() }
        } else {
            authState = .signedOut
        }
    }

    func signUp(username: String, email: String, password: String) async {
        isLoading = true; errorMessage = nil; noticeMessage = nil
        defer { isLoading = false }
        do {
            let json = try await cognitoRequest(target: "SignUp", body: [
                "ClientId": Config.cognitoAppClientId,
                "Username": username,
                "Password": password,
                "UserAttributes": [["Name": "email", "Value": email]],
            ])
            codeDestination = Self.destination(in: json)
            authState = .needsConfirmation(username: username)
        } catch let error as AuthError where error.cognitoName == "UsernameExistsException" {
            // An earlier sign-up that never got its code also answers "exists". Asking for a fresh code tells the two
            // apart: it works for an unconfirmed account and is refused for one that is already confirmed.
            if await requestNewCode(for: username) {
                noticeMessage = "That username has a sign-up waiting for its code. We've sent a new one."
            } else {
                errorMessage = error.localizedDescription
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Asks Cognito to email the code again. Returns whether a code is on its way (and, if so, moves to the code step).
    @discardableResult
    func resendConfirmationCode(username: String) async -> Bool {
        isLoading = true; errorMessage = nil; noticeMessage = nil
        defer { isLoading = false }
        let sent = await requestNewCode(for: username)
        if sent { noticeMessage = "We've sent a new code. It can take a minute, and may land in spam." }
        else if errorMessage == nil { errorMessage = "We couldn't send a new code. Try again in a minute." }
        return sent
    }

    private func requestNewCode(for username: String) async -> Bool {
        do {
            let json = try await cognitoRequest(target: "ResendConfirmationCode", body: [
                "ClientId": Config.cognitoAppClientId,
                "Username": username,
            ])
            codeDestination = Self.destination(in: json)
            authState = .needsConfirmation(username: username)
            return true
        } catch {
            if (error as? AuthError)?.cognitoName != "InvalidParameterException" { errorMessage = error.localizedDescription }
            return false
        }
    }

    /// Leaves the code step (wrong email, or the person wants to start over).
    func cancelConfirmation() {
        errorMessage = nil; noticeMessage = nil; codeDestination = nil
        authState = .signedOut
    }

    private static func destination(in json: [String: Any]) -> String? {
        (json["CodeDeliveryDetails"] as? [String: Any])?["Destination"] as? String
    }

    func confirmSignUp(username: String, code: String) async {
        isLoading = true; errorMessage = nil; noticeMessage = nil
        defer { isLoading = false }
        do {
            _ = try await cognitoRequest(target: "ConfirmSignUp", body: [
                "ClientId": Config.cognitoAppClientId,
                "Username": username,
                "ConfirmationCode": code,
            ])
            codeDestination = nil
            authState = .signedOut
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func signIn(username: String, password: String) async {
        isLoading = true; errorMessage = nil; noticeMessage = nil
        defer { isLoading = false }
        do {
            let json = try await cognitoRequest(target: "InitiateAuth", body: [
                "AuthFlow": "USER_PASSWORD_AUTH",
                "ClientId": Config.cognitoAppClientId,
                "AuthParameters": ["USERNAME": username, "PASSWORD": password],
            ])
            try applyAuthResult(json)
        } catch let error as AuthError where error.cognitoName == "UserNotConfirmedException" {
            // They signed up but never entered the code (or left the app on that step): take them back to it and
            // send a fresh code instead of leaving them at a sign-in error they cannot get past.
            if await requestNewCode(for: username) {
                noticeMessage = "That email isn't confirmed yet. We've sent a new code."
            } else {
                errorMessage = error.localizedDescription
            }
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
        request.timeoutInterval = 10      // the default 60 s would leave the app waiting on a blank screen

        let (data, response) = try await transport(request)
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
        } catch AuthError.cognito {
            // The server itself refused the saved login (expired or revoked): that is the only reason to sign out.
            signOut()
            return false
        } catch {
            // No connection, a timeout, a server hiccup: keep the saved login so the next launch can try again.
            // If there is no cached identity to show, fall back to the sign-in screen without deleting anything.
            if authState == .restoring { authState = .signedOut }
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
        request.timeoutInterval = 10

        let (data, response) = try await transport(request)
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
