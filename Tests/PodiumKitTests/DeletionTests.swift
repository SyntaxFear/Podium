import XCTest
import GRDB
@testable import PodiumKit

final class DeletionTests: XCTestCase {
    func testDeleteKeywordRemovesHistory() throws {
        let db = try PodiumDatabase(queue: DatabaseQueue())
        try db.upsertApp(TrackedApp(id: 1, name: "A", artworkURL: nil, rating: nil, ratingCount: nil))
        let kw = try db.addKeyword(appId: 1, term: "x", country: "us")
        try db.insertRankSnapshot(keywordId: kw.id, rank: 5, at: Date())
        try db.deleteKeyword(id: kw.id)
        XCTAssertTrue(try db.keywords(appId: 1).isEmpty)
        XCTAssertNil(try db.latestRank(keywordId: kw.id))
    }

    func testDeleteAppCascades() throws {
        let db = try PodiumDatabase(queue: DatabaseQueue())
        try db.upsertApp(TrackedApp(id: 1, name: "A", artworkURL: nil, rating: nil, ratingCount: nil))
        let kw = try db.addKeyword(appId: 1, term: "x", country: "us")
        try db.insertRankSnapshot(keywordId: kw.id, rank: 5, at: Date())
        try db.deleteApp(id: 1)
        XCTAssertTrue(try db.allApps().isEmpty)
        XCTAssertTrue(try db.allKeywords().isEmpty)
        XCTAssertNil(try db.latestRank(keywordId: kw.id))
    }
}
