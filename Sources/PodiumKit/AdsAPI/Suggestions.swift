import Foundation

/// POST /v1/suggestions/{keywords|phrases|categories}/query
/// Filters on promotedObjectId + promotedObjectType are required by the API.
public struct SuggestionsQuery: Encodable, Sendable {
    public var filters: [APIFilter]
    public var sorting: [APISort]?
    public var pagination: APIPage?

    public init(filters: [APIFilter], sorting: [APISort]? = nil, pagination: APIPage? = nil) {
        self.filters = filters
        self.sorting = sorting
        self.pagination = pagination
    }

    public static func forApp(
        adamId: Int, countries: [String] = [], pageSize: Int = 1000
    ) -> SuggestionsQuery {
        var filters = [
            APIFilter(field: "promotedObjectId", op: "EQUALS", value: [String(adamId)]),
            APIFilter(field: "promotedObjectType", op: "EQUALS", value: ["APPSTORE_APP"]),
        ]
        if !countries.isEmpty {
            filters.append(APIFilter(field: "countryOrRegion", op: "IN", value: countries))
        }
        return SuggestionsQuery(
            filters: filters,
            sorting: [APISort(field: "popularity", order: "DESC")],
            pagination: APIPage(offset: 0, pageSize: min(pageSize, 1000)))
    }
}

public struct Suggestion: Decodable, Sendable, Equatable {
    public let text: String?
    public let phrase: String?
    public let category: String?
    public let popularity: Int?

    /// The suggested term regardless of which endpoint produced it.
    public var term: String? { text ?? phrase ?? category }
}

public struct SuggestionsResponse: Decodable, Sendable {
    public let result: [Suggestion]?
    public let pagination: ResponsePagination?

    public var suggestions: [Suggestion] { result ?? [] }
}

extension AdsAPIClient {
    public func keywordSuggestions(_ query: SuggestionsQuery) async throws -> SuggestionsResponse {
        try await post("suggestions/keywords/query", body: query)
    }

    public func phraseSuggestions(_ query: SuggestionsQuery) async throws -> SuggestionsResponse {
        try await post("suggestions/phrases/query", body: query)
    }

    public func categorySuggestions(_ query: SuggestionsQuery) async throws -> SuggestionsResponse {
        try await post("suggestions/categories/query", body: query)
    }
}
