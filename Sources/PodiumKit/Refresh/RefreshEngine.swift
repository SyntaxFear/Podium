import Foundation

public struct RankChange: Sendable, Equatable {
    public let keywordId: Int64
    public let term: String
    public let country: String
    public let old: Int?
    public let new: Int?
}

public struct RefreshEngine: Sendable {
    public typealias RankProvider = @Sendable (_ term: String, _ country: String, _ appId: Int) async throws -> Int?

    let db: PodiumDatabase
    let rankProvider: RankProvider
    let now: @Sendable () -> Date

    public init(
        db: PodiumDatabase,
        now: @escaping @Sendable () -> Date = { Date() },
        rankProvider: @escaping RankProvider
    ) {
        self.db = db
        self.now = now
        self.rankProvider = rankProvider
    }

    /// Convenience wiring for production: check ranks via the public App Store client.
    public init(db: PodiumDatabase, client: AppStoreSearchClient) {
        self.init(db: db) { term, country, appId in
            try await client.rank(ofApp: appId, term: term, country: country)
        }
    }

    /// Checks every tracked keyword, appends snapshots, and returns rank changes (old != new only).
    public func refreshAllKeywords() async throws -> [RankChange] {
        var changes: [RankChange] = []
        for keyword in try db.allKeywords() {
            let previous = try db.latestRank(keywordId: keyword.id)?.rank
            let current = try await rankProvider(keyword.term, keyword.country, keyword.appId)
            try db.insertRankSnapshot(keywordId: keyword.id, rank: current, at: now())
            if previous != current {
                changes.append(RankChange(
                    keywordId: keyword.id, term: keyword.term, country: keyword.country,
                    old: previous, new: current))
            }
        }
        return changes
    }
}
