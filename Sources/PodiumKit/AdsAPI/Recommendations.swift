import Foundation

/// POST /v1/recommendations/{target-cpas|daily-budgets}/query
public struct TargetCpaRecommendation: Decodable, Sendable, Identifiable {
    public let id: Int?
    public let campaignId: Int?
    public let campaignName: String?
    public let recommendedTargetCPA: Money?
    public let averageCPA: Money?
    public let averageCPT: Money?
    public let expectedInstalls: Int?
    public let expectedSpend: Money?
    public let expectedCPA: Money?

    public var rowId: String { id.map(String.init) ?? UUID().uuidString }
}

public struct DailyCapRecommendation: Decodable, Sendable, Identifiable {
    public let id: Int?
    public let campaignId: Int?
    public let campaignName: String?
    public let dailyBudget: Money?
    public let suggestedDailyBudgetAmount: Money?
    public let expectedInstalls: Int?
    public let expectedSpend: Money?
    public let expectedCpa: Money?

    public var rowId: String { id.map(String.init) ?? UUID().uuidString }
}

extension TargetCpaRecommendation {
    public var id_: String { rowId }
}

struct RecommendationsResult<Row: Decodable>: Decodable {
    let rows: [Row]?
}

struct RecommendationsResponse<Row: Decodable>: Decodable {
    let result: RecommendationsResult<Row>?
    var rows: [Row] { result?.rows ?? [] }
}

extension AdsAPIClient {
    public func targetCpaRecommendations(_ query: SuggestionsQuery) async throws -> [TargetCpaRecommendation] {
        let response: RecommendationsResponse<TargetCpaRecommendation> =
            try await post("recommendations/target-cpas/query", body: query)
        return response.rows
    }

    public func dailyBudgetRecommendations(_ query: SuggestionsQuery) async throws -> [DailyCapRecommendation] {
        let response: RecommendationsResponse<DailyCapRecommendation> =
            try await post("recommendations/daily-budgets/query", body: query)
        return response.rows
    }
}
