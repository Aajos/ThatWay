//
//  OwnerAuthentication.swift
//  ThatWay
//
//  "Is this really the phone's owner?" asked before the one decision that matters: letting someone see where you are.
//
//    Face ID / Touch ID  >  the phone's passcode  >  an app passcode (set up with an email code, see AppPasscode.swift)
//
//  The system check sits behind a small protocol so every branch is tested without a screen or a face. The coordinator
//  decides which check applies; when it needs an app-passcode screen it publishes a prompt and waits for the answer, so the
//  caller just does `await authenticate(reason:)` and gets a result.
//
//  Stopping a trace, blocking and reporting never go through this: a safety action must work at once, for anyone holding
//  the phone, however it is locked.
//

import Foundation
import LocalAuthentication
import Combine

enum BiometryKind: Equatable { case faceID, touchID, opticID, other

    var name: String {
        switch self {
        case .faceID: return "Face ID"
        case .touchID: return "Touch ID"
        case .opticID: return "Optic ID"
        case .other: return "biometrics"
        }
    }
}

/// How this phone can prove its owner is here, strongest first.
enum OwnerCheck: Equatable {
    case biometric(BiometryKind)
    case devicePasscode
    case appPasscode
    /// Nothing is set up: the only way forward is to set up an app passcode (after verifying the email).
    case none

    var summary: String {
        switch self {
        case .biometric(let kind): return "\(kind.name) or your phone passcode"
        case .devicePasscode: return "your phone passcode"
        case .appPasscode: return "your ThatWay passcode"
        case .none: return "nothing yet"
        }
    }
}

enum OwnerAuthResult: Equatable {
    case success
    case cancelled
    case failed
    case lockedOut
}

/// What the phone itself can do. (A fake in tests.)
@MainActor
protocol SystemOwnerAuth: AnyObject {
    /// Face ID / Touch ID is enrolled and allowed for this app.
    func biometry() -> BiometryKind?
    /// The phone has a passcode set (which is also what makes Face ID possible).
    func hasDevicePasscode() -> Bool
    /// Asks the system: biometrics, falling back to the phone's passcode. Never called when neither exists.
    func evaluate(reason: String) async -> OwnerAuthResult
}

@MainActor
final class LocalAuthSystem: SystemOwnerAuth {
    func biometry() -> BiometryKind? {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else { return nil }
        switch context.biometryType {
        case .faceID: return .faceID
        case .touchID: return .touchID
        case .opticID: return .opticID
        default: return .other
        }
    }

    func hasDevicePasscode() -> Bool {
        var error: NSError?
        return LAContext().canEvaluatePolicy(.deviceOwnerAuthentication, error: &error)
    }

    func evaluate(reason: String) async -> OwnerAuthResult {
        let context = LAContext()
        do {
            return try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason) ? .success : .failed
        } catch let error as LAError {
            NSLog("TW owner check: LAError %d", error.code.rawValue)
            switch error.code {
            case .userCancel, .appCancel, .systemCancel: return .cancelled
            case .biometryLockout: return .lockedOut
            default: return .failed
            }
        } catch {
            return .failed
        }
    }
}

/// What the screen should be showing, if anything, on behalf of an `authenticate` call that is waiting.
enum OwnerPrompt: Equatable, Identifiable {
    case enterPasscode(reason: String)
    case setUpPasscode(reason: String)

    var id: String {
        switch self {
        case .enterPasscode: return "enter"
        case .setUpPasscode: return "setup"
        }
    }
}

@MainActor
protocol OwnerAuthenticating: AnyObject {
    var method: OwnerCheck { get }
    func authenticate(reason: String) async -> OwnerAuthResult
}

@MainActor
final class OwnerAuthCoordinator: ObservableObject, OwnerAuthenticating {
    @Published private(set) var prompt: OwnerPrompt?

    private let system: SystemOwnerAuth
    private let passcode: AppPasscode
    private let userId: () -> String?
    private var waiting: CheckedContinuation<OwnerAuthResult, Never>?

    init(system: SystemOwnerAuth? = nil, passcode: AppPasscode = AppPasscode(), userId: @escaping () -> String?) {
        self.system = system ?? LocalAuthSystem(); self.passcode = passcode; self.userId = userId
    }

    var appPasscode: AppPasscode { passcode }
    var currentUserId: String? { userId() }

