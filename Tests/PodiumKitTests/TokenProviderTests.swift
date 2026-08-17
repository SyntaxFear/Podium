import XCTest
import CryptoKit
@testable import PodiumKit

final class TokenProviderTests: XCTestCase {
    private func makeCredentials() -> AdsCredentials {
        AdsCredentials(
            clientId: "SEARCHADS.abc", teamId: "SEARCHADS.team", keyId: "kid-1",
            privateKeyPEM: P256.Signing.PrivateKey().pemRepresentation, orgId: 123)
    }

    func testFetchesAndCachesToken() async throws {
        nonisolated(unsafe) var calls = 0
        MockURLProtocol.handler = { request in
            calls += 1
            XCTAssertEqual(request.url?.host, "appleid.apple.com")
            XCTAssertEqual(request.httpMethod, "POST")
            let json = #"{"access_token":"tok-1","token_type":"Bearer","expires_in":3600}"#
            return (200, Data(json.utf8))
        }
        let provider = TokenProvider(
            credentials: makeCredentials(), session: MockURLProtocol.makeSession())
        let t1 = try await provider.validToken()
        let t2 = try await provider.validToken()
        XCTAssertEqual(t1, "tok-1")
        XCTAssertEqual(t2, "tok-1")
        XCTAssertEqual(calls, 1)
    }

    func testRefreshesExpiredToken() async throws {
        nonisolated(unsafe) var calls = 0
        MockURLProtocol.handler = { _ in
            calls += 1
            let json = #"{"access_token":"tok-\#(calls)","token_type":"Bearer","expires_in":3600}"#
            return (200, Data(json.utf8))
        }
        nonisolated(unsafe) var fakeNow = Date(timeIntervalSince1970: 1_755_000_000)
        let provider = TokenProvider(
            credentials: makeCredentials(), session: MockURLProtocol.makeSession(),
            now: { fakeNow })
        _ = try await provider.validToken()
        fakeNow = fakeNow.addingTimeInterval(3600)
        let t = try await provider.validToken()
        XCTAssertEqual(t, "tok-2")
        XCTAssertEqual(calls, 2)
    }

    func testHTTPErrorSurfaces() async throws {
        MockURLProtocol.handler = { _ in (400, Data(#"{"error":"invalid_client"}"#.utf8)) }
        let provider = TokenProvider(
            credentials: makeCredentials(), session: MockURLProtocol.makeSession())
        do {
            _ = try await provider.validToken()
            XCTFail("expected error")
        } catch let PodiumError.http(status, body) {
            XCTAssertEqual(status, 400)
            XCTAssertTrue(body.contains("invalid_client"))
        }
    }
}
