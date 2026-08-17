import XCTest
@testable import PodiumKit

final class AdsModelsTests: XCTestCase {
    private func fixture(_ name: String) throws -> Data {
        let url = Bundle.module.url(forResource: "Fixtures/\(name)", withExtension: "json")!
        return try Data(contentsOf: url)
    }

    func testDecodesSearchTermPopularity() throws {
        let response = try JSONDecoder().decode(
            InsightsResponse<SearchTermPopularityRow>.self,
            from: fixture("search-term-popularity"))
        XCTAssertEqual(response.rows.count, 2)
        XCTAssertEqual(response.rows[0].searchTerm, "kids drawing")
        XCTAssertEqual(response.rows[0].searchPopularity1to100, 74)
        XCTAssertEqual(response.rows[0].rankInGenre, 1)
        XCTAssertEqual(response.rows[0].countryOrRegion, "US")
        XCTAssertEqual(response.pagination?.totalCount, 2)
    }

    func testDecodesKeywordSuggestions() throws {
        let response = try JSONDecoder().decode(
            SuggestionsResponse.self, from: fixture("keyword-suggestions"))
        XCTAssertEqual(response.suggestions.compactMap(\.term), ["kids art app", "drawing for kids"])
        XCTAssertEqual(response.suggestions[1].popularity, 38)
    }

    func testPopularityQueryEncodesContract() throws {
        let query = SearchTermPopularityQuery(
            timeRange: .init(start: "2026-08-09", end: "2026-08-15", granularity: .weekly),
            filters: [APIFilter(field: "countryOrRegion", op: "IN", value: ["US", "GB"])],
            pagination: APIPage(offset: 0, pageSize: 500))
        let json = try JSONSerialization.jsonObject(
            with: JSONEncoder().encode(query)) as! [String: Any]
        let timeRange = json["timeRange"] as! [String: Any]
        XCTAssertEqual(timeRange["granularity"] as? String, "WEEKLY_SUN_SAT")
        let filter = (json["filters"] as! [[String: Any]])[0]
        XCTAssertEqual(filter["operator"] as? String, "IN")
        XCTAssertEqual(filter["value"] as? [String], ["US", "GB"])
    }

    func testSuggestionsQueryRequiresPromotedObject() throws {
        let query = SuggestionsQuery.forApp(adamId: 123, countries: ["US"])
        let json = try JSONSerialization.jsonObject(
            with: JSONEncoder().encode(query)) as! [String: Any]
        let filters = json["filters"] as! [[String: Any]]
        let fields = filters.map { $0["field"] as! String }
        XCTAssertTrue(fields.contains("promotedObjectId"))
        XCTAssertTrue(fields.contains("promotedObjectType"))
        XCTAssertTrue(fields.contains("countryOrRegion"))
    }

    func testLatestWeeklyWindowIsSundayToSaturday() {
        let now = Date(timeIntervalSince1970: 1_787_264_000)
        let window = SearchTermPopularityQuery.latestWindow(granularity: .weekly, now: now)
        XCTAssertEqual(window.granularity, .weekly)
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(identifier: "UTC")
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let start = formatter.date(from: window.start)!
        let end = formatter.date(from: window.end)!
        XCTAssertEqual(calendar.component(.weekday, from: start), 1)
        XCTAssertEqual(calendar.component(.weekday, from: end), 7)
        XCTAssertEqual(calendar.dateComponents([.day], from: start, to: end).day, 6)
        XCTAssertLessThan(end, now)
    }
}
