import XCTest
import GRDB
@testable import PodiumKit

final class RefreshEngineTests: XCTestCase {
    func testRefreshRecordsSnapshotsAndDiffsChanges() async throws {
        let db = try PodiumDatabase(queue: DatabaseQueue())
        try db.upsertApp(TrackedApp(id: 1, name: "Buki", artworkURL: nil, rating: nil, ratingCount: nil))
        let kw1 = try db.addKeyword(appId: 1, term: "kids drawing", country: "us")
        let kw2 = try db.addKeyword(appId: 1, term: "art scrapbook", country: "us")
        try db.insertRankSnapshot(keywordId: kw1.id, rank: 10, at: Date(timeIntervalSince1970: 1))

        let ranks: [String: Int?] = ["kids drawing": 8, "art scrapbook": nil]
        let engine = RefreshEngine(db: db) { term, _, _ in ranks[term] ?? nil }

        let changes = try await engine.refreshAllKeywords()

        XCTAssertEqual(try db.latestRank(keywordId: kw1.id)?.rank, 8)
        XCTAssertEqual(try db.latestRank(keywordId: kw2.id)?.rank, nil)
        XCTAssertEqual(changes, [
            RankChange(keywordId: kw1.id, term: "kids drawing", country: "us", old: 10, new: 8)
        ])
    }
}
