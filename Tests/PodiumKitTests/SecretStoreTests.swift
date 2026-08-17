import XCTest
@testable import PodiumKit

final class SecretStoreTests: XCTestCase {
    func testInMemoryRoundTrip() throws {
        let store = InMemorySecretStore()
        try store.set(Data("pem".utf8), for: "privateKey")
        XCTAssertEqual(try store.get("privateKey"), Data("pem".utf8))
        try store.delete("privateKey")
        XCTAssertNil(try store.get("privateKey"))
    }
}
