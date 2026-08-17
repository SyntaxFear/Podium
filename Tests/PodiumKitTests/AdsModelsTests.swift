import XCTest
@testable import PodiumKit

final class AdsModelsTests: XCTestCase {
    private func fixture(_ name: String) throws -> Data {
        let url = Bundle.module.url(forResource: "Fixtures/\(name)", withExtension: "json")!
        return try Data(contentsOf: url)
    }

    func testDecodesSearchTermPopularity() throws {
        let response = try JSONDecoder().decode(
            SearchTermPopularityResponse.self, from: fixture("search-term-popularity"))
        XCTAssertEqual(response.data.count, 2)
        XCTAssertEqual(response.data[0].searchTerm, "kids drawing")
        XCTAssertEqual(response.data[0].popularity, 74)
        XCTAssertEqual(response.data[0].rank, 1)
    }

    func testDecodesKeywordSuggestions() throws {
        let response = try JSONDecoder().decode(
            SuggestionsResponse.self, from: fixture("keyword-suggestions"))
        XCTAssertEqual(response.data.map(\.text), ["kids art app", "drawing for kids"])
        XCTAssertEqual(response.data[1].popularity, 38)
    }

    func testPopularityRequestEncodesFilters() throws {
        let request = SearchTermPopularityRequest(
            countryOrRegion: "US", genreId: 6017, granularity: .weekly)
        let json = try JSONSerialization.jsonObject(
            with: JSONEncoder().encode(request)) as! [String: Any]
        XCTAssertEqual(json["countryOrRegion"] as? String, "US")
        XCTAssertEqual(json["genreId"] as? Int, 6017)
        XCTAssertEqual(json["granularity"] as? String, "WEEKLY")
    }
}
