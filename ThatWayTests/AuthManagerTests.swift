//
//  AuthManagerTests.swift
//  ThatWayTests
//
//  The sign-up / confirmation path, against canned Cognito answers (no network, no Keychain restore).
//  These are the situations that made "the email never arrives" look permanent: a sign-up left unconfirmed,
//  signing in before confirming, signing up again with the same username, and no way to ask for a new code.
//

import Testing
import Foundation
@testable import ThatWay

/// Answers each Cognito call by its `X-Amz-Target`, and remembers what was asked.
private final class CognitoStub: @unchecked Sendable {
    struct Reply { let status: Int; let body: [String: Any] }
    var replies: [String: Reply] = [:]
    private(set) var targets: [String] = []

    func ok(_ target: String, _ body: [String: Any] = [:]) { replies[target] = Reply(status: 200, body: body) }
    func fail(_ target: String, type: String, message: String = "x") {
        replies[target] = Reply(status: 400, body: ["__type": type, "message": message])
    }

    var transport: AuthManager.Transport {
        { [self] request in
            let target = (request.value(forHTTPHeaderField: "X-Amz-Target") ?? "").replacingOccurrences(of: "AWSCognitoIdentityProviderService.", with: "")
            targets.append(target)
            let reply = replies[target] ?? Reply(status: 500, body: [:])
            let data = try JSONSerialization.data(withJSONObject: reply.body)
            let response = HTTPURLResponse(url: request.url!, statusCode: reply.status, httpVersion: nil, headerFields: nil)!
            return (data, response)
        }
    }
}

private let delivery: [String: Any] = ["CodeDeliveryDetails": ["Destination": "j***@g***", "DeliveryMedium": "EMAIL"]]

@MainActor
struct AuthManagerTests {
    private func makeManager(_ stub: CognitoStub) -> AuthManager {
        AuthManager(transport: stub.transport, restoreSession: false)
    }

    @Test func signUpMovesToTheCodeStepAndRemembersWhereItWent() async {
        let stub = CognitoStub(); stub.ok("SignUp", delivery)
        let auth = makeManager(stub)
        await auth.signUp(username: "sam", email: "sam@example.com", password: "Passw0rd!23")
        #expect(auth.authState == .needsConfirmation(username: "sam"))
        #expect(auth.codeDestination == "j***@g***")
        #expect(auth.errorMessage == nil)
    }

    @Test func signingInBeforeConfirmingSendsANewCodeInsteadOfDeadEnding() async {
        let stub = CognitoStub()
        stub.fail("InitiateAuth", type: "UserNotConfirmedException")
        stub.ok("ResendConfirmationCode", delivery)
        let auth = makeManager(stub)
        await auth.signIn(username: "sam", password: "Passw0rd!23")
        #expect(auth.authState == .needsConfirmation(username: "sam"))
        #expect(stub.targets == ["InitiateAuth", "ResendConfirmationCode"])
        #expect(auth.noticeMessage?.contains("new code") == true)
        #expect(auth.errorMessage == nil)
    }

    @Test func reusingAnUnconfirmedUsernameResendsTheCode() async {
        let stub = CognitoStub()
        stub.fail("SignUp", type: "UsernameExistsException")
        stub.ok("ResendConfirmationCode", delivery)
        let auth = makeManager(stub)
        await auth.signUp(username: "sam", email: "sam@example.com", password: "Passw0rd!23")
        #expect(auth.authState == .needsConfirmation(username: "sam"))
        #expect(auth.noticeMessage != nil)
    }

    @Test func reusingAConfirmedUsernameSaysItIsTaken() async {
        let stub = CognitoStub()
        stub.fail("SignUp", type: "UsernameExistsException")
        stub.fail("ResendConfirmationCode", type: "InvalidParameterException", message: "User is already confirmed.")
        let auth = makeManager(stub)
        await auth.signUp(username: "sam", email: "sam@example.com", password: "Passw0rd!23")
        #expect(auth.authState == .signedOut)
        #expect(auth.errorMessage == "That username is taken.")
    }

    @Test func resendReportsWhenThereIsNoMoreRoomToSend() async {
        let stub = CognitoStub()
        stub.fail("ResendConfirmationCode", type: "LimitExceededException")
        let auth = makeManager(stub)
        let sent = await auth.resendConfirmationCode(username: "sam")
        #expect(sent == false)
        #expect(auth.errorMessage == "Too many attempts. Wait a few minutes and try again.")
    }

    @Test func confirmingReturnsToSignIn() async {
        let stub = CognitoStub(); stub.ok("SignUp", delivery); stub.ok("ConfirmSignUp")
        let auth = makeManager(stub)
        await auth.signUp(username: "sam", email: "sam@example.com", password: "Passw0rd!23")
        await auth.confirmSignUp(username: "sam", code: "123456")
        #expect(auth.authState == .signedOut)
        #expect(auth.codeDestination == nil)
    }

