//
//  SafetyManager.swift
//  ThatWay
//
//  Blocking, reporting and closing an account: the parts of the app that exist to protect a person from another person, or
//  from the app. None of it is throttled by the app, none of it needs the owner check (it must work at once for whoever is
//  holding the phone), and none of it tells the other person anything.
//
//    block      removes the friendship, every permission in both directions and any last position, and hides each from the other
//    report     is stored for a person to read; it never carries a location
//    delete     removes the account and everything linked to it (the server deletes, then the app signs out)
//    deactivate removes everything social but keeps the sign-in and the plan; reactivating brings the profile back, not the friends
//

import Foundation
import Combine

struct BlockedUser: Decodable, Identifiable, Equatable {
    let userId: String
    let username: String?
    var id: String { userId }
    var displayName: String { username ?? "Blocked person" }
}

struct AccountStatus: Decodable, Equatable {
    /// "active" or "deactivated"
    let status: String
    let deactivatedAt: Double?
    let deletesAt: Double?
    var isDeactivated: Bool { status == "deactivated" }
}

enum ReportCategory: String, CaseIterable, Identifiable {
    case unwantedTracing = "unwanted_tracing"
    case harassment, threat, impersonation, other
    var id: String { rawValue }

    var title: String {
        switch self {
        case .unwantedTracing: return "Tracing or following me when I didn’t want it"
        case .harassment: return "Harassment or unwanted contact"
        case .threat: return "Threats, or I feel unsafe"
        case .impersonation: return "Pretending to be someone else"
        case .other: return "Something else"
        }
    }

    /// The one category that should put "if you are in danger, call" in front of the person.
    var isUrgent: Bool { self == .threat }
}

@MainActor
protocol SafetyAPI: AnyObject {
    func blockUser(id: String) async throws
    func unblockUser(id: String) async throws
    func blockedUsers() async throws -> [BlockedUser]
    func reportUser(id: String, category: String, details: String) async throws
    func accountStatus() async throws -> AccountStatus
    func deleteAccount() async throws
    func deactivateAccount() async throws
    func reactivateAccount() async throws
}

@MainActor
final class SafetyManager: ObservableObject {
    @Published private(set) var blocked: [BlockedUser] = []
    @Published private(set) var account: AccountStatus?
    @Published private(set) var isWorking = false
    @Published var errorMessage: String?
    @Published var notice: String?

    private let api: SafetyAPI
    /// After a block: refresh the friends list and the trace sync (the server has already removed everything).
    var afterBlock: ((String) async -> Void)?
    /// After the server confirms a deletion or a deactivation: sign out and clear what is kept on this phone.
    var afterAccountClosed: ((_ deleted: Bool) -> Void)?

    init(api: SafetyAPI) { self.api = api }

    /// A signed-in person who deactivated and came back must choose what happens next before anything else.
    var needsReactivation: Bool { account?.isDeactivated == true }

    func reset() { blocked = []; account = nil; errorMessage = nil; notice = nil; isWorking = false }

    // MARK: Blocking

    @discardableResult
    func block(_ friend: Friend) async -> Bool {
        errorMessage = nil
        do {
            try await api.blockUser(id: friend.id)
            blocked.removeAll { $0.userId == friend.id }
            blocked.append(BlockedUser(userId: friend.id, username: friend.username))
            await afterBlock?(friend.id)
            return true
        } catch {
            errorMessage = "We couldn’t block \(friend.username) just now. Check your connection and try again: they are not blocked yet."
            return false
        }
    }

    func unblock(_ user: BlockedUser) async {
        errorMessage = nil
        do {
            try await api.unblockUser(id: user.userId)
            blocked.removeAll { $0.userId == user.userId }
            notice = "\(user.displayName) is unblocked. You are not friends again unless one of you sends a new request."
        } catch {
            errorMessage = "We couldn’t unblock \(user.displayName) just now. Try again."
        }
    }

    func loadBlocked() async {
        if let list = try? await api.blockedUsers() { blocked = list }
    }

    // MARK: Reporting

    /// Files a report. `alsoBlock` blocks in the same go (the report is sent first, so a failed block never loses it).
    @discardableResult
    func report(_ friend: Friend, category: ReportCategory, details: String, alsoBlock: Bool) async -> Bool {
        errorMessage = nil
        do {
            try await api.reportUser(id: friend.id, category: category.rawValue, details: String(details.prefix(500)))
        } catch {
            errorMessage = "We couldn’t send your report just now. Check your connection and try again."
            return false
        }
        notice = "Your report was sent."
        if alsoBlock { await block(friend) }
        return true
    }

    // MARK: The account

    func checkAccount() async {
        if let status = try? await api.accountStatus() { account = status }
    }

    func reactivate() async {
        errorMessage = nil; isWorking = true
        defer { isWorking = false }
        do {
            try await api.reactivateAccount()
            account = AccountStatus(status: "active", deactivatedAt: nil, deletesAt: nil)
        } catch {
            errorMessage = "We couldn’t reactivate your account just now. Try again."
        }
    }

    /// Deletes everything. The app signs out only after the server has said it is done, so a failure leaves the person
    /// signed in and able to try again (nothing is half-promised).
    func deleteAccount() async {
        errorMessage = nil; isWorking = true
        defer { isWorking = false }
        do {
            try await api.deleteAccount()
            afterAccountClosed?(true)
        } catch {
            errorMessage = "We couldn’t finish deleting your account. Nothing has been signed out: check your connection and try again."
        }
    }

    func deactivateAccount() async {
        errorMessage = nil; isWorking = true
        defer { isWorking = false }
        do {
            try await api.deactivateAccount()
            afterAccountClosed?(false)
        } catch {
            errorMessage = "We couldn’t deactivate your account. Check your connection and try again."
        }
    }
}

// MARK: - Network

extension FriendsManager: SafetyAPI {
    func blockUser(id: String) async throws {
        let _: EmptyResponse = try await request(method: "POST", path: "/blocks", body: ["userId": id])
    }

    func unblockUser(id: String) async throws {
        let _: EmptyResponse = try await request(method: "DELETE", path: "/blocks/\(id)")
    }

    func blockedUsers() async throws -> [BlockedUser] {
        try await request(method: "GET", path: "/blocks")
    }

    func reportUser(id: String, category: String, details: String) async throws {
        let _: EmptyResponse = try await request(method: "POST", path: "/reports", body: ["userId": id, "category": category, "details": details])
    }

    func accountStatus() async throws -> AccountStatus {
        try await request(method: "GET", path: "/account")
    }

    func deleteAccount() async throws {
        let _: EmptyResponse = try await request(method: "POST", path: "/account/delete", body: ["confirmed": true])
    }

    func deactivateAccount() async throws {
        let _: EmptyResponse = try await request(method: "POST", path: "/account/deactivate", body: ["confirmed": true])
    }

    func reactivateAccount() async throws {
        let _: EmptyResponse = try await request(method: "POST", path: "/account/reactivate")
    }
}
