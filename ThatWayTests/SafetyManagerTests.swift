//
//  SafetyManagerTests.swift
//  ThatWayTests
//
//  Blocking, reporting and closing an account: a failure is always said plainly and never leaves the person believing
//  something happened that did not; destructive steps sign out only after the server confirms; reports go out before any block.
//

import Testing
import Foundation
@testable import ThatWay

@MainActor
private final class FakeSafetyAPI: SafetyAPI {
    var calls: [String] = []
    var fail: Set<String> = []
    var blockedList: [BlockedUser] = []
    var status = AccountStatus(status: "active", deactivatedAt: nil, deletesAt: nil)

    private func run(_ name: String) throws { calls.append(name); if fail.contains(name) { throw FriendsError.unreachable } }
    func blockUser(id: String) async throws { try run("block:\(id)") }
    func unblockUser(id: String) async throws { try run("unblock:\(id)") }
    func blockedUsers() async throws -> [BlockedUser] { try run("blocked"); return blockedList }
    func reportUser(id: String, category: String, details: String) async throws { try run("report:\(id):\(category):\(details.count)") }
    func accountStatus() async throws -> AccountStatus { try run("status"); return status }
    func deleteAccount() async throws { try run("delete") }
    func deactivateAccount() async throws { try run("deactivate") }
    func reactivateAccount() async throws { try run("reactivate") }
}

@MainActor
struct SafetyManagerTests {
    let sam = Friend(id: "sam-id", username: "sam", status: "ACCEPTED", requestedAt: nil, acceptedAt: nil)

    // MARK: Blocking

    @Test func blockingTellsTheServerListsThemAndRefreshesTheApp() async {
        let api = FakeSafetyAPI()
        let safety = SafetyManager(api: api)
        var refreshed: [String] = []
        safety.afterBlock = { refreshed.append($0) }
        #expect(await safety.block(sam))
        #expect(api.calls == ["block:sam-id"])
        #expect(safety.blocked.map(\.displayName) == ["sam"])
        #expect(refreshed == ["sam-id"])
    }

    @Test func blockingTwiceListsThemOnce() async {
        let safety = SafetyManager(api: FakeSafetyAPI())
        _ = await safety.block(sam); _ = await safety.block(sam)
        #expect(safety.blocked.count == 1)
    }

    @Test func aFailedBlockSaysTheyAreNotBlockedYet() async {
        let api = FakeSafetyAPI(); api.fail = ["block:sam-id"]
        let safety = SafetyManager(api: api)
        var refreshed = 0
        safety.afterBlock = { _ in refreshed += 1 }
        #expect(await safety.block(sam) == false)
        #expect(safety.blocked.isEmpty && refreshed == 0)
        #expect(safety.errorMessage?.contains("not blocked yet") == true)
    }

    @Test func unblockingRemovesThemAndSaysTheFriendshipDoesNotComeBack() async {
        let api = FakeSafetyAPI()
        let safety = SafetyManager(api: api)
        _ = await safety.block(sam)
        await safety.unblock(safety.blocked[0])
        #expect(safety.blocked.isEmpty && api.calls.last == "unblock:sam-id")
        #expect(safety.notice?.contains("not friends again") == true)
    }

    @Test func theBlockedListComesFromTheServerWithNames() async {
        let api = FakeSafetyAPI(); api.blockedList = [BlockedUser(userId: "a", username: "alex"), BlockedUser(userId: "b", username: nil)]
        let safety = SafetyManager(api: api)
        await safety.loadBlocked()
        #expect(safety.blocked.map(\.displayName) == ["alex", "Blocked person"])
    }

    // MARK: Reporting

    @Test func aReportIsSentWithItsCategoryAndATrimmedNote() async {
        let api = FakeSafetyAPI()
        let safety = SafetyManager(api: api)
        #expect(await safety.report(sam, category: .unwantedTracing, details: String(repeating: "x", count: 900), alsoBlock: false))
        #expect(api.calls == ["report:sam-id:unwanted_tracing:500"])
        #expect(safety.notice == "Your report was sent.")
    }

    @Test func alsoBlockingSendsTheReportFirst() async {
        let api = FakeSafetyAPI()
        let safety = SafetyManager(api: api)
        _ = await safety.report(sam, category: .threat, details: "", alsoBlock: true)
        #expect(api.calls == ["report:sam-id:threat:0", "block:sam-id"])
    }

    @Test func aReportThatCannotBeSentIsNeverPretendedAndNothingIsBlocked() async {
        let api = FakeSafetyAPI(); api.fail = ["report:sam-id:harassment:0"]
        let safety = SafetyManager(api: api)
        #expect(await safety.report(sam, category: .harassment, details: "", alsoBlock: true) == false)
        #expect(api.calls == ["report:sam-id:harassment:0"], "no block was attempted behind a failed report")
        #expect(safety.notice == nil && safety.errorMessage != nil)
    }

    @Test func onlyThreatsAreUrgent() {
        #expect(ReportCategory.allCases.filter(\.isUrgent) == [.threat])
        #expect(ReportCategory(rawValue: "unwanted_tracing") == .unwantedTracing, "the wire names match the server's list")
        #expect(Set(ReportCategory.allCases.map(\.rawValue)) == ["unwanted_tracing", "harassment", "threat", "impersonation", "other"])
    }

    // MARK: The account

    @Test func deletingSignsOutOnlyAfterTheServerConfirms() async {
        let api = FakeSafetyAPI()
        let safety = SafetyManager(api: api)
        var closed: [Bool] = []
        safety.afterAccountClosed = { closed.append($0) }
        await safety.deleteAccount()
        #expect(api.calls == ["delete"] && closed == [true])
    }

    @Test func aDeleteThatFailsLeavesThePersonSignedInAndSaysSo() async {
        let api = FakeSafetyAPI(); api.fail = ["delete"]
        let safety = SafetyManager(api: api)
        var closed = 0
        safety.afterAccountClosed = { _ in closed += 1 }
        await safety.deleteAccount()
        #expect(closed == 0)
        #expect(safety.errorMessage?.contains("Nothing has been signed out") == true)
    }

    @Test func deactivatingIsNotDeleting() async {
        let api = FakeSafetyAPI()
        let safety = SafetyManager(api: api)
        var closed: [Bool] = []
        safety.afterAccountClosed = { closed.append($0) }
        await safety.deactivateAccount()
        #expect(api.calls == ["deactivate"] && closed == [false])
    }

    @Test func aDeactivatedAccountMustChooseBeforeAnythingElse() async {
        let api = FakeSafetyAPI(); api.status = AccountStatus(status: "deactivated", deactivatedAt: 100, deletesAt: 31_536_100)
        let safety = SafetyManager(api: api)
        #expect(safety.needsReactivation == false)
        await safety.checkAccount()
        #expect(safety.needsReactivation)
        await safety.reactivate()
        #expect(api.calls.last == "reactivate" && safety.needsReactivation == false)
    }

    @Test func aFailedReactivationKeepsThemOnTheChoice() async {
        let api = FakeSafetyAPI(); api.status = AccountStatus(status: "deactivated", deactivatedAt: 100, deletesAt: 200); api.fail = ["reactivate"]
        let safety = SafetyManager(api: api)
        await safety.checkAccount(); await safety.reactivate()
        #expect(safety.needsReactivation && safety.errorMessage != nil)
    }

    @Test func resettingForgetsEverything() async {
        let safety = SafetyManager(api: FakeSafetyAPI())
        _ = await safety.block(sam)
        safety.reset()
        #expect(safety.blocked.isEmpty && safety.account == nil && safety.errorMessage == nil)
    }
}
