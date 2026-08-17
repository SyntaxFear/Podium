import XCTest
@testable import PodiumKit

final class ScaffoldTests: XCTestCase {
    func testVersion() {
        XCTAssertEqual(PodiumKitInfo.version, "0.1.0")
    }
}
