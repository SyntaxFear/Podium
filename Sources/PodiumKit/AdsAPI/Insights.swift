import Foundation

public struct SearchTermPopularityRequest: Encodable, Sendable {
    public enum Granularity: String, Encodable, Sendable {
        case weekly = "WEEKLY"
        case monthly = "MONTHLY"
    }
    public var countryOrRegion: String
    public var genreId: Int?
    public var granularity: Granularity

    public init(countryOrRegion: String, genreId: Int? = nil, granularity: Granularity = .weekly) {
        self.countryOrRegion = countryOrRegion
        self.genreId = genreId
        self.granularity = granularity
    }
}

public struct SearchTermPopularity: Decodable, Sendable, Equatable {
    public let searchTerm: String
    public let rank: Int
    public let popularity: Int
}

public struct Pagination: Decodable, Sendable, Equatable {
    public let totalResults: Int
    public let startIndex: Int
    public let itemsPerPage: Int
}

public struct SearchTermPopularityResponse: Decodable, Sendable {
    public let data: [SearchTermPopularity]
    public let pagination: Pagination?
}

extension AdsAPIClient {
    public func searchTermPopularity(
        _ request: SearchTermPopularityRequest
    ) async throws -> SearchTermPopularityResponse {
        try await post("insights/apps/search-term-popularity/query", body: request)
    }
}
