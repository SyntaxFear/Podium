import Foundation

/// Resolves official popularity scores for tracked keyword terms via the
/// keyword-suggestions endpoint, scoped to the promoted app as the API requires.
/// Scores are Apple-aggregated across storefronts — no per-country breakdown.
public struct PopularityService: Sendable {
    let api: AdsAPIClient
    public init(api: AdsAPIClient) { self.api = api }

    /// Lowercased term → popularity, for exact (case-insensitive) matches only.
    public func popularity(
        appId: Int, for terms: [String], countries: [String]
    ) async throws -> [String: Int] {
        guard !terms.isEmpty else { return [:] }
        let wanted = Set(terms.map { $0.lowercased() })
        let response = try await api.keywordSuggestions(
            .forApp(adamId: appId, countries: countries.map { $0.uppercased() }))
        var map: [String: Int] = [:]
        for suggestion in response.suggestions {
            guard let term = suggestion.term?.lowercased() else { continue }
            if wanted.contains(term), let score = suggestion.popularity {
                map[term] = score
            }
        }
        return map
    }
}
