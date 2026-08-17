import XCTest
import GRDB
@testable import PodiumKit

final class StorageTests: XCTestCase {
    private func makeDB() throws -> PodiumDatabase {
        try PodiumDatabase(queue: DatabaseQueue())
    }

    func testUpsertAppAndAddKeyword() throws {
        let db = try makeDB()
        try db.upsertApp(TrackedApp(id: 1, name: "Buki", artworkURL: nil, rating: 4.5, ratingCount: 10))
        try db.upsertApp(TrackedApp(id: 1, name: "Buki", artworkURL: nil, rating: 4.7, ratingCount: 12))
        XCTAssertEqual(try db.allApps().count, 1)
        XCTAssertEqual(try db.allApps()[0].rating, 4.7)

        let kw = try db.addKeyword(appId: 1, term: "kids drawing", country: "us")
        _ = try db.addKeyword(appId: 1, term: "kids drawing", country: "us")
        XCTAssertEqual(try db.keywords(appId: 1).count, 1)
        XCTAssertEqual(kw.term, "kids drawing")
    }

    func testRankSnapshotsAndLatest() throws {
        let db = try makeDB()
        try db.upsertApp(TrackedApp(id: 1, name: "Buki", artworkURL: nil, rating: nil, ratingCount: nil))
        let kw = try db.addKeyword(appId: 1, term: "kids drawing", country: "us")
        let t1 = Date(timeIntervalSince1970: 1_755_000_000)
        try db.insertRankSnapshot(keywordId: kw.id, rank: 12, at: t1)
        try db.insertRankSnapshot(keywordId: kw.id, rank: 8, at: t1.addingTimeInterval(86_400))
        XCTAssertEqual(try db.latestRank(keywordId: kw.id)?.rank, 8)
        XCTAssertEqual(try db.rankHistory(keywordId: kw.id).count, 2)
    }
}
