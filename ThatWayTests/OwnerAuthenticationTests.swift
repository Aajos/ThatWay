//
//  OwnerAuthenticationTests.swift
//  ThatWayTests
//
//  "Is this really the phone's owner?" — the order of the checks (Face ID/Touch ID, then the phone passcode, then an app
//  passcode set up with an email code), the app passcode's hashing and lockout, and the persistent no-lock reminder.
//

import Testing
import Foundation
@testable import ThatWay

@MainActor
private final class FakeSystem: SystemOwnerAuth {
    var bio: BiometryKind?
    var passcode = true
    var answer: OwnerAuthResult = .success
    private(set) var asked: [String] = []
    func biometry() -> BiometryKind? { bio }
    func hasDevicePasscode() -> Bool { passcode }
    func evaluate(reason: String) async -> OwnerAuthResult { asked.append(reason); return answer }
}

private final class MemoryStore: PasscodeStoring {
    var records: [String: PasscodeRecord] = [:]
    func load(for user: String) -> PasscodeRecord? { records[user] }
    func save(_ record: PasscodeRecord, for user: String) { records[user] = record }
    func clear(for user: String) { records[user] = nil }
}

@MainActor
private final class FakeEmail: EmailVerifying {
    var sendError: Error?
    var verifyError: Error?
    var sent = 0
    var verified: [String] = []
    func sendVerificationCode() async throws -> String? { if let sendError { throw sendError }; sent += 1; return "j***@g***" }
    func verifyEmailCode(_ code: String) async throws { if let verifyError { throw verifyError }; verified.append(code) }
}

/// A passcode with fast hashing and a clock the test controls.
private func passcode(_ store: MemoryStore = MemoryStore(), clock: @escaping () -> Date = Date.init) -> AppPasscode {
    AppPasscode(store: store, now: clock, rounds: 10)
}

struct PasscodeRulesTests {
    @Test func aPasscodeIsExactlySixDigits() {
        #expect(PasscodeRules.isWellFormed("402917"))
        #expect(!PasscodeRules.isWellFormed("40291"))
        #expect(!PasscodeRules.isWellFormed("4029178"))
        #expect(!PasscodeRules.isWellFormed("40a917"))
        #expect(!PasscodeRules.isWellFormed("４０２９１７"), "ASCII digits only")
    }

    @Test func theObviousGuessesAreRefused() {
        for easy in ["000000", "111111", "123456", "654321", "345678", "987654"] {
            #expect(PasscodeRules.isTooEasy(easy), "\(easy)")
            #expect(PasscodeRules.problem(with: easy) != nil)
        }
        #expect(!PasscodeRules.isTooEasy("402917"))
        #expect(PasscodeRules.problem(with: "402917") == nil)
        #expect(PasscodeRules.problem(with: "12")?.contains("6 digits") == true)
    }
}

@MainActor
struct AppPasscodeTests {
    @Test func theRightPasscodeOpensAndTheWrongOneDoesNot() {
        let p = passcode()
        #expect(p.set("402917", for: "me"))
        #expect(p.isSet(for: "me"))
        #expect(p.verify("402917", for: "me") == .correct)
        #expect(p.verify("402918", for: "me") == .wrong(triesLeft: 4))
    }

    @Test func thePasscodeItselfIsNeverStored() {
        let store = MemoryStore()
        let p = passcode(store)
        _ = p.set("402917", for: "me")
        let record = store.records["me"]!
        let everything = record.salt + record.hash + (try! JSONEncoder().encode(record))
        #expect(!String(decoding: everything, as: UTF8.self).contains("402917"))
        #expect(record.hash.count == 32 && record.salt.count == 16)
    }

    @Test func eachAccountAndEachSetHasItsOwnSalt() {
        let store = MemoryStore()
        let p = passcode(store)
        _ = p.set("402917", for: "a"); _ = p.set("402917", for: "b")
        #expect(store.records["a"]!.salt != store.records["b"]!.salt)
        #expect(store.records["a"]!.hash != store.records["b"]!.hash, "the same digits hash differently")
        #expect(p.verify("402917", for: "a") == .correct && p.verify("402917", for: "c") == .notSet)
    }

    @Test func aWeakPasscodeCannotBeSet() {
        let p = passcode()
        #expect(!p.set("123456", for: "me") && !p.isSet(for: "me"))
        #expect(!p.set("12", for: "me"))
    }

