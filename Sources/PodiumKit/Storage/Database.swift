import Foundation
import GRDB

public struct TrackedApp: Codable, Sendable, Equatable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "trackedApp"
    public var id: Int
    public var name: String
    public var artworkURL: String?
    public var rating: Double?
    public var ratingCount: Int?

    public init(id: Int, name: String, artworkURL: String?, rating: Double?, ratingCount: Int?) {
        self.id = id
        self.name = name
        self.artworkURL = artworkURL
        self.rating = rating
        self.ratingCount = ratingCount
    }
}

public struct TrackedKeyword: Codable, Sendable, Equatable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "trackedKeyword"
    public var id: Int64
    public var appId: Int
    public var term: String
    public var country: String
}

public struct RankSnapshot: Codable, Sendable, Equatable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "rankSnapshot"
    public var id: Int64?
    public var keywordId: Int64
    public var rank: Int?
    public var checkedAt: Date
}

public struct TrackedCompetitor: Codable, Sendable, Equatable, FetchableRecord, PersistableRecord, Identifiable {
    public static let databaseTableName = "trackedCompetitor"
    public var id: Int64
    public var appId: Int
    public var competitorAdamId: Int
    public var name: String
    public var artworkURL: String?
}

public struct CompetitorRankSnapshot: Codable, Sendable, Equatable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "competitorRankSnapshot"
    public var id: Int64?
    public var competitorId: Int64
    public var keywordId: Int64
    public var rank: Int?
    public var checkedAt: Date
}

public final class PodiumDatabase: Sendable {
    let queue: DatabaseQueue

    public convenience init(path: String) throws {
        try self.init(queue: DatabaseQueue(path: path))
    }

