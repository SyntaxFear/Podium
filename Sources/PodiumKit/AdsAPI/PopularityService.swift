import Foundation

/// Resolves official popularity scores for tracked keyword terms via the
/// keyword-suggestions endpoint (seeded with the terms themselves).
/// Scores are Apple-aggregated across storefronts — no per-country breakdown.
public struct PopularityService: Sendable {
    let api: AdsAPIClient
    public init(api: AdsAPIClient) { self.api = api }

    /// Lowercased term → popularity, for exact (case-insensitive) matches only.
    public func popularity(for terms: [String], countries: [String]) async throws -> [String: Int] {
        guard !terms.isEmpty else { return [:] }
        let wanted = Set(terms.map { $0.lowercased() })
        let response = try await api.keywordSuggestions(
            SuggestionsRequest(terms: terms, countriesOrRegions: countries))
        var map: [String: Int] = [:]
        for suggestion in response.data {
            let key = suggestion.text.lowercased()
            if wanted.contains(key), let score = suggestion.popularity {
                map[key] = score
            }
        }
        return map
    }
}
