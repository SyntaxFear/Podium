import XCTest
@testable import PodiumKit

final class ReportsTests: XCTestCase {
    private func fixture(_ name: String) throws -> Data {
        let url = Bundle.module.url(forResource: "Fixtures/\(name)", withExtension: "json")!
        return try Data(contentsOf: url)
    }

    func testDecodesKeywordReportRow() throws {
        let response = try JSONDecoder().decode(
            ReportResponse.self, from: fixture("report-keywords"))
        XCTAssertEqual(response.rows.count, 1)
        let row = response.rows[0]
        XCTAssertEqual(row.id, "111")
        XCTAssertEqual(row.text, "kids drawing")
        XCTAssertEqual(row.status, "ACTIVE")
        XCTAssertEqual(row.countryOrRegion, "US")
        XCTAssertEqual(row.totalMetrics?.impressions, 5000)
        XCTAssertEqual(row.totalMetrics?.taps, 210)
        XCTAssertEqual(row.totalMetrics?.localSpend?.value, 42.50)
        XCTAssertEqual(row.insights?.bidRecommendation?.suggestedBidAmount, 1.25)
        XCTAssertEqual(response.pagination?.totalCount, 1)
    }

    func testTrailingDaysWindowEndsYesterday() {
        let now = Date(timeIntervalSince1970: 1_787_264_000)
        let window = ReportsQuery.trailingDays(7, now: now)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = calendar.timeZone
        let start = formatter.date(from: window.start)!
        let end = formatter.date(from: window.end)!
        XCTAssertEqual(calendar.dateComponents([.day], from: start, to: end).day, 7)
        XCTAssertLessThan(end, now)
    }

    func testReportLevelPaths() {
        XCTAssertEqual(ReportLevel.campaigns.path, "reports/apps/campaigns/query")
        XCTAssertEqual(ReportLevel.searchterms.path, "reports/apps/searchterms/query")
    }
}