    @Test func aWrongCodeStaysOnTheCodeStepWithAClearMessage() async {
        let stub = CognitoStub(); stub.ok("SignUp", delivery); stub.fail("ConfirmSignUp", type: "CodeMismatchException")
        let auth = makeManager(stub)
        await auth.signUp(username: "sam", email: "sam@example.com", password: "Passw0rd!23")
        await auth.confirmSignUp(username: "sam", code: "000000")
        #expect(auth.authState == .needsConfirmation(username: "sam"))
        #expect(auth.errorMessage?.contains("isn't right") == true)
    }

    @Test func startingOverLeavesTheCodeStep() async {
        let stub = CognitoStub(); stub.ok("SignUp", delivery)
        let auth = makeManager(stub)
        await auth.signUp(username: "sam", email: "typo@example.com", password: "Passw0rd!23")
        auth.cancelConfirmation()
        #expect(auth.authState == .signedOut)
        #expect(auth.codeDestination == nil)
    }

    @Test func forgotPasswordEmailsACodeAndMovesToTheResetStep() async {
        let stub = CognitoStub(); stub.ok("ForgotPassword", delivery)
        let auth = makeManager(stub)
        await auth.forgotPassword(username: " sam ")
        #expect(auth.authState == .resettingPassword(username: "sam"))
        #expect(auth.codeDestination == "j***@g***")
        #expect(stub.targets == ["ForgotPassword"])
    }

    @Test func forgotPasswordNeedsAUsername() async {
        let stub = CognitoStub()
        let auth = makeManager(stub)
        await auth.forgotPassword(username: "  ")
        #expect(stub.targets.isEmpty)
        #expect(auth.errorMessage?.contains("username") == true)
        #expect(auth.authState == .signedOut)
    }

    @Test func resetWithTheRightCodeReturnsToSignIn() async {
        let stub = CognitoStub(); stub.ok("ForgotPassword", delivery); stub.ok("ConfirmForgotPassword")
        let auth = makeManager(stub)
        await auth.forgotPassword(username: "sam")
        await auth.confirmPasswordReset(username: "sam", code: "123456", newPassword: "NewPassw0rd!")
        #expect(auth.authState == .signedOut)
        #expect(auth.noticeMessage?.contains("Password changed") == true)
    }

    @Test func aWrongResetCodeKeepsTheStepOpen() async {
        let stub = CognitoStub(); stub.ok("ForgotPassword", delivery); stub.fail("ConfirmForgotPassword", type: "CodeMismatchException")
        let auth = makeManager(stub)
        await auth.forgotPassword(username: "sam")
        await auth.confirmPasswordReset(username: "sam", code: "000000", newPassword: "NewPassw0rd!")
        #expect(auth.authState == .resettingPassword(username: "sam"))
        #expect(auth.errorMessage?.contains("isn't right") == true)
    }

    @Test func anUnconfirmedAccountIsSentTheSignUpCodeInstead() async {
        let stub = CognitoStub(); stub.fail("ForgotPassword", type: "InvalidParameterException"); stub.ok("ResendConfirmationCode", delivery)
        let auth = makeManager(stub)
        await auth.forgotPassword(username: "sam")
        #expect(auth.authState == .needsConfirmation(username: "sam"))
    }

    // MARK: Username availability

    @Test func theRulesAreLowercaseLettersNumbersAndUnderscore() {
        #expect(UsernameRules.isValid("sam"))
        #expect(UsernameRules.isValid("  Sam_99  "), "trimmed and lowercased first")
        #expect(UsernameRules.normalised("  Sam_99 ") == "sam_99")
        #expect(!UsernameRules.isValid("ab"))
        #expect(!UsernameRules.isValid(String(repeating: "a", count: 21)))
        #expect(!UsernameRules.isValid("1sam"))
        #expect(!UsernameRules.isValid("sam smith"))
        #expect(!UsernameRules.isValid("sam-smith"))
        #expect(!UsernameRules.isValid("sämüel"), "ASCII only")
        #expect(!UsernameRules.isValid(""))
    }

    @Test func anInvalidNameIsNeverSentToTheServer() async {
        let stub = CognitoStub()
        let auth = makeManager(stub)
        #expect(await auth.usernameAvailability("a b") == .invalid)
        #expect(stub.targets.isEmpty)
    }

    @Test func theServersAnswersMapToStatuses() async {
        let stub = CognitoStub()
        let auth = makeManager(stub)
        stub.ok("", ["available": true])
        #expect(await auth.usernameAvailability("freshname") == .available)
        stub.ok("", ["available": false, "reason": "taken"])
        #expect(await auth.usernameAvailability("aadit") == .taken)
        stub.ok("", ["available": false, "reason": "reserved"])
        #expect(await auth.usernameAvailability("admin") == .reserved)
    }

