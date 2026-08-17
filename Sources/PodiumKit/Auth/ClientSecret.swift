import Foundation
import CryptoKit

public enum ClientSecret {
    /// Apple caps client-secret lifetime at 180 days; we use 170 to leave rotation margin.
    public static let lifetime: TimeInterval = 86_400 * 170

    public static func make(
        clientId: String, teamId: String, keyId: String,
        privateKeyPEM: String, now: Date = Date()
    ) throws -> String {
        let key = try P256.Signing.PrivateKey(pemRepresentation: privateKeyPEM)
        let iat = Int(now.timeIntervalSince1970)
        let header: [String: String] = ["alg": "ES256", "kid": keyId]
        let payload: [String: Any] = [
            "sub": clientId, "iss": teamId, "aud": "https://appleid.apple.com",
            "iat": iat, "exp": iat + Int(lifetime),
        ]
        let h = try JSONSerialization.data(withJSONObject: header, options: [.sortedKeys]).base64URLEncoded()
        let p = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys]).base64URLEncoded()
        let signingInput = Data("\(h).\(p)".utf8)
        let signature = try key.signature(for: signingInput)
        return "\(h).\(p).\(signature.rawRepresentation.base64URLEncoded())"
    }

    public static func generatePrivateKeyPEM() -> String {
        P256.Signing.PrivateKey().pemRepresentation
    }

    public static func publicKeyPEM(fromPrivatePEM pem: String) throws -> String {
        try P256.Signing.PrivateKey(pemRepresentation: pem).publicKey.pemRepresentation
    }
}
