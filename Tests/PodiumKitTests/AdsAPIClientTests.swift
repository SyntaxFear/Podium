import XCTest
import CryptoKit
@testable import PodiumKit

final class AdsAPIClientTests: XCTestCase {
    private func makeClient(handler: @escaping @Sendable (URLRequest) throws -> (Int, Data)) -> AdsAPIClient {
        MockURLProtocol.handler = handler
        let creds = AdsCredentials(
            clientId: "c", teamId: "t", keyId: "k",
            privateKeyPEM: P256.Signing.PrivateKey().pemRepresentation, orgId: 42)
        let session = MockURLProtocol.makeSession()
        return AdsAPIClient(
            credentials: creds,
            tokenProvider: TokenProvider(credentials: creds, session: session),
            session: session, sleep: { _ in })
    }

    struct Echo: Codable, Equatable { let ok: Bool }

    func testAttachesAuthAndContextHeaders() async throws {
        let client = makeClient { request in
            if request.url?.host == "appleid.apple.com" {
                return (200, Data(#"{"access_token":"tok","token_type":"Bearer","expires_in":3600}"#.utf8))
            }
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer tok")
            XCTAssertEqual(request.value(forHTTPHeaderField: "X-AP-Context"), "adAccountId=42")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
            return (200, Data(#"{"ok":true}"#.utf8))
        }
        let result: Echo = try await client.post("insights/apps/search-term-popularity/query", body: ["a": "b"])
        XCTAssertEqual(result, Echo(ok: true))
    }

    func testRetriesOn429ThenSucceeds() async throws {
        nonisolated(unsafe) var apiCalls = 0
        let client = makeClient { request in
            if request.url?.host == "appleid.apple.com" {
                return (200, Data(#"{"access_token":"tok","token_type":"Bearer","expires_in":3600}"#.utf8))
            }
            apiCalls += 1
            return apiCalls < 3 ? (429, Data()) : (200, Data(#"{"ok":true}"#.utf8))
        }
        let result: Echo = try await client.post("suggestions/keywords/query", body: ["a": "b"])
        XCTAssertEqual(result, Echo(ok: true))
        XCTAssertEqual(apiCalls, 3)
    }

    func testGivesUpAfterMaxRetries() async throws {
        let client = makeClient { request in
            if request.url?.host == "appleid.apple.com" {
                return (200, Data(#"{"access_token":"tok","token_type":"Bearer","expires_in":3600}"#.utf8))
            }
            return (429, Data())
        }
        do {
            let _: Echo = try await client.post("reports/campaigns", body: ["a": "b"])
            XCTFail("expected rateLimited")
        } catch PodiumError.rateLimited {}
    }

    func testNon200SurfacesBody() async throws {
        let client = makeClient { request in
            if request.url?.host == "appleid.apple.com" {
                return (200, Data(#"{"access_token":"tok","token_type":"Bearer","expires_in":3600}"#.utf8))
            }
            return (403, Data(#"{"error":{"errors":[{"message":"forbidden"}]}}"#.utf8))
        }
        do {
            let _: Echo = try await client.post("x", body: ["a": "b"])
            XCTFail("expected http error")
        } catch let PodiumError.http(status, body) {
            XCTAssertEqual(status, 403)
            XCTAssertTrue(body.contains("forbidden"))
        }
    }
}