    @Test func aFailedCheckNeverBlocksSigningUp() async {
        let stub = CognitoStub()           // no reply configured: the stub answers 500
        let auth = makeManager(stub)
        #expect(await auth.usernameAvailability("somebody") == .unknown)
    }

    @Test func signUpUsesTheLowercaseName() async {
        let stub = CognitoStub(); stub.ok("SignUp", delivery)
        let auth = makeManager(stub)
        await auth.signUp(username: "  Sam_99 ", email: "sam@example.com", password: "Passw0rd!23")
        #expect(auth.authState == .needsConfirmation(username: "sam_99"))
    }

    // MARK: Proving the email (before an app passcode can be set up)

    private func signedIn(_ stub: CognitoStub) async -> AuthManager {
        let id = Self.jwt(["sub": "user-1", "cognito:username": "sam"])
        stub.ok("InitiateAuth", ["AuthenticationResult": ["IdToken": id, "AccessToken": "access-1", "RefreshToken": "refresh-1"]])
        let auth = makeManager(stub)
        await auth.signIn(username: "sam", password: "Passw0rd!23")
        return auth
    }

    private static func jwt(_ claims: [String: Any]) -> String {
        func b64(_ data: Data) -> String { data.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "") }
        let payload = try! JSONSerialization.data(withJSONObject: claims)
        return "\(b64(Data("{}".utf8))).\(b64(payload)).sig"
    }

    @Test func aCodeIsSentToTheVerifiedEmailAndTheMaskedAddressIsReturned() async throws {
        let stub = CognitoStub()
        let auth = await signedIn(stub)
        stub.ok("GetUserAttributeVerificationCode", delivery)
        let destination = try await auth.sendVerificationCode()
        #expect(destination == "j***@g***")
        #expect(stub.targets.last == "GetUserAttributeVerificationCode")
    }

    @Test func verifyingTheCodeSucceedsOrSaysWhyNot() async throws {
        let stub = CognitoStub()
        let auth = await signedIn(stub)
        stub.ok("VerifyUserAttribute")
        try await auth.verifyEmailCode("123456")
        #expect(stub.targets.last == "VerifyUserAttribute")
        stub.fail("VerifyUserAttribute", type: "CodeMismatchException")
        do { try await auth.verifyEmailCode("000000"); Issue.record("should have thrown") }
        catch { #expect(error.localizedDescription.contains("isn't right")) }
    }

    @Test func withoutBeingSignedInNoCodeIsSent() async {
        let stub = CognitoStub()
        let auth = makeManager(stub)
        await #expect(throws: AuthError.self) { _ = try await auth.sendVerificationCode() }
        #expect(stub.targets.isEmpty)
    }

    @Test func anExpiredSessionIsRefreshedOnceThenTheCodeIsSent() async throws {
        let stub = CognitoStub()
        // First call: the access token has expired. The refresh works. The second try succeeds.
        var calls = 0
        let inner = stub.transport
        let flaky: AuthManager.Transport = { request in
            let target = (request.value(forHTTPHeaderField: "X-Amz-Target") ?? "").replacingOccurrences(of: "AWSCognitoIdentityProviderService.", with: "")
            if target == "GetUserAttributeVerificationCode" {
                calls += 1
                if calls == 1 {
                    let data = try JSONSerialization.data(withJSONObject: ["__type": "NotAuthorizedException", "message": "expired"])
                    return (data, HTTPURLResponse(url: request.url!, statusCode: 400, httpVersion: nil, headerFields: nil)!)
                }
            }
            return try await inner(request)
        }
        let again = AuthManager(transport: flaky, restoreSession: false)
        let id = Self.jwt(["sub": "user-1", "cognito:username": "sam"])
        stub.ok("InitiateAuth", ["AuthenticationResult": ["IdToken": id, "AccessToken": "access-2", "RefreshToken": "refresh-1"]])
        await again.signIn(username: "sam", password: "Passw0rd!23")
        stub.ok("GetUserAttributeVerificationCode", delivery)
        let destination = try await again.sendVerificationCode()
        #expect(destination == "j***@g***" && calls == 2)
    }

    @Test func namespacedExceptionTypesAreRecognised() {
        let error = AuthError.cognito(type: "com.amazonaws.cognito.identity.idp.model#UserNotConfirmedException", message: "x")
        #expect(error.cognitoName == "UserNotConfirmedException")
    }

    @Test func friendsAndNearbyNeedTheServiceAddress() {
        #expect(Config.apiConfigured == !Config.apiBaseURL.contains("REPLACE_WITH"))
    }
}
