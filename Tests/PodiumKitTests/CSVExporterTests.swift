import XCTest
@testable import PodiumKit

final class CSVExporterTests: XCTestCase {
    func testExportsHistoryWithEscaping() {
        let keyword = TrackedKeyword(id: 1, appId: 9, term: "kids, \"art\"", country: "us")
        let history = [
            RankSnapshot(id: 1, keywordId: 1, rank: 12, checkedAt: Date(timeIntervalSince1970: 0)),
            RankSnapshot(id: 2, keywordId: 1, rank: nil, checkedAt: Date(timeIntervalSince1970: 86_400)),
        ]
        let csv = CSVExporter.keywordHistoryCSV(keyword: keyword, history: history)
        let lines = csv.split(separator: "\n").map(String.init)
        XCTAssertEqual(lines[0], "date,term,country,rank")
        XCTAssertTrue(lines[1].hasPrefix("1970-01-01"))
        XCTAssertTrue(lines[1].contains("\"kids, \"\"art\"\"\""))
        XCTAssertTrue(lines[1].hasSuffix(",us,12"))
        XCTAssertTrue(lines[2].hasSuffix(",us,"))
    }
}
