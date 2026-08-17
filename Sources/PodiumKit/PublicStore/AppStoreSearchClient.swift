import Foundation

public struct StoreApp: Decodable, Sendable, Equatable {
    public let trackId: Int
    public let trackName: String
    public let averageUserRating: Double?
    public let userRatingCount: Int?
    public let artworkUrl100: String?
}

public struct AppStoreSearchClient: Sendable {
    let session: URLSession
    public init(session: URLSession = .shared) { self.session = session }

    private struct SearchResponse: Decodable {
        let results: [StoreApp]
    }

    /// 1-based position of `appId` in App Store search results for `term`, or nil if not in the top `limit`.
    public func rank(ofApp appId: Int, term: String, country: String, limit: Int = 200) async throws -> Int? {
        var components = URLComponents(string: "https://itunes.apple.com/search")!
        components.queryItems = [
            URLQueryItem(name: "term", value: term),
            URLQueryItem(name: "country", value: country),
            URLQueryItem(name: "entity", value: "software"),
            URLQueryItem(name: "limit", value: String(limit)),
        ]
        let results = try await fetch(components.url!).results
        guard let index = results.firstIndex(where: { $0.trackId == appId }) else { return nil }
        return index + 1
    }

    public func lookup(appId: Int, country: String) async throws -> StoreApp? {
        var components = URLComponents(string: "https://itunes.apple.com/lookup")!
        components.queryItems = [
            URLQueryItem(name: "id", value: String(appId)),
            URLQueryItem(name: "country", value: country),
        ]
        return try await fetch(components.url!).results.first
    }

    public func search(term: String, country: String, limit: Int = 25) async throws -> [StoreApp] {
        var components = URLComponents(string: "https://itunes.apple.com/search")!
        components.queryItems = [
            URLQueryItem(name: "term", value: term),
            URLQueryItem(name: "country", value: country),
            URLQueryItem(name: "entity", value: "software"),
            URLQueryItem(name: "limit", value: String(limit)),
        ]
        return try await fetch(components.url!).results
    }

    private func fetch(_ url: URL) async throws -> SearchResponse {
        let (data, response) = try await session.data(from: url)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else {
            throw PodiumError.http(status: status, body: String(decoding: data, as: UTF8.self))
        }
        do {
            return try JSONDecoder().decode(SearchResponse.self, from: data)
        } catch {
            throw PodiumError.decoding("SearchResponse: \(error)")
        }
    }
}
