import XCTest
@testable import PodiumKit

final class AppStoreSearchClientTests: XCTestCase {
    private func fixture(_ name: String) throws -> Data {
        let url = Bundle.module.url(forResource: "Fixtures/\(name)", withExtension: "json")!
        return try Data(contentsOf: url)
    }

    func testRankFindsPositionInResults() async throws {
        let data = try fixture("itunes-search")
        MockURLProtocol.handler = { request in
            XCTAssertEqual(request.url?.host, "itunes.apple.com")
            let query = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!
            let items = Dictionary(uniqueKeysWithValues: query.queryItems!.map { ($0.name, $0.value ?? "") })
            XCTAssertEqual(items["term"], "wardrobe app")
            XCTAssertEqual(items["country"], "us")
            XCTAssertEqual(items["entity"], "software")
            return (200, data)
        }
        let client = AppStoreSearchClient(session: MockURLProtocol.makeSession())
        let rank = try await client.rank(ofApp: 6797999335, term: "wardrobe app", country: "us")
        XCTAssertEqual(rank, 2)
    }

    func testRankReturnsNilWhenAbsent() async throws {
        let data = try fixture("itunes-search")
        MockURLProtocol.handler = { _ in (200, data) }
        let client = AppStoreSearchClient(session: MockURLProtocol.makeSession())
        let rank = try await client.rank(ofApp: 999, term: "wardrobe app", country: "us")
        XCTAssertNil(rank)
    }

    func testLookupReturnsAppMetadata() async throws {
        let data = try fixture("itunes-lookup")
        MockURLProtocol.handler = { _ in (200, data) }
        let client = AppStoreSearchClient(session: MockURLProtocol.makeSession())
        let app = try await client.lookup(appId: 6797999335, country: "us")
        XCTAssertEqual(app?.trackName, "Samosi")
        XCTAssertEqual(app?.userRatingCount, 120)
    }
}
