import Foundation

public struct AdsCredentials: Sendable, Codable, Equatable {
    public var clientId: String
    public var teamId: String
    public var keyId: String
    public var privateKeyPEM: String
    /// Legacy org scoping (v5-style); kept so previously saved credentials still decode.
    public var orgId: Int?
    /// Ad-account scoping for the Platform API (X-AP-Context: adAccountId=…).
    public var adAccountId: Int?

    public init(
        clientId: String, teamId: String, keyId: String, privateKeyPEM: String,
        orgId: Int? = nil, adAccountId: Int? = nil
    ) {
        self.clientId = clientId
        self.teamId = teamId
        self.keyId = keyId
        self.privateKeyPEM = privateKeyPEM
        self.orgId = orgId
        self.adAccountId = adAccountId
    }
}

public actor TokenProvider {
    public static let tokenURL = URL(string: "https://appleid.apple.com/auth/oauth2/token")!
    public static let scope = "searchadsorg"

    private let credentials: AdsCredentials
    private let session: URLSession
    private let now: @Sendable () -> Date
    private var cached: (token: String, expiresAt: Date)?

    public init(
        credentials: AdsCredentials, session: URLSession = .shared,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.credentials = credentials
        self.session = session
        self.now = now
    }

    public func validToken() async throws -> String {
        if let cached, cached.expiresAt > now().addingTimeInterval(60) {
            return cached.token
        }
        let secret = try ClientSecret.make(
            clientId: credentials.clientId, teamId: credentials.teamId,
            keyId: credentials.keyId, privateKeyPEM: credentials.privateKeyPEM, now: now())

        var request = URLRequest(url: Self.tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let form = [
            "grant_type": "client_credentials",
            "client_id": credentials.clientId,
            "client_secret": secret,
            "scope": Self.scope,
        ]
        request.httpBody = Data(
            form.map { "\($0.key)=\($0.value)" }.joined(separator: "&").utf8)

        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else {
            throw PodiumError.http(status: status, body: String(decoding: data, as: UTF8.self))
        }
        struct TokenResponse: Decodable {
            let access_token: String
            let expires_in: Int
        }
        let decoded = try JSONDecoder().decode(TokenResponse.self, from: data)
        let entry = (decoded.access_token, now().addingTimeInterval(TimeInterval(decoded.expires_in)))
        cached = entry
        return entry.0
    }

    public func invalidate() { cached = nil }
}
