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

    @Test func namespacedExceptionTypesAreRecognised() {
        let error = AuthError.cognito(type: "com.amazonaws.cognito.identity.idp.model#UserNotConfirmedException", message: "x")
        #expect(error.cognitoName == "UserNotConfirmedException")
    }

    @Test func friendsAndNearbyNeedTheServiceAddress() {
        #expect(Config.apiConfigured == !Config.apiBaseURL.contains("REPLACE_WITH"))
    }
}