    public init(queue: DatabaseQueue) throws {
        self.queue = queue
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1") { db in
            try db.create(table: "trackedApp") { t in
                t.primaryKey("id", .integer)
                t.column("name", .text).notNull()
                t.column("artworkURL", .text)
                t.column("rating", .double)
                t.column("ratingCount", .integer)
            }
            try db.create(table: "trackedKeyword") { t in
                t.autoIncrementedPrimaryKey("id")
                t.belongsTo("app", inTable: "trackedApp").notNull()
                t.column("term", .text).notNull()
                t.column("country", .text).notNull()
                t.uniqueKey(["appId", "term", "country"])
            }
            try db.create(table: "rankSnapshot") { t in
                t.autoIncrementedPrimaryKey("id")
                t.belongsTo("keyword", inTable: "trackedKeyword").notNull()
                t.column("rank", .integer)
                t.column("checkedAt", .datetime).notNull()
            }
        }
        migrator.registerMigration("v2_competitors") { db in
            try db.create(table: "trackedCompetitor") { t in
                t.autoIncrementedPrimaryKey("id")
                t.belongsTo("app", inTable: "trackedApp").notNull()
                t.column("competitorAdamId", .integer).notNull()
                t.column("name", .text).notNull()
                t.column("artworkURL", .text)
                t.uniqueKey(["appId", "competitorAdamId"])
            }
            try db.create(table: "competitorRankSnapshot") { t in
                t.autoIncrementedPrimaryKey("id")
                t.belongsTo("competitor", inTable: "trackedCompetitor").notNull()
                t.belongsTo("keyword", inTable: "trackedKeyword").notNull()
                t.column("rank", .integer)
                t.column("checkedAt", .datetime).notNull()
            }
        }
        try migrator.migrate(queue)
    }

    public func upsertApp(_ app: TrackedApp) throws {
        try queue.write { db in try app.upsert(db) }
    }

    public func allApps() throws -> [TrackedApp] {
        try queue.read { db in try TrackedApp.order(Column("name")).fetchAll(db) }
    }

    @discardableResult
    public func addKeyword(appId: Int, term: String, country: String) throws -> TrackedKeyword {
        try queue.write { db in
            let existing = try TrackedKeyword
                .filter(Column("appId") == appId && Column("term") == term && Column("country") == country)
                .fetchOne(db)
            if let existing { return existing }
            let id = try Int64.fetchOne(db, sql: "SELECT COALESCE(MAX(id),0)+1 FROM trackedKeyword")!
            let keyword = TrackedKeyword(id: id, appId: appId, term: term, country: country)
            try keyword.insert(db)
            return keyword
        }
    }

    public func keywords(appId: Int) throws -> [TrackedKeyword] {
        try queue.read { db in
            try TrackedKeyword.filter(Column("appId") == appId).order(Column("term")).fetchAll(db)
        }
    }

    public func allKeywords() throws -> [TrackedKeyword] {
        try queue.read { db in try TrackedKeyword.fetchAll(db) }
    }

    public func insertRankSnapshot(keywordId: Int64, rank: Int?, at date: Date) throws {
        try queue.write { db in
            var snapshot = RankSnapshot(id: nil, keywordId: keywordId, rank: rank, checkedAt: date)
            try snapshot.insert(db)
        }
    }

    public func latestRank(keywordId: Int64) throws -> RankSnapshot? {
        try queue.read { db in
            try RankSnapshot.filter(Column("keywordId") == keywordId)
                .order(Column("checkedAt").desc).fetchOne(db)
        }
    }

    public func deleteKeyword(id: Int64) throws {
        try queue.write { db in
            try db.execute(sql: "DELETE FROM rankSnapshot WHERE keywordId = ?", arguments: [id])
            try db.execute(sql: "DELETE FROM trackedKeyword WHERE id = ?", arguments: [id])
        }
    }

    public func deleteApp(id: Int) throws {
        try queue.write { db in
            try db.execute(
                sql: "DELETE FROM rankSnapshot WHERE keywordId IN (SELECT id FROM trackedKeyword WHERE appId = ?)",
                arguments: [id])
            try db.execute(sql: "DELETE FROM trackedKeyword WHERE appId = ?", arguments: [id])
            try db.execute(sql: "DELETE FROM trackedApp WHERE id = ?", arguments: [id])
        }
    }

    public func rankHistory(keywordId: Int64, limit: Int = 90) throws -> [RankSnapshot] {
        try queue.read { db in
            Array(
                try RankSnapshot.filter(Column("keywordId") == keywordId)
                    .order(Column("checkedAt").desc).limit(limit).fetchAll(db)
                    .reversed())
        }
    }

    @discardableResult
    public func addCompetitor(
        appId: Int, competitorAdamId: Int, name: String, artworkURL: String?
    ) throws -> TrackedCompetitor {
        try queue.write { db in
            let existing = try TrackedCompetitor
                .filter(Column("appId") == appId && Column("competitorAdamId") == competitorAdamId)
                .fetchOne(db)
            if let existing { return existing }
            let id = try Int64.fetchOne(db, sql: "SELECT COALESCE(MAX(id),0)+1 FROM trackedCompetitor")!
            let competitor = TrackedCompetitor(
                id: id, appId: appId, competitorAdamId: competitorAdamId,
                name: name, artworkURL: artworkURL)
            try competitor.insert(db)
            return competitor
        }
    }

    public func competitors(appId: Int) throws -> [TrackedCompetitor] {
        try queue.read { db in
            try TrackedCompetitor.filter(Column("appId") == appId).order(Column("name")).fetchAll(db)
        }
    }

    public func deleteCompetitor(id: Int64) throws {
        try queue.write { db in
            try db.execute(sql: "DELETE FROM competitorRankSnapshot WHERE competitorId = ?", arguments: [id])
            try db.execute(sql: "DELETE FROM trackedCompetitor WHERE id = ?", arguments: [id])
        }
    }

    public func insertCompetitorRankSnapshot(competitorId: Int64, keywordId: Int64, rank: Int?, at date: Date) throws {
        try queue.write { db in
            var snapshot = CompetitorRankSnapshot(
                id: nil, competitorId: competitorId, keywordId: keywordId, rank: rank, checkedAt: date)
            try snapshot.insert(db)
        }
    }

    public func latestCompetitorRank(competitorId: Int64, keywordId: Int64) throws -> CompetitorRankSnapshot? {
        try queue.read { db in
            try CompetitorRankSnapshot
                .filter(Column("competitorId") == competitorId && Column("keywordId") == keywordId)
                .order(Column("checkedAt").desc).fetchOne(db)
        }
    }
}
