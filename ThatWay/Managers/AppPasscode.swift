//
//  AppPasscode.swift
//  ThatWay
//
//  The last-resort lock. Before anyone can allow a friend to trace them, the app checks that it is really the phone's owner:
//    1. Face ID or Touch ID (best),
//    2. the phone's own passcode,
//    3. only if the phone has neither: an APP passcode, set up inside ThatWay after the account's email address has been
//       verified with a code. (Someone who has merely picked up an unlocked phone with no lock must not be able to set one.)
//  The app passcode is six digits. It is never stored: only a salted, slow hash of it (PBKDF2-HMAC-SHA256) lives in the
//  Keychain, per account, and five wrong tries lock it for a while, longer each time.
//
//  Nothing here blocks the app from working: it guards the one decision that matters (letting someone see where you are).
//

import Foundation
import Security
import CommonCrypto

// MARK: - The rules for a passcode

enum PasscodeRules {
    static let length = 6

    static func isWellFormed(_ pin: String) -> Bool {
        pin.count == length && pin.allSatisfy { $0.isASCII && $0.isNumber }
    }

    /// Refuses the guesses everyone tries first: one repeated digit, and straight runs up or down (123456, 654321).
    static func isTooEasy(_ pin: String) -> Bool {
        let digits = pin.compactMap { $0.wholeNumberValue }
        guard digits.count == length else { return true }
        if Set(digits).count == 1 { return true }
        let steps = zip(digits, digits.dropFirst()).map { $1 - $0 }
        return steps.allSatisfy { $0 == 1 } || steps.allSatisfy { $0 == -1 }
    }

    static func problem(with pin: String) -> String? {
        if !isWellFormed(pin) { return "Use exactly \(length) digits." }
        if isTooEasy(pin) { return "That one is too easy to guess. Avoid repeats and runs like 123456." }
        return nil
    }
}

// MARK: - Storage

/// What is kept for one account. The passcode itself is never in here.
struct PasscodeRecord: Codable, Equatable {
    var salt: Data
    var hash: Data
    var rounds: Int
    var failures: Int
    var lockedUntil: Date?
    var setAt: Date
}

protocol PasscodeStoring: AnyObject {
    func load(for user: String) -> PasscodeRecord?
    func save(_ record: PasscodeRecord, for user: String)
    func clear(for user: String)
}

final class KeychainPasscodeStore: PasscodeStoring {
    private func key(_ user: String) -> String { "appPasscode.\(user)" }

    func load(for user: String) -> PasscodeRecord? {
        guard let text = KeychainStore.get(key(user)), let data = text.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(PasscodeRecord.self, from: data)
    }

    func save(_ record: PasscodeRecord, for user: String) {
        guard let data = try? JSONEncoder().encode(record), let text = String(data: data, encoding: .utf8) else { return }
        KeychainStore.set(text, for: key(user))
    }

    func clear(for user: String) { KeychainStore.delete(key(user)) }
}

// MARK: - The check itself

enum PasscodeCheck: Equatable {
    case correct
    case wrong(triesLeft: Int)
    case lockedOut(until: Date)
    case notSet
}

/// Hashing and the lockout policy. Pure apart from the store and the clock, so it is tested without a screen.
final class AppPasscode {
    static let triesBeforeLock = 5
    static let defaultRounds = 150_000

    private let store: PasscodeStoring
    private let now: () -> Date
    private let rounds: Int
    private let random: (Int) -> Data

    init(store: PasscodeStoring = KeychainPasscodeStore(), now: @escaping () -> Date = Date.init,
         rounds: Int = AppPasscode.defaultRounds, random: @escaping (Int) -> Data = AppPasscode.secureRandom) {
        self.store = store; self.now = now; self.rounds = rounds; self.random = random
    }

    func isSet(for user: String) -> Bool { store.load(for: user) != nil }
    func clear(for user: String) { store.clear(for: user) }

    /// Lock time after `failures` wrong tries in a row: 5 minutes at the fifth, doubling each time, never more than an hour.
    static func lockDuration(failures: Int) -> TimeInterval {
        guard failures >= triesBeforeLock else { return 0 }
        return min(3600, 300 * pow(2, Double(failures - triesBeforeLock)))
    }

    /// Sets (or replaces) the passcode. The caller has already verified the account's email.
    func set(_ pin: String, for user: String) -> Bool {
        guard PasscodeRules.problem(with: pin) == nil else { return false }
        let salt = random(16)
        store.save(PasscodeRecord(salt: salt, hash: Self.derive(pin, salt: salt, rounds: rounds), rounds: rounds, failures: 0, lockedUntil: nil, setAt: now()), for: user)
        return true
    }

    func verify(_ pin: String, for user: String) -> PasscodeCheck {
        guard var record = store.load(for: user) else { return .notSet }
        if let until = record.lockedUntil, until > now() { return .lockedOut(until: until) }
        let attempt = Self.derive(pin, salt: record.salt, rounds: record.rounds)
        if Self.constantTimeEqual(attempt, record.hash) {
            record.failures = 0; record.lockedUntil = nil
            store.save(record, for: user)
            return .correct
        }
        record.failures += 1
        let lock = Self.lockDuration(failures: record.failures)
        if lock > 0 {
            let until = now().addingTimeInterval(lock)
            record.lockedUntil = until
            store.save(record, for: user)
            return .lockedOut(until: until)
        }
        store.save(record, for: user)
        return .wrong(triesLeft: Self.triesBeforeLock - record.failures)
    }

    // MARK: Primitives

    static func derive(_ pin: String, salt: Data, rounds: Int) -> Data {
        var out = [UInt8](repeating: 0, count: 32)
        let status = salt.withUnsafeBytes { saltBytes in
            CCKeyDerivationPBKDF(CCPBKDFAlgorithm(kCCPBKDF2), pin, pin.utf8.count,
                                 saltBytes.bindMemory(to: UInt8.self).baseAddress, salt.count,
                                 CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256), UInt32(rounds), &out, out.count)
        }
        return status == Int32(kCCSuccess) ? Data(out) : Data()
    }

    static func constantTimeEqual(_ a: Data, _ b: Data) -> Bool {
        guard a.count == b.count, !a.isEmpty else { return false }
        var difference: UInt8 = 0
        for (x, y) in zip(a, b) { difference |= x ^ y }
        return difference == 0
    }

    static func secureRandom(_ count: Int) -> Data {
        var bytes = [UInt8](repeating: 0, count: count)
        _ = SecRandomCopyBytes(kSecRandomDefault, count, &bytes)
        return Data(bytes)
    }
}
