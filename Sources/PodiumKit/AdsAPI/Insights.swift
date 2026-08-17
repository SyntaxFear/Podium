import Foundation

/// Shared query building blocks for the Apple Ads Platform API v1.
public struct APIFilter: Encodable, Sendable {
    public var field: String
    public var op: String
    public var value: [String]
    public var ignoreCase: Bool?

    enum CodingKeys: String, CodingKey {
        case field
        case op = "operator"
        case value
        case ignoreCase
    }

    public init(field: String, op: String, value: [String], ignoreCase: Bool? = nil) {
        self.field = field
        self.op = op
        self.value = value
        self.ignoreCase = ignoreCase
    }
}

public struct APISort: Encodable, Sendable {
    public var field: String
    public var order: String

    public init(field: String, order: String = "ASC") {
        self.field = field
        self.order = order
    }
}

public struct APIPage: Encodable, Sendable {
    public var offset: Int
    public var pageSize: Int

    public init(offset: Int = 0, pageSize: Int = 500) {
        self.offset = offset
        self.pageSize = pageSize
    }
}

public struct ResponsePagination: Decodable, Sendable, Equatable {
    public let offset: Int?
    public let pageSize: Int?
    public let totalCount: Int?
}

/// POST /v1/insights/apps/search-term-popularity/query
public struct SearchTermPopularityQuery: Encodable, Sendable {
    public enum Granularity: String, Encodable, Sendable {
        case weekly = "WEEKLY_SUN_SAT"
        case monthly = "MONTHLY"
    }

    public struct TimeRange: Encodable, Sendable {
        public var start: String
        public var end: String
        public var granularity: Granularity

        public init(start: String, end: String, granularity: Granularity) {
            self.start = start
            self.end = end
            self.granularity = granularity
        }
    }

    public var timeRange: TimeRange
    public var filters: [APIFilter]?
    public var sorting: [APISort]?
    public var pagination: APIPage?

    public init(
        timeRange: TimeRange, filters: [APIFilter]? = nil,
        sorting: [APISort]? = nil, pagination: APIPage? = nil
    ) {
        self.timeRange = timeRange
        self.filters = filters
        self.sorting = sorting
        self.pagination = pagination
    }

    /// The most recent complete reporting window: last full Sun–Sat week, or previous month.
    public static func latestWindow(granularity: Granularity, now: Date = Date()) -> TimeRange {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = calendar.timeZone
        switch granularity {
        case .weekly:
            let weekday = calendar.component(.weekday, from: now)
            let lastSaturday = calendar.date(byAdding: .day, value: -weekday - 7, to: now)!
            let sunday = calendar.date(byAdding: .day, value: -6, to: lastSaturday)!
            return TimeRange(
                start: formatter.string(from: sunday),
                end: formatter.string(from: lastSaturday), granularity: .weekly)
        case .monthly:
            let startOfThisMonth = calendar.date(
                from: calendar.dateComponents([.year, .month], from: now))!
            let startOfPrevious = calendar.date(byAdding: .month, value: -2, to: startOfThisMonth)!
            let endOfPrevious = calendar.date(byAdding: .day, value: -1, to: startOfThisMonth)!
            return TimeRange(
                start: formatter.string(from: startOfPrevious),
                end: formatter.string(from: endOfPrevious), granularity: .monthly)
        }
    }
}

public struct SearchTermPopularityRow: Decodable, Sendable, Equatable, Identifiable {
    public let week: String?
    public let month: String?
    public let countryOrRegion: String?
    public let genre: String?
    public let searchTerm: String
    public let rankInGenre: Int?
    public let searchPopularityInGenre: Int?
    public let searchPopularity1to100: Int?
    public let searchPopularity1to5: Int?

    public var id: String {
        "\(searchTerm)|\(countryOrRegion ?? "")|\(genre ?? "")|\(week ?? month ?? "")"
    }
}

public struct InsightsResult<Row: Decodable & Sendable>: Decodable, Sendable {
    public let rows: [Row]?
}

public struct InsightsResponse<Row: Decodable & Sendable>: Decodable, Sendable {
    public let result: InsightsResult<Row>?
    public let pagination: ResponsePagination?

    public var rows: [Row] { result?.rows ?? [] }
}

extension AdsAPIClient {
    public func searchTermPopularity(
        _ query: SearchTermPopularityQuery
    ) async throws -> InsightsResponse<SearchTermPopularityRow> {
        try await post("insights/apps/search-term-popularity/query", body: query)
    }
}
