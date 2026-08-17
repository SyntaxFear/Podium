import Foundation

/// POST /v1/reports/apps/{campaigns|adgroups|ads|keywords|searchterms}/query
public struct ReportsQuery: Encodable, Sendable {
    public struct TimeRange: Encodable, Sendable {
        public var start: String
        public var end: String
        public var timeZone: String?
        public var granularity: String?

        public init(start: String, end: String, timeZone: String? = nil, granularity: String? = nil) {
            self.start = start
            self.end = end
            self.timeZone = timeZone
            self.granularity = granularity
        }
    }

    public var timeRange: TimeRange
    public var filters: [APIFilter]?
    public var sorting: [APISort]?
    public var pagination: APIPage?
    public var groupBy: [String]?

    public init(
        timeRange: TimeRange, filters: [APIFilter]? = nil, sorting: [APISort]? = nil,
        pagination: APIPage? = nil, groupBy: [String]? = nil
    ) {
        self.timeRange = timeRange
        self.filters = filters
        self.sorting = sorting
        self.pagination = pagination
        self.groupBy = groupBy
    }

    /// Trailing N days ending yesterday, UTC-safe.
    public static func trailingDays(_ count: Int, now: Date = Date()) -> TimeRange {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = calendar.timeZone
        let end = calendar.date(byAdding: .day, value: -1, to: now)!
        let start = calendar.date(byAdding: .day, value: -count, to: end)!
        return TimeRange(start: formatter.string(from: start), end: formatter.string(from: end))
    }
}

public struct Money: Decodable, Sendable, Equatable {
    public let amount: String?
    public let currency: String?

    public var value: Double { amount.flatMap(Double.init) ?? 0 }
}

/// Metric fields shared across campaign/ad-group/keyword/search-term/ad report rows.
public struct ReportMetrics: Decodable, Sendable, Equatable {
    public let date: String?
    public let localSpend: Money?
    public let impressions: Int?
    public let taps: Int?
    public let ttr: Double?
    public let cpt: Money?
    public let cpm: Money?
    public let tapInstalls: Int?
    public let tapInstallCPI: Money?
    public let tapInstallRate: Double?
    public let totalInstalls: Int?
    public let totalAvgCPI: Money?
    public let totalInstallRate: Double?
    public let viewInstalls: Int?
}

public struct KeywordInsights: Decodable, Sendable, Equatable {
    public struct BidRecommendation: Decodable, Sendable, Equatable {
        public let suggestedBidAmount: Double?
    }
    public let bidRecommendation: BidRecommendation?
}

/// One row of a campaign/ad-group/keyword/search-term/ad report, with row identity
/// (name/status when present) plus totals. Fields not present for a given level
/// stay nil — a single generic row shape covers all five report endpoints.
public struct ReportRow: Decodable, Sendable, Identifiable {
    public let id: String
    public let name: String?
    public let status: String?
    public let displayStatus: String?
    public let text: String?
    public let searchTermText: String?
    public let countryOrRegion: String?
    public let deviceClass: String?
    public let totalMetrics: ReportMetrics?
    public let granularMetrics: [ReportMetrics]?
    public let insights: KeywordInsights?

    enum CodingKeys: String, CodingKey {
        case id, name, status, displayStatus, text, searchTermText
        case countryOrRegion, deviceClass, totalMetrics, granularMetrics, insights
    }

    /// Reports encode entity identity as a nested `metadata` object rather than
    /// flat fields; this decoder flattens it so ReportRow reads the same for
    /// campaigns, ad groups, keywords, search terms, and ads.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: DynamicKey.self)
        func string(_ key: String, in c: KeyedDecodingContainer<DynamicKey>) -> String? {
            try? c.decodeIfPresent(String.self, forKey: DynamicKey(stringValue: key)!)
        }
        func int(_ key: String, in c: KeyedDecodingContainer<DynamicKey>) -> Int? {
            if let v = try? c.decodeIfPresent(Int.self, forKey: DynamicKey(stringValue: key)!) { return v }
            return nil
        }

        let metadataKey = DynamicKey(stringValue: "metadata")!
        let metadata = try? container.nestedContainer(keyedBy: DynamicKey.self, forKey: metadataKey)

        let rawId = metadata.flatMap { int("id", in: $0) } ?? int("id", in: container)
        id = rawId.map(String.init) ?? UUID().uuidString
        name = metadata.flatMap { string("name", in: $0) } ?? string("name", in: container)
        status = metadata.flatMap { string("status", in: $0) }
        displayStatus = metadata.flatMap { string("displayStatus", in: $0) }
        text = metadata.flatMap { string("text", in: $0) }
        searchTermText = metadata.flatMap { string("searchTermText", in: $0) }
        countryOrRegion = metadata.flatMap { string("countryOrRegion", in: $0) }
            ?? string("countryOrRegion", in: container)
        deviceClass = metadata.flatMap { string("deviceClass", in: $0) }
            ?? string("deviceClass", in: container)
        totalMetrics = try container.decodeIfPresent(
            ReportMetrics.self, forKey: DynamicKey(stringValue: "totalMetrics")!)
        granularMetrics = try container.decodeIfPresent(
            [ReportMetrics].self, forKey: DynamicKey(stringValue: "granularMetrics")!)
        insights = try metadata?.decodeIfPresent(
            KeywordInsights.self, forKey: DynamicKey(stringValue: "insights")!)
    }
}

private struct DynamicKey: CodingKey {
    var stringValue: String
    var intValue: Int?
    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { self.stringValue = String(intValue); self.intValue = intValue }
}

public struct ReportSummary: Decodable, Sendable {
    public let grandTotal: ReportMetrics?
}

public struct ReportResult: Decodable, Sendable {
    public let rows: [ReportRow]?
    public let summary: ReportSummary?
}

public struct ReportResponse: Decodable, Sendable {
    public let result: ReportResult?
    public let pagination: ResponsePagination?

    public var rows: [ReportRow] { result?.rows ?? [] }
    public var grandTotal: ReportMetrics? { result?.summary?.grandTotal }
}

public enum ReportLevel: String, Sendable, CaseIterable {
    case campaigns, adgroups, ads, keywords, searchterms

    public var path: String { "reports/apps/\(rawValue)/query" }
    public var displayName: String {
        switch self {
        case .campaigns: return "Campaigns"
        case .adgroups: return "Ad groups"
        case .ads: return "Ads"
        case .keywords: return "Keywords"
        case .searchterms: return "Search terms"
        }
    }
}

extension AdsAPIClient {
    public func report(_ level: ReportLevel, query: ReportsQuery) async throws -> ReportResponse {
        try await post(level.path, body: query)
    }
}
