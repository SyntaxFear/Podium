import Foundation

public struct SuggestionsRequest: Encodable, Sendable {
    public var terms: [String]?
    public var adamId: Int?
    public var countriesOrRegions: [String]?

    public init(terms: [String]? = nil, adamId: Int? = nil, countriesOrRegions: [String]? = nil) {
        self.terms = terms
        self.adamId = adamId
        self.countriesOrRegions = countriesOrRegions
    }
}

public struct Suggestion: Decodable, Sendable, Equatable {
    public let text: String
    public let popularity: Int?
}

public struct SuggestionsResponse: Decodable, Sendable {
    public let data: [Suggestion]
}

extension AdsAPIClient {
    public func keywordSuggestions(_ request: SuggestionsRequest) async throws -> SuggestionsResponse {
        try await post("suggestions/keywords/query", body: request)
    }

    public func phraseSuggestions(_ request: SuggestionsRequest) async throws -> SuggestionsResponse {
        try await post("suggestions/phrases/query", body: request)
    }
}
