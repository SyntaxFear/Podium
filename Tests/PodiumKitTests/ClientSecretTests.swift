import XCTest
import CryptoKit
@testable import PodiumKit

final class ClientSecretTests: XCTestCase {
    func testBase64URLHasNoPaddingOrUnsafeChars() {
        let data = Data([251, 255, 190, 1])
        let s = data.base64URLEncoded()
        XCTAssertFalse(s.contains("="))
        XCTAssertFalse(s.contains("+"))
        XCTAssertFalse(s.contains("/"))
    }

    func testClientSecretStructureAndSignature() throws {
        let key = P256.Signing.PrivateKey()
        let now = Date(timeIntervalSince1970: 1_755_000_000)
        let jwt = try ClientSecret.make(
            clientId: "SEARCHADS.abc", teamId: "SEARCHADS.team", keyId: "kid-1",
            privateKeyPEM: key.pemRepresentation, now: now)

        let parts = jwt.split(separator: ".").map(String.init)
        XCTAssertEqual(parts.count, 3)

        func decode(_ s: String) throws -> [String: Any] {
            var b = s.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
            while b.count % 4 != 0 { b += "=" }
            let obj = try JSONSerialization.jsonObject(with: Data(base64Encoded: b)!)
            return obj as! [String: Any]
        }
        let header = try decode(parts[0])
        XCTAssertEqual(header["alg"] as? String, "ES256")
        XCTAssertEqual(header["kid"] as? String, "kid-1")

        let payload = try decode(parts[1])
        XCTAssertEqual(payload["sub"] as? String, "SEARCHADS.abc")
        XCTAssertEqual(payload["iss"] as? String, "SEARCHADS.team")
        XCTAssertEqual(payload["aud"] as? String, "https://appleid.apple.com")
        let iat = payload["iat"] as! Int, exp = payload["exp"] as! Int
        XCTAssertEqual(iat, 1_755_000_000)
        XCTAssertEqual(exp - iat, 86_400 * 170)

        var raw = parts[2].replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while raw.count % 4 != 0 { raw += "=" }
        let sig = try P256.Signing.ECDSASignature(rawRepresentation: Data(base64Encoded: raw)!)
        let signed = Data("\(parts[0]).\(parts[1])".utf8)
        XCTAssertTrue(key.publicKey.isValidSignature(sig, for: signed))
    }
}
