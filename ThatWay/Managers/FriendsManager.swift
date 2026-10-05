//
//  FriendsManager.swift
//  ThatWay
//
//  REST client for the live friends API (API Gateway + Lambda + DynamoDB — see the backend
//  brief pasted into this project's notes, and backend/SETUP.md for the original provisioning
//  steps), following the same plain URLSession pattern as RoutingManager. Every request carries
//  the Cognito *access* token from AuthManager as a bearer token — the API Gateway JWT
//  authorizer validates access tokens here, not ID tokens.
//

import Foundation
import Combine

/// `/friends/search` returns a plain user hit, not a relationship record — it has no
/// `status`/`requestedAt`/`acceptedAt`, so it's kept separate from `Friend` rather than faking
/// those fields.
struct UserSearchResult: Identifiable, Decodable, Equatable {
    let id: String
    let username: String
}

@MainActor
final class FriendsManager: ObservableObject {
    @Published var friends: [Friend] = []
    @Published var incomingRequests: [Friend] = []
    @Published var outgoingRequests: [Friend] = []
    @Published var searchResults: [UserSearchResult] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let auth: AuthManager
    private var cancellables = Set<AnyCancellable>()

    init(auth: AuthManager) {
        self.auth = auth
        auth.$authState.sink { [weak self] state in
            guard let self else { return }
            if state == .signedIn {
                Task { await self.refresh() }
            } else if state == .signedOut {
                self.friends = []
                self.incomingRequests = []
                self.outgoingRequests = []
                self.searchResults = []
            }
        }.store(in: &cancellables)
    }

    func refresh() async {
        isLoading = true; errorMessage = nil
        defer { isLoading = false }
        do {
            async let accepted: [Friend] = request(method: "GET", path: "/friends?status=ACCEPTED")
            async let incoming: [Friend] = request(method: "GET", path: "/friends?status=INCOMING")
            async let outgoing: [Friend] = request(method: "GET", path: "/friends?status=PENDING")
            (friends, incomingRequests, outgoingRequests) = try await (accepted, incoming, outgoing)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func searchUsers(query: String) async {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { searchResults = []; return }
        errorMessage = nil
        do {
            var components = URLComponents()
            components.queryItems = [URLQueryItem(name: "username", value: trimmed)]
            let encodedQuery = components.percentEncodedQuery.map { "?\($0)" } ?? ""
            searchResults = try await request(method: "GET", path: "/friends/search\(encodedQuery)") as [UserSearchResult]
        } catch {
            errorMessage = error.localizedDescription
            searchResults = []
        }
    }

    @discardableResult
    func sendRequest(to userId: String) async -> Bool {
        errorMessage = nil
        do {
            let _: EmptyResponse = try await request(method: "POST", path: "/friends/request", body: ["friendId": userId])
            await refresh()
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    /// `requesterId` is the other person's id — only the recipient of their incoming request
    /// can respond to it.
    func respond(to requesterId: String, accept: Bool) async {
        errorMessage = nil
        do {
            let _: EmptyResponse = try await request(method: "POST", path: "/friends/respond", body: [
                "requesterId": requesterId,
                "action": accept ? "accept" : "reject",
            ])
            await refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func removeFriend(id: String) async {
        errorMessage = nil
        do {
            let _: EmptyResponse = try await request(method: "DELETE", path: "/friends/\(id)")
            await refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func request<T: Decodable>(method: String, path: String, body: [String: Any]? = nil, allowRefresh: Bool = true) async throws -> T {
        guard let url = URL(string: Config.apiBaseURL + path) else { throw FriendsError.badURL }
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = method
        if let token = auth.bearerToken {
            urlRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        if let body {
            urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
            urlRequest.httpBody = try JSONSerialization.data(withJSONObject: body)
        }

        let (data, response) = try await URLSession.shared.data(for: urlRequest)
        guard let http = response as? HTTPURLResponse else { throw FriendsError.unreachable }

        // Access tokens last 60 minutes; a 401 here almost always means it just expired.
        // Refresh once and retry the same call before surfacing an error.
        if http.statusCode == 401, allowRefresh, await auth.refreshAccessToken() {
            return try await request(method: method, path: path, body: body, allowRefresh: false)
        }

        guard 200..<300 ~= http.statusCode else {
            let decoded = try? JSONDecoder().decode(ErrorBody.self, from: data)
            let message = decoded?.error ?? decoded?.message
            throw FriendsError.server(message ?? "The friends service couldn't be reached.")
        }
        return try JSONDecoder().decode(T.self, from: data)
    }
}

private struct EmptyResponse: Decodable {}
private struct ErrorBody: Decodable { let error: String?; let message: String? }

enum FriendsError: LocalizedError {
    case badURL
    case unreachable
    case server(String)

    var errorDescription: String? {
        switch self {
        case .badURL, .unreachable: return "The friends service couldn't be reached."
        case .server(let message): return message
        }
    }
}