    @Test func fiveWrongTriesLockItForLongerEachTime() {
        var now = Date(timeIntervalSince1970: 1_800_000_000)
        let p = passcode(clock: { now })
        _ = p.set("402917", for: "me")
        for left in [4, 3, 2, 1] { #expect(p.verify("000001", for: "me") == .wrong(triesLeft: left)) }
        guard case .lockedOut(let until) = p.verify("000001", for: "me") else { Issue.record("should be locked"); return }
        #expect(until == now.addingTimeInterval(300))
        #expect(p.verify("402917", for: "me") == .lockedOut(until: until), "even the right one is refused while locked")
        now = until.addingTimeInterval(1)
        guard case .lockedOut(let longer) = p.verify("000001", for: "me") else { Issue.record("sixth wrong try locks again"); return }
        #expect(longer == now.addingTimeInterval(600), "twice as long")
        now = longer.addingTimeInterval(1)
        #expect(p.verify("402917", for: "me") == .correct)
        #expect(p.verify("000001", for: "me") == .wrong(triesLeft: 4), "a right answer resets the count")
    }

    @Test func lockTimesDoubleAndStopAtAnHour() {
        #expect(AppPasscode.lockDuration(failures: 4) == 0)
        #expect(AppPasscode.lockDuration(failures: 5) == 300)
        #expect(AppPasscode.lockDuration(failures: 6) == 600)
        #expect(AppPasscode.lockDuration(failures: 7) == 1200)
        #expect(AppPasscode.lockDuration(failures: 30) == 3600)
    }

    @Test func comparingHashesIsExactAndRefusesEmpty() {
        #expect(AppPasscode.constantTimeEqual(Data([1, 2, 3]), Data([1, 2, 3])))
        #expect(!AppPasscode.constantTimeEqual(Data([1, 2, 3]), Data([1, 2, 4])))
        #expect(!AppPasscode.constantTimeEqual(Data([1, 2]), Data([1, 2, 3])))
        #expect(!AppPasscode.constantTimeEqual(Data(), Data()), "an empty hash never matches")
    }

    @Test func clearingRemovesIt() {
        let p = passcode()
        _ = p.set("402917", for: "me")
        p.clear(for: "me")
        #expect(!p.isSet(for: "me") && p.verify("402917", for: "me") == .notSet)
    }
}

@MainActor
struct OwnerCoordinatorTests {
    private func make(bio: BiometryKind? = nil, passcode hasPhone: Bool = true, appPin: Bool = false) -> (OwnerAuthCoordinator, FakeSystem, AppPasscode) {
        let system = FakeSystem(); system.bio = bio; system.passcode = hasPhone
        let pin = passcode()
        if appPin { _ = pin.set("402917", for: "me") }
        return (OwnerAuthCoordinator(system: system, passcode: pin, userId: { "me" }), system, pin)
    }

    @Test func theOrderIsBiometricsThenPhonePasscodeThenAppPasscodeThenNothing() {
        #expect(make(bio: .faceID).0.method == .biometric(.faceID))
        #expect(make(bio: .touchID).0.method == .biometric(.touchID))
        #expect(make(bio: nil, passcode: true).0.method == .devicePasscode)
        #expect(make(bio: nil, passcode: false, appPin: true).0.method == .appPasscode)
        #expect(make(bio: nil, passcode: false, appPin: false).0.method == .none)
        #expect(make(bio: .faceID, passcode: true, appPin: true).0.method == .biometric(.faceID), "the strongest wins")
    }

    @Test func aPhoneWithALockUsesTheSystemCheckAndNeverAnAppScreen() async {
        let (owner, system, _) = make(bio: .faceID)
        let result = await owner.authenticate(reason: "Allow sam")
        #expect(result == .success && system.asked == ["Allow sam"] && owner.prompt == nil)
        system.answer = .cancelled
        #expect(await owner.authenticate(reason: "x") == .cancelled)
        system.answer = .failed
        #expect(await owner.authenticate(reason: "x") == .failed)
    }

    @Test func aPhoneWithOnlyAnAppPasscodeAsksForIt() async {
        let (owner, system, _) = make(passcode: false, appPin: true)
        let pending = Task { await owner.authenticate(reason: "Allow sam") }
        for _ in 0..<10 where owner.prompt == nil { await Task.yield() }
        #expect(owner.prompt == .enterPasscode(reason: "Allow sam"))
        owner.resolve(.success)
        #expect(await pending.value == .success)
        #expect(owner.prompt == nil && system.asked.isEmpty, "the system was never asked")
    }

    @Test func aPhoneWithNothingIsSentToSetUpAPasscodeFirst() async {
        let (owner, _, _) = make(passcode: false)
        let pending = Task { await owner.authenticate(reason: "Allow sam") }
        for _ in 0..<10 where owner.prompt == nil { await Task.yield() }
        #expect(owner.prompt == .setUpPasscode(reason: "Allow sam"))
        owner.resolve(.cancelled)
        #expect(await pending.value == .cancelled, "closing the setup allows nothing")
    }

