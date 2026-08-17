import XCTest
@testable import PodiumKit

final class PathsAndCredentialsTests: XCTestCase {
    func testDatabaseURLCreatesDirectory() throws {
        let base = FileManager.default.temporaryDirectory
            .appending(path: "podium-test-\(UUID().uuidString)")
        let url = try PodiumPaths.databaseURL(under: base)
        XCTAssertEqual(url.lastPathComponent, "podium.sqlite")
        XCTAssertEqual(url.deletingLastPathComponent().lastPathComponent, "Podium")
        var isDir: ObjCBool = false
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: url.deletingLastPathComponent().path, isDirectory: &isDir))
        XCTAssertTrue(isDir.boolValue)
    }

    func testCredentialsRoundTrip() throws {
        let store = CredentialsStore(store: InMemorySecretStore())
        XCTAssertNil(try store.load())
        let creds = AdsCredentials(
            clientId: "c", teamId: "t", keyId: "k", privateKeyPEM: "pem", orgId: 7)
        try store.save(creds)
        XCTAssertEqual(try store.load(), creds)
        try store.clear()
        XCTAssertNil(try store.load())
    }
}
