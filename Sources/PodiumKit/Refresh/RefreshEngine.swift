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
    /// Throttled to stay under App Store search rate limits; a failing keyword (network error,
    /// rate limit, or deleted mid-refresh) is skipped so the rest of the loop completes.
    public func refreshAllKeywords() async throws -> [RankChange] {
        var changes: [RankChange] = []
        for (index, keyword) in try db.allKeywords().enumerated() {
            if index > 0 { try? await Task.sleep(for: .milliseconds(400)) }
            do {
                let previous = try db.latestRank(keywordId: keyword.id)?.rank
                let current = try await rankProvider(keyword.term, keyword.country, keyword.appId)
                try db.insertRankSnapshot(keywordId: keyword.id, rank: current, at: now())
                if previous != current {
                    changes.append(RankChange(
                        keywordId: keyword.id, term: keyword.term, country: keyword.country,
                        old: previous, new: current))
                }
            } catch {
                continue
            }
        }
        return changes
    }

    /// Checks every tracked competitor against every keyword of the app it's attached to.
    public func refreshCompetitors() async throws {
        for keyword in try db.allKeywords() {
            let competitors = try db.competitors(appId: keyword.appId)
            for competitor in competitors {
                try? await Task.sleep(for: .milliseconds(400))
                let rank: Int? = (try? await rankProvider(
                    keyword.term, keyword.country, competitor.competitorAdamId)) ?? nil
                try db.insertCompetitorRankSnapshot(
                    competitorId: competitor.id, keywordId: keyword.id, rank: rank, at: now())
            }
        }
    }
}
