import XCTest
import CryptoKit
@testable import PodiumKit

final class PopularityServiceTests: XCTestCase {
    private func makeAPI() -> AdsAPIClient {
        let creds = AdsCredentials(
            clientId: "c", teamId: "t", keyId: "k",
            privateKeyPEM: P256.Signing.PrivateKey().pemRepresentation, adAccountId: 1)
        let session = MockURLProtocol.makeSession()
        return AdsAPIClient(
            credentials: creds,
            tokenProvider: TokenProvider(credentials: creds, session: session),
            session: session, sleep: { _ in })
    }

    func testMapsPopularityForExactTermMatches() async throws {
        MockURLProtocol.handler = { request in
            if request.url?.host == "appleid.apple.com" {
                return (200, Data(#"{"access_token":"tok","token_type":"Bearer","expires_in":3600}"#.utf8))
            }
            XCTAssertEqual(request.value(forHTTPHeaderField: "X-AP-Context"), "adAccountId=1")
            XCTAssertTrue(request.url!.path.contains("suggestions/keywords/query"))
            let json = #"""
            {"result":[
              {"text":"kids drawing","popularity":74},
              {"text":"drawing games","popularity":50},
              {"text":"Art Scrapbook","popularity":41}
            ]}
            """#
            return (200, Data(json.utf8))
        }
        let service = PopularityService(api: makeAPI())

        let map = try await service.popularity(
            appId: 555, for: ["kids drawing", "art scrapbook", "missing term"], countries: ["us"])

        XCTAssertEqual(map["kids drawing"], 74)
        XCTAssertEqual(map["art scrapbook"], 41)
        XCTAssertNil(map["missing term"])
        XCTAssertNil(map["drawing games"])
    }

    func testEmptyTermsShortCircuits() async throws {
        MockURLProtocol.handler = { _ in
            XCTFail("no network call expected")
            return (500, Data())
        }
        let map = try await PopularityService(api: makeAPI())
            .popularity(appId: 1, for: [], countries: ["US"])
        XCTAssertEqual(map, [:])
    }
}