    @Test func onlyOneQuestionIsAskedAtATime() async {
        let (owner, _, _) = make(passcode: false, appPin: true)
        let first = Task { await owner.authenticate(reason: "one") }
        for _ in 0..<10 where owner.prompt == nil { await Task.yield() }
        let second = await owner.authenticate(reason: "two")
        #expect(second == .cancelled)
        owner.resolve(.success)
        #expect(await first.value == .success)
    }

    @Test func resolvingWithNothingWaitingIsHarmless() {
        let (owner, _, _) = make(bio: .faceID)
        owner.resolve(.cancelled)
        #expect(owner.prompt == nil)
    }

    @Test func thePhoneHavingNoLockIsReported() {
        #expect(make(passcode: false).0.phoneHasNoLock)
        #expect(!make(passcode: true).0.phoneHasNoLock)
    }
}

@MainActor
struct ScreenLockStatusTests {
    @Test func theReminderFollowsWhetherThePhoneHasALock() {
        let system = FakeSystem(); system.passcode = false
        let status = ScreenLockStatus(system: system)
        #expect(status.phoneHasNoLock)
        system.passcode = true
        #expect(status.phoneHasNoLock, "not until it is re-checked")
        status.refresh()
        #expect(!status.phoneHasNoLock, "gone as soon as the person turns a lock on")
    }
}

@MainActor
struct PasscodeSetupTests {
    private func make() -> (AppPasscodeSetup, FakeEmail, AppPasscode) {
        let email = FakeEmail()
        let pin = passcode()
        return (AppPasscodeSetup(email: email, passcode: pin, userId: "me"), email, pin)
    }

    @Test func aPasscodeCannotBeChosenBeforeTheEmailIsVerified() async {
        let (setup, email, pin) = make()
        #expect(setup.step == .intro)
        setup.choose("402917"); setup.confirm("402917")
        #expect(setup.step == .intro && !pin.isSet(for: "me"), "a stranger cannot skip the email step")
        await setup.sendCode()
        #expect(setup.step == .emailCode(sentTo: "j***@g***") && email.sent == 1)
        setup.choose("402917"); setup.confirm("402917")
        #expect(setup.step == .emailCode(sentTo: "j***@g***") && !pin.isSet(for: "me"), "sending the code is not verifying it")
        await setup.verify(code: "123456")
        #expect(setup.step == .choose && email.verified == ["123456"])
    }

    @Test func aWrongCodeStaysOnTheCodeStepWithTheReason() async {
        let (setup, email, _) = make()
        await setup.sendCode()
        email.verifyError = AuthError.cognito(type: "CodeMismatchException", message: "x")
        await setup.verify(code: "000000")
        #expect(setup.step == .emailCode(sentTo: "j***@g***"))
        #expect(setup.message?.contains("isn't right") == true)
    }

    @Test func aCodeThatCouldNotBeSentSaysSoAndStaysAtTheStart() async {
        let (setup, email, _) = make()
        email.sendError = AuthError.cognito(type: "LimitExceededException", message: "x")
        await setup.sendCode()
        #expect(setup.step == .intro && setup.message?.contains("Too many attempts") == true)
    }

    @Test func choosingThenConfirmingSetsIt() async {
        let (setup, _, pin) = make()
        await setup.sendCode(); await setup.verify(code: "123456")
        setup.choose("402917")
        #expect(setup.step == .confirm)
        setup.confirm("402917")
        #expect(setup.step == .done && pin.isSet(for: "me"))
        #expect(pin.verify("402917", for: "me") == .correct)
    }

    @Test func aMismatchStartsAgainAndSetsNothing() async {
        let (setup, _, pin) = make()
        await setup.sendCode(); await setup.verify(code: "123456")
        setup.choose("402917")
        setup.confirm("402918")
        #expect(setup.step == .choose && !pin.isSet(for: "me") && setup.message?.contains("didn't match") == true)
    }

    @Test func aWeakChoiceIsRefusedWithAReason() async {
        let (setup, _, _) = make()
        await setup.sendCode(); await setup.verify(code: "123456")
        setup.choose("123456")
        #expect(setup.step == .choose && setup.message?.contains("too easy") == true)
    }

    @Test func anEmptyCodeIsNotSentToTheServer() async {
        let (setup, email, _) = make()
        await setup.sendCode()
        await setup.verify(code: "  ")
        #expect(email.verified.isEmpty && setup.message != nil)
    }
}