    /// The strongest check this phone offers right now.
    var method: OwnerCheck {
        if let kind = system.biometry() { return .biometric(kind) }
        if system.hasDevicePasscode() { return .devicePasscode }
        if let user = userId(), passcode.isSet(for: user) { return .appPasscode }
        return .none
    }

    /// True when the phone itself has no lock. (An app passcode is then the only protection, and the app keeps saying so.)
    var phoneHasNoLock: Bool { !system.hasDevicePasscode() }

    func authenticate(reason: String) async -> OwnerAuthResult {
        NSLog("TW owner check: method %@", String(describing: method))
        switch method {
        case .biometric, .devicePasscode:
            let result = await system.evaluate(reason: reason)
            NSLog("TW owner check: system answered %@", String(describing: result))
            return result
        case .appPasscode:
            return await present(.enterPasscode(reason: reason))
        case .none:
            return await present(.setUpPasscode(reason: reason))
        }
    }

    private func present(_ next: OwnerPrompt) async -> OwnerAuthResult {
        guard waiting == nil else { return .cancelled }          // one question at a time
        prompt = next
        return await withCheckedContinuation { waiting = $0 }
    }

    /// The prompt screen reports back. (Also called with `.cancelled` when the screen is dismissed any other way.)
    func resolve(_ result: OwnerAuthResult) {
        prompt = nil
        guard let waiting else { return }
        self.waiting = nil
        waiting.resume(returning: result)
    }
}

/// The persistent "your phone has no lock" reminder. It never blocks anything; it only keeps the person informed.
@MainActor
final class ScreenLockStatus: ObservableObject {
    @Published private(set) var phoneHasNoLock = false
    private let system: SystemOwnerAuth

    init(system: SystemOwnerAuth? = nil) {
        self.system = system ?? LocalAuthSystem()
        refresh()
    }

    /// Call whenever the app comes to the front: the person may have just turned a lock on.
    func refresh() { phoneHasNoLock = !system.hasDevicePasscode() }
}

// MARK: - Setting up an app passcode

/// Proves the account's email address by a code (the same Cognito mechanism as sign-up), so a stranger holding an unlocked,
/// lock-less phone cannot set a passcode of their own.
@MainActor
protocol EmailVerifying: AnyObject {
    /// Sends a code to the account's email. Returns where it went, already masked ("j***@g***").
    func sendVerificationCode() async throws -> String?
    func verifyEmailCode(_ code: String) async throws
}

enum PasscodeSetupStep: Equatable {
    case intro
    case emailCode(sentTo: String?)
    case choose
    case confirm
    case done
}

@MainActor
final class AppPasscodeSetup: ObservableObject {
    @Published private(set) var step: PasscodeSetupStep = .intro
    @Published private(set) var message: String?
    @Published private(set) var isWorking = false

    private let email: EmailVerifying
    private let passcode: AppPasscode
    private let userId: String
    private var chosen: String?

    init(email: EmailVerifying, passcode: AppPasscode, userId: String) {
        self.email = email; self.passcode = passcode; self.userId = userId
    }

    func sendCode() async {
        isWorking = true; message = nil
        defer { isWorking = false }
        do {
            let destination = try await email.sendVerificationCode()
            step = .emailCode(sentTo: destination)
        } catch {
            message = error.localizedDescription
        }
    }

    func verify(code: String) async {
        let trimmed = code.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { message = "Enter the code from the email."; return }
        isWorking = true; message = nil
        defer { isWorking = false }
        do {
            try await email.verifyEmailCode(trimmed)
            step = .choose
        } catch {
            message = error.localizedDescription
        }
    }

    func choose(_ pin: String) {
        guard step == .choose else { return }                  // never before the email has been verified
        if let problem = PasscodeRules.problem(with: pin) { message = problem; return }
        chosen = pin; message = nil; step = .confirm
    }

    func confirm(_ pin: String) {
        guard step == .confirm else { return }
        guard let chosen else { step = .choose; return }
        guard pin == chosen else { message = "Those didn't match. Start again."; self.chosen = nil; step = .choose; return }
        guard passcode.set(pin, for: userId) else { message = "Couldn't save that passcode."; return }
        message = nil; step = .done
    }

    /// Back to the start of the choosing (mistyped confirmation, or the person changed their mind).
    func startChoosingAgain() { chosen = nil; message = nil; step = .choose }
}
