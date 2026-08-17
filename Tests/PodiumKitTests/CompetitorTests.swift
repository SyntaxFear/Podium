import XCTest
import GRDB
@testable import PodiumKit

final class CompetitorTests: XCTestCase {
    func testAddCompetitorAndListByApp() throws {
        let db = try PodiumDatabase(queue: DatabaseQueue())
        try db.upsertApp(TrackedApp(id: 1, name: "Mine", artworkURL: nil, rating: nil, ratingCount: nil))
        let competitor = try db.addCompetitor(
            appId: 1, competitorAdamId: 999, name: "Rival", artworkURL: nil)
        XCTAssertEqual(competitor.name, "Rival")
        XCTAssertEqual(try db.competitors(appId: 1).count, 1)

        _ = try db.addCompetitor(appId: 1, competitorAdamId: 999, name: "Rival", artworkURL: nil)
        XCTAssertEqual(try db.competitors(appId: 1).count, 1, "adding the same competitor twice should not duplicate")
    }

    func testCompetitorRankSnapshotsAndLatest() throws {
        let db = try PodiumDatabase(queue: DatabaseQueue())
        try db.upsertApp(TrackedApp(id: 1, name: "Mine", artworkURL: nil, rating: nil, ratingCount: nil))
        let keyword = try db.addKeyword(appId: 1, term: "wardrobe", country: "us")
        let competitor = try db.addCompetitor(
            appId: 1, competitorAdamId: 999, name: "Rival", artworkURL: nil)

        try db.insertCompetitorRankSnapshot(competitorId: competitor.id, keywordId: keyword.id, rank: 12, at: Date())
        try db.insertCompetitorRankSnapshot(competitorId: competitor.id, keywordId: keyword.id, rank: 8, at: Date().addingTimeInterval(3600))

        XCTAssertEqual(try db.latestCompetitorRank(competitorId: competitor.id, keywordId: keyword.id)?.rank, 8)
    }

    func testDeleteCompetitorRemovesSnapshots() throws {
        let db = try PodiumDatabase(queue: DatabaseQueue())
        try db.upsertApp(TrackedApp(id: 1, name: "Mine", artworkURL: nil, rating: nil, ratingCount: nil))
        let keyword = try db.addKeyword(appId: 1, term: "wardrobe", country: "us")
        let competitor = try db.addCompetitor(
            appId: 1, competitorAdamId: 999, name: "Rival", artworkURL: nil)
        try db.insertCompetitorRankSnapshot(competitorId: competitor.id, keywordId: keyword.id, rank: 12, at: Date())

        try db.deleteCompetitor(id: competitor.id)

        XCTAssertTrue(try db.competitors(appId: 1).isEmpty)
        XCTAssertNil(try db.latestCompetitorRank(competitorId: competitor.id, keywordId: keyword.id))
    }
}
