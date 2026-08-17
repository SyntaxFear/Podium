# PodiumKit Core Engine Implementation Plan (Plan 1 of 3)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build PodiumKit — the UI-free Swift package powering Podium: Apple Ads OAuth, typed API clients, public App Store rank checking, local SQLite storage, and the refresh/diff engine — fully unit-tested.

**Architecture:** A single SwiftPM package with one library target (`PodiumKit`) organized into Auth / AdsAPI / PublicStore / Storage / Refresh folders, plus a `podium-smoke` executable for manual live verification. All network code is injectable (URLProtocol mocks in tests); all persistence tests run on in-memory SQLite.

**Tech Stack:** Swift 6 / SwiftPM, CryptoKit (ES256 JWT), URLSession async/await, GRDB.swift 7 (SQLite), XCTest.

**Scope note:** Plan 2 (SwiftUI Mac app: wizard + screens) and Plan 3 (repo/README/CI/notarized releases) are separate follow-up plans, authored after this plan is executed and reviewed. This plan alone yields a working, tested engine and a CLI smoke test.

**Conventions for every task:** run commands from `/Users/bitcoin/Desktop/Podium`. Test runner is `swift test`. Commit after every green test run — plan steps include the exact commits.

---

### Task 1: Package scaffold

**Files:**
- Create: `Package.swift`
- Create: `Sources/PodiumKit/PodiumKit.swift`
- Create: `Tests/PodiumKitTests/ScaffoldTests.swift`
- Create: `.gitignore`

- [ ] **Step 1: Write Package.swift**

```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PodiumKit",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "PodiumKit", targets: ["PodiumKit"]),
        .executable(name: "podium-smoke", targets: ["PodiumSmoke"]),
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.0.0"),
    ],
    targets: [
        .target(name: "PodiumKit", dependencies: [.product(name: "GRDB", package: "GRDB.swift")]),
        .executableTarget(name: "PodiumSmoke", dependencies: ["PodiumKit"]),
        .testTarget(name: "PodiumKitTests", dependencies: ["PodiumKit"]),
    ]
)
```

- [ ] **Step 2: Write minimal sources so the package builds**

`Sources/PodiumKit/PodiumKit.swift`:
```swift
public enum PodiumKitInfo {
    public static let version = "0.1.0"
}
```

Create `Sources/PodiumSmoke/main.swift`:
```swift
import PodiumKit
print("PodiumKit \(PodiumKitInfo.version)")
```

`Tests/PodiumKitTests/ScaffoldTests.swift`:
```swift
import XCTest
@testable import PodiumKit

final class ScaffoldTests: XCTestCase {
    func testVersion() {
        XCTAssertEqual(PodiumKitInfo.version, "0.1.0")
    }
}
```

`.gitignore`:
```
.build/
.swiftpm/
xcuserdata/
DerivedData/
*.xcodeproj
.DS_Store
```

- [ ] **Step 3: Run tests**

Run: `swift test`
Expected: `Test Suite 'All tests' passed` (1 test). First run also resolves GRDB (network fetch, ~30s).

- [ ] **Step 4: Commit**

```bash
git add -A && git commit -m "feat: scaffold PodiumKit package with GRDB dependency"
```

---

### Task 2: Base64URL + client secret (ES256 JWT)

**Files:**
- Create: `Sources/PodiumKit/Auth/Base64URL.swift`
- Create: `Sources/PodiumKit/Auth/ClientSecret.swift`
- Test: `Tests/PodiumKitTests/ClientSecretTests.swift`

- [ ] **Step 1: Write the failing tests**

```swift
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
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter ClientSecretTests`
Expected: compile error — `base64URLEncoded` / `ClientSecret` not defined.

- [ ] **Step 3: Implement**

`Sources/PodiumKit/Auth/Base64URL.swift`:
```swift
import Foundation

extension Data {
    func base64URLEncoded() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
```

`Sources/PodiumKit/Auth/ClientSecret.swift`:
```swift
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
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter ClientSecretTests`
Expected: 2 tests PASS.

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "feat: ES256 client secret (JWT) generation and key-pair helpers"
```

---

### Task 3: Secret storage (protocol + in-memory + Keychain)

**Files:**
- Create: `Sources/PodiumKit/Auth/SecretStore.swift`
- Test: `Tests/PodiumKitTests/SecretStoreTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
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
```

- [ ] **Step 2: Run to verify failure**

Run: `swift test --filter SecretStoreTests`
Expected: compile error — types not defined.

- [ ] **Step 3: Implement**

`Sources/PodiumKit/Auth/SecretStore.swift`:
```swift
import Foundation
import Security

public protocol SecretStore: Sendable {
    func set(_ data: Data, for key: String) throws
    func get(_ key: String) throws -> Data?
    func delete(_ key: String) throws
}

public final class InMemorySecretStore: SecretStore, @unchecked Sendable {
    private var storage: [String: Data] = [:]
    private let lock = NSLock()
    public init() {}
    public func set(_ data: Data, for key: String) throws {
        lock.lock(); defer { lock.unlock() }
        storage[key] = data
    }
    public func get(_ key: String) throws -> Data? {
        lock.lock(); defer { lock.unlock() }
        return storage[key]
    }
    public func delete(_ key: String) throws {
        lock.lock(); defer { lock.unlock() }
        storage[key] = nil
    }
}

/// Thin macOS Keychain adapter (kSecClassGenericPassword under the "app.podium" service).
/// Not unit-tested — exercised via the smoke CLI and the app.
public struct KeychainSecretStore: SecretStore {
    public let service: String
    public init(service: String = "app.podium") { self.service = service }

    public func set(_ data: Data, for key: String) throws {
        try delete(key)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
        ]
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else { throw PodiumError.keychain(status) }
    }

    public func get(_ key: String) throws -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw PodiumError.keychain(status) }
        return result as? Data
    }

    public func delete(_ key: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw PodiumError.keychain(status)
        }
    }
}

public enum PodiumError: Error, Equatable {
    case keychain(OSStatus)
    case missingCredentials
    case http(status: Int, body: String)
    case rateLimited
    case decoding(String)
}
```

- [ ] **Step 4: Run tests**

Run: `swift test --filter SecretStoreTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "feat: SecretStore protocol with in-memory and Keychain implementations"
```

---

### Task 4: URLProtocol mock + TokenProvider

**Files:**
- Create: `Sources/PodiumKit/Auth/TokenProvider.swift`
- Create: `Tests/PodiumKitTests/Support/MockURLProtocol.swift`
- Test: `Tests/PodiumKitTests/TokenProviderTests.swift`

- [ ] **Step 1: Write the mock transport (test support, no test yet)**

`Tests/PodiumKitTests/Support/MockURLProtocol.swift`:
```swift
import Foundation

final class MockURLProtocol: URLProtocol {
    nonisolated(unsafe) static var handler: (@Sendable (URLRequest) throws -> (Int, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.handler else { fatalError("no handler set") }
        do {
            let (status, data) = try handler(request)
            let response = HTTPURLResponse(
                url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}

    static func makeSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        return URLSession(configuration: config)
    }
}
```

- [ ] **Step 2: Write the failing tests**

`Tests/PodiumKitTests/TokenProviderTests.swift`:
```swift
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
```

- [ ] **Step 3: Run to verify failure**

Run: `swift test --filter TokenProviderTests`
Expected: compile error — `AdsCredentials` / `TokenProvider` not defined.

- [ ] **Step 4: Implement**

`Sources/PodiumKit/Auth/TokenProvider.swift`:
```swift
import Foundation

public struct AdsCredentials: Sendable, Codable, Equatable {
    public var clientId: String
    public var teamId: String
    public var keyId: String
    public var privateKeyPEM: String
    public var orgId: Int?

    public init(clientId: String, teamId: String, keyId: String, privateKeyPEM: String, orgId: Int? = nil) {
        self.clientId = clientId
        self.teamId = teamId
        self.keyId = keyId
        self.privateKeyPEM = privateKeyPEM
        self.orgId = orgId
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
```

- [ ] **Step 5: Run tests**

Run: `swift test --filter TokenProviderTests`
Expected: 3 tests PASS.

- [ ] **Step 6: Commit**

```bash
git add -A && git commit -m "feat: OAuth2 token provider with caching and expiry refresh"
```

---

### Task 5: AdsAPIClient (auth injection, retry, backoff)

**Files:**
- Create: `Sources/PodiumKit/AdsAPI/AdsAPIClient.swift`
- Test: `Tests/PodiumKitTests/AdsAPIClientTests.swift`

- [ ] **Step 1: Write the failing tests**

```swift
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
            XCTAssertEqual(request.value(forHTTPHeaderField: "X-AP-Context"), "orgId=42")
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
```

- [ ] **Step 2: Run to verify failure**

Run: `swift test --filter AdsAPIClientTests`
Expected: compile error — `AdsAPIClient` not defined.

- [ ] **Step 3: Implement**

`Sources/PodiumKit/AdsAPI/AdsAPIClient.swift`:
```swift
import Foundation

public struct AdsAPIClient: Sendable {
    /// Verified against Apple's live docs in Task 9 (smoke). Single source of truth for the host.
    public static let defaultBaseURL = URL(string: "https://api.searchads.apple.com/api/v1")!

    let baseURL: URL
    let credentials: AdsCredentials
    let tokenProvider: TokenProvider
    let session: URLSession
    let sleep: @Sendable (Duration) async -> Void
    let maxRetries: Int

    public init(
        credentials: AdsCredentials,
        tokenProvider: TokenProvider,
        baseURL: URL = AdsAPIClient.defaultBaseURL,
        session: URLSession = .shared,
        maxRetries: Int = 3,
        sleep: @escaping @Sendable (Duration) async -> Void = { try? await Task.sleep(for: $0) }
    ) {
        self.credentials = credentials
        self.tokenProvider = tokenProvider
        self.baseURL = baseURL
        self.session = session
        self.maxRetries = maxRetries
        self.sleep = sleep
    }

    public func post<T: Decodable, Body: Encodable & Sendable>(
        _ path: String, body: Body
    ) async throws -> T {
        try await send(path: path, method: "POST", body: body)
    }

    public func get<T: Decodable>(_ path: String) async throws -> T {
        try await send(path: path, method: "GET", body: Optional<Int>.none)
    }

    private func send<T: Decodable, Body: Encodable & Sendable>(
        path: String, method: String, body: Body?
    ) async throws -> T {
        var attempt = 0
        var didRefreshAuth = false
        while true {
            attempt += 1
            var request = URLRequest(url: baseURL.appending(path: path))
            request.httpMethod = method
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            let token = try await tokenProvider.validToken()
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            if let orgId = credentials.orgId {
                request.setValue("orgId=\(orgId)", forHTTPHeaderField: "X-AP-Context")
            }
            if let body {
                request.httpBody = try JSONEncoder().encode(body)
            }

            let (data, response) = try await session.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            switch status {
            case 200, 201:
                do {
                    return try JSONDecoder().decode(T.self, from: data)
                } catch {
                    throw PodiumError.decoding("\(T.self): \(error)")
                }
            case 401 where !didRefreshAuth:
                didRefreshAuth = true
                await tokenProvider.invalidate()
                continue
            case 429, 500...599:
                if attempt > maxRetries { throw PodiumError.rateLimited }
                await sleep(.seconds(Double(1 << (attempt - 1))))
                continue
            default:
                throw PodiumError.http(status: status, body: String(decoding: data, as: UTF8.self))
            }
        }
    }
}
```

- [ ] **Step 4: Run tests**

Run: `swift test --filter AdsAPIClientTests`
Expected: 4 tests PASS.

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "feat: Ads API client with auth injection, 401 refresh, and 429 backoff"
```

---

### Task 6: Insights + Suggestions endpoint models

**Files:**
- Create: `Sources/PodiumKit/AdsAPI/Insights.swift`
- Create: `Sources/PodiumKit/AdsAPI/Suggestions.swift`
- Create: `Tests/PodiumKitTests/Fixtures/search-term-popularity.json`
- Create: `Tests/PodiumKitTests/Fixtures/keyword-suggestions.json`
- Test: `Tests/PodiumKitTests/AdsModelsTests.swift`
- Modify: `Package.swift` (add fixtures as test resources)

**Contract note:** field names below follow Apple's published Apple Ads Platform API v1 documentation (search-term rank/popularity rows; suggestion text/popularity pairs; responses wrapped in a `data` envelope, popularity aggregated across storefronts — no per-country field). Task 9's smoke run validates them against the live API; any drift found there is fixed in the models and these fixtures together.

- [ ] **Step 1: Add fixtures**

`Tests/PodiumKitTests/Fixtures/search-term-popularity.json`:
```json
{
  "data": [
    { "searchTerm": "kids drawing", "rank": 1, "popularity": 74 },
    { "searchTerm": "coloring book", "rank": 2, "popularity": 69 }
  ],
  "pagination": { "totalResults": 2, "startIndex": 0, "itemsPerPage": 50 }
}
```

`Tests/PodiumKitTests/Fixtures/keyword-suggestions.json`:
```json
{
  "data": [
    { "text": "kids art app", "popularity": 41 },
    { "text": "drawing for kids", "popularity": 38 }
  ]
}
```

In `Package.swift`, change the test target to:
```swift
.testTarget(
    name: "PodiumKitTests",
    dependencies: ["PodiumKit"],
    resources: [.copy("Fixtures")]),
```

- [ ] **Step 2: Write the failing tests**

`Tests/PodiumKitTests/AdsModelsTests.swift`:
```swift
import XCTest
@testable import PodiumKit

final class AdsModelsTests: XCTestCase {
    private func fixture(_ name: String) throws -> Data {
        let url = Bundle.module.url(forResource: "Fixtures/\(name)", withExtension: "json")!
        return try Data(contentsOf: url)
    }

    func testDecodesSearchTermPopularity() throws {
        let response = try JSONDecoder().decode(
            SearchTermPopularityResponse.self, from: fixture("search-term-popularity"))
        XCTAssertEqual(response.data.count, 2)
        XCTAssertEqual(response.data[0].searchTerm, "kids drawing")
        XCTAssertEqual(response.data[0].popularity, 74)
        XCTAssertEqual(response.data[0].rank, 1)
    }

    func testDecodesKeywordSuggestions() throws {
        let response = try JSONDecoder().decode(
            SuggestionsResponse.self, from: fixture("keyword-suggestions"))
        XCTAssertEqual(response.data.map(\.text), ["kids art app", "drawing for kids"])
        XCTAssertEqual(response.data[1].popularity, 38)
    }

    func testPopularityRequestEncodesFilters() throws {
        let request = SearchTermPopularityRequest(
            countryOrRegion: "US", genreId: 6017, granularity: .weekly)
        let json = try JSONSerialization.jsonObject(
            with: JSONEncoder().encode(request)) as! [String: Any]
        XCTAssertEqual(json["countryOrRegion"] as? String, "US")
        XCTAssertEqual(json["genreId"] as? Int, 6017)
        XCTAssertEqual(json["granularity"] as? String, "WEEKLY")
    }
}
```

- [ ] **Step 3: Run to verify failure**

Run: `swift test --filter AdsModelsTests`
Expected: compile error — model types not defined.

- [ ] **Step 4: Implement**

`Sources/PodiumKit/AdsAPI/Insights.swift`:
```swift
import Foundation

public struct SearchTermPopularityRequest: Encodable, Sendable {
    public enum Granularity: String, Encodable, Sendable {
        case weekly = "WEEKLY"
        case monthly = "MONTHLY"
    }
    public var countryOrRegion: String
    public var genreId: Int?
    public var granularity: Granularity

    public init(countryOrRegion: String, genreId: Int? = nil, granularity: Granularity = .weekly) {
        self.countryOrRegion = countryOrRegion
        self.genreId = genreId
        self.granularity = granularity
    }
}

public struct SearchTermPopularity: Decodable, Sendable, Equatable {
    public let searchTerm: String
    public let rank: Int
    public let popularity: Int
}

public struct Pagination: Decodable, Sendable, Equatable {
    public let totalResults: Int
    public let startIndex: Int
    public let itemsPerPage: Int
}

public struct SearchTermPopularityResponse: Decodable, Sendable {
    public let data: [SearchTermPopularity]
    public let pagination: Pagination?
}

extension AdsAPIClient {
    public func searchTermPopularity(
        _ request: SearchTermPopularityRequest
    ) async throws -> SearchTermPopularityResponse {
        try await post("insights/apps/search-term-popularity/query", body: request)
    }
}
```

`Sources/PodiumKit/AdsAPI/Suggestions.swift`:
```swift
import Foundation

public struct SuggestionsRequest: Encodable, Sendable {
    public var terms: [String]?
    public var adamId: Int?
    public var countriesOrRegions: [String]?

    public init(terms: [String]? = nil, adamId: Int? = nil, countriesOrRegions: [String]? = nil) {
        self.terms = terms
        self.adamId = adamId
        self.countriesOrRegions = countriesOrRegions
    }
}

public struct Suggestion: Decodable, Sendable, Equatable {
    public let text: String
    public let popularity: Int?
}

public struct SuggestionsResponse: Decodable, Sendable {
    public let data: [Suggestion]
}

extension AdsAPIClient {
    public func keywordSuggestions(_ request: SuggestionsRequest) async throws -> SuggestionsResponse {
        try await post("suggestions/keywords/query", body: request)
    }

    public func phraseSuggestions(_ request: SuggestionsRequest) async throws -> SuggestionsResponse {
        try await post("suggestions/phrases/query", body: request)
    }
}
```

- [ ] **Step 5: Run tests**

Run: `swift test --filter AdsModelsTests`
Expected: 3 tests PASS.

- [ ] **Step 6: Commit**

```bash
git add -A && git commit -m "feat: insights and suggestions endpoint models with fixture-backed decoding"
```

---

### Task 7: Public App Store client (rank + app lookup)

**Files:**
- Create: `Sources/PodiumKit/PublicStore/AppStoreSearchClient.swift`
- Create: `Tests/PodiumKitTests/Fixtures/itunes-search.json`
- Create: `Tests/PodiumKitTests/Fixtures/itunes-lookup.json`
- Test: `Tests/PodiumKitTests/AppStoreSearchClientTests.swift`

- [ ] **Step 1: Add fixtures**

`Tests/PodiumKitTests/Fixtures/itunes-search.json`:
```json
{
  "resultCount": 3,
  "results": [
    { "trackId": 111, "trackName": "Other App A", "averageUserRating": 4.1, "userRatingCount": 10, "artworkUrl100": "https://example.com/a.png" },
    { "trackId": 6797999335, "trackName": "Samosi", "averageUserRating": 4.8, "userRatingCount": 120, "artworkUrl100": "https://example.com/s.png" },
    { "trackId": 333, "trackName": "Other App B", "averageUserRating": 3.9, "userRatingCount": 5, "artworkUrl100": "https://example.com/b.png" }
  ]
}
```

`Tests/PodiumKitTests/Fixtures/itunes-lookup.json`:
```json
{
  "resultCount": 1,
  "results": [
    { "trackId": 6797999335, "trackName": "Samosi", "averageUserRating": 4.8, "userRatingCount": 120, "artworkUrl100": "https://example.com/s.png" }
  ]
}
```

- [ ] **Step 2: Write the failing tests**

```swift
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
```

- [ ] **Step 3: Run to verify failure**

Run: `swift test --filter AppStoreSearchClientTests`
Expected: compile error — `AppStoreSearchClient` not defined.

- [ ] **Step 4: Implement**

`Sources/PodiumKit/PublicStore/AppStoreSearchClient.swift`:
```swift
import Foundation

public struct StoreApp: Decodable, Sendable, Equatable {
    public let trackId: Int
    public let trackName: String
    public let averageUserRating: Double?
    public let userRatingCount: Int?
    public let artworkUrl100: String?
}

public struct AppStoreSearchClient: Sendable {
    let session: URLSession
    public init(session: URLSession = .shared) { self.session = session }

    private struct SearchResponse: Decodable {
        let results: [StoreApp]
    }

    /// 1-based position of `appId` in App Store search results for `term`, or nil if not in the top `limit`.
    public func rank(ofApp appId: Int, term: String, country: String, limit: Int = 200) async throws -> Int? {
        var components = URLComponents(string: "https://itunes.apple.com/search")!
        components.queryItems = [
            URLQueryItem(name: "term", value: term),
            URLQueryItem(name: "country", value: country),
            URLQueryItem(name: "entity", value: "software"),
            URLQueryItem(name: "limit", value: String(limit)),
        ]
        let results = try await fetch(components.url!).results
        guard let index = results.firstIndex(where: { $0.trackId == appId }) else { return nil }
        return index + 1
    }

    public func lookup(appId: Int, country: String) async throws -> StoreApp? {
        var components = URLComponents(string: "https://itunes.apple.com/lookup")!
        components.queryItems = [
            URLQueryItem(name: "id", value: String(appId)),
            URLQueryItem(name: "country", value: country),
        ]
        return try await fetch(components.url!).results.first
    }

    public func search(term: String, country: String, limit: Int = 25) async throws -> [StoreApp] {
        var components = URLComponents(string: "https://itunes.apple.com/search")!
        components.queryItems = [
            URLQueryItem(name: "term", value: term),
            URLQueryItem(name: "country", value: country),
            URLQueryItem(name: "entity", value: "software"),
            URLQueryItem(name: "limit", value: String(limit)),
        ]
        return try await fetch(components.url!).results
    }

    private func fetch(_ url: URL) async throws -> SearchResponse {
        let (data, response) = try await session.data(from: url)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else {
            throw PodiumError.http(status: status, body: String(decoding: data, as: UTF8.self))
        }
        do {
            return try JSONDecoder().decode(SearchResponse.self, from: data)
        } catch {
            throw PodiumError.decoding("SearchResponse: \(error)")
        }
    }
}
```

- [ ] **Step 5: Run tests**

Run: `swift test --filter AppStoreSearchClientTests`
Expected: 3 tests PASS.

- [ ] **Step 6: Commit**

```bash
git add -A && git commit -m "feat: public App Store client for rank checks, search, and app lookup"
```

---

### Task 8: Storage (GRDB schema + queries) and Refresh engine

**Files:**
- Create: `Sources/PodiumKit/Storage/Database.swift`
- Create: `Sources/PodiumKit/Refresh/RefreshEngine.swift`
- Test: `Tests/PodiumKitTests/StorageTests.swift`
- Test: `Tests/PodiumKitTests/RefreshEngineTests.swift`

- [ ] **Step 1: Write the failing storage tests**

`Tests/PodiumKitTests/StorageTests.swift`:
```swift
import XCTest
import GRDB
@testable import PodiumKit

final class StorageTests: XCTestCase {
    private func makeDB() throws -> PodiumDatabase {
        try PodiumDatabase(queue: DatabaseQueue())
    }

    func testUpsertAppAndAddKeyword() throws {
        let db = try makeDB()
        try db.upsertApp(TrackedApp(id: 1, name: "Buki", artworkURL: nil, rating: 4.5, ratingCount: 10))
        try db.upsertApp(TrackedApp(id: 1, name: "Buki", artworkURL: nil, rating: 4.7, ratingCount: 12))
        XCTAssertEqual(try db.allApps().count, 1)
        XCTAssertEqual(try db.allApps()[0].rating, 4.7)

        let kw = try db.addKeyword(appId: 1, term: "kids drawing", country: "us")
        _ = try db.addKeyword(appId: 1, term: "kids drawing", country: "us")
        XCTAssertEqual(try db.keywords(appId: 1).count, 1)
        XCTAssertEqual(kw.term, "kids drawing")
    }

    func testRankSnapshotsAndLatest() throws {
        let db = try makeDB()
        try db.upsertApp(TrackedApp(id: 1, name: "Buki", artworkURL: nil, rating: nil, ratingCount: nil))
        let kw = try db.addKeyword(appId: 1, term: "kids drawing", country: "us")
        let t1 = Date(timeIntervalSince1970: 1_755_000_000)
        try db.insertRankSnapshot(keywordId: kw.id, rank: 12, at: t1)
        try db.insertRankSnapshot(keywordId: kw.id, rank: 8, at: t1.addingTimeInterval(86_400))
        XCTAssertEqual(try db.latestRank(keywordId: kw.id)?.rank, 8)
        XCTAssertEqual(try db.rankHistory(keywordId: kw.id).count, 2)
    }
}
```

- [ ] **Step 2: Run to verify failure**

Run: `swift test --filter StorageTests`
Expected: compile error — storage types not defined.

- [ ] **Step 3: Implement storage**

`Sources/PodiumKit/Storage/Database.swift`:
```swift
import Foundation
import GRDB

public struct TrackedApp: Codable, Sendable, Equatable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "trackedApp"
    public var id: Int
    public var name: String
    public var artworkURL: String?
    public var rating: Double?
    public var ratingCount: Int?

    public init(id: Int, name: String, artworkURL: String?, rating: Double?, ratingCount: Int?) {
        self.id = id
        self.name = name
        self.artworkURL = artworkURL
        self.rating = rating
        self.ratingCount = ratingCount
    }
}

public struct TrackedKeyword: Codable, Sendable, Equatable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "trackedKeyword"
    public var id: Int64
    public var appId: Int
    public var term: String
    public var country: String
}

public struct RankSnapshot: Codable, Sendable, Equatable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "rankSnapshot"
    public var id: Int64?
    public var keywordId: Int64
    public var rank: Int?
    public var checkedAt: Date
}

public final class PodiumDatabase: Sendable {
    let queue: DatabaseQueue

    public convenience init(path: String) throws {
        try self.init(queue: DatabaseQueue(path: path))
    }

    public init(queue: DatabaseQueue) throws {
        self.queue = queue
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1") { db in
            try db.create(table: "trackedApp") { t in
                t.primaryKey("id", .integer)
                t.column("name", .text).notNull()
                t.column("artworkURL", .text)
                t.column("rating", .double)
                t.column("ratingCount", .integer)
            }
            try db.create(table: "trackedKeyword") { t in
                t.autoIncrementedPrimaryKey("id")
                t.belongsTo("app", inTable: "trackedApp").notNull()
                t.column("term", .text).notNull()
                t.column("country", .text).notNull()
                t.uniqueKey(["appId", "term", "country"])
            }
            try db.create(table: "rankSnapshot") { t in
                t.autoIncrementedPrimaryKey("id")
                t.belongsTo("keyword", inTable: "trackedKeyword").notNull()
                t.column("rank", .integer)
                t.column("checkedAt", .datetime).notNull()
            }
        }
        try migrator.migrate(queue)
    }

    public func upsertApp(_ app: TrackedApp) throws {
        try queue.write { db in try app.upsert(db) }
    }

    public func allApps() throws -> [TrackedApp] {
        try queue.read { db in try TrackedApp.order(Column("name")).fetchAll(db) }
    }

    @discardableResult
    public func addKeyword(appId: Int, term: String, country: String) throws -> TrackedKeyword {
        try queue.write { db in
            let existing = try TrackedKeyword
                .filter(Column("appId") == appId && Column("term") == term && Column("country") == country)
                .fetchOne(db)
            if let existing { return existing }
            let id = try Int64.fetchOne(db, sql: "SELECT COALESCE(MAX(id),0)+1 FROM trackedKeyword")!
            let keyword = TrackedKeyword(id: id, appId: appId, term: term, country: country)
            try keyword.insert(db)
            return keyword
        }
    }

    public func keywords(appId: Int) throws -> [TrackedKeyword] {
        try queue.read { db in
            try TrackedKeyword.filter(Column("appId") == appId).order(Column("term")).fetchAll(db)
        }
    }

    public func allKeywords() throws -> [TrackedKeyword] {
        try queue.read { db in try TrackedKeyword.fetchAll(db) }
    }

    public func insertRankSnapshot(keywordId: Int64, rank: Int?, at date: Date) throws {
        try queue.write { db in
            var snapshot = RankSnapshot(id: nil, keywordId: keywordId, rank: rank, checkedAt: date)
            try snapshot.insert(db)
        }
    }

    public func latestRank(keywordId: Int64) throws -> RankSnapshot? {
        try queue.read { db in
            try RankSnapshot.filter(Column("keywordId") == keywordId)
                .order(Column("checkedAt").desc).fetchOne(db)
        }
    }

    public func rankHistory(keywordId: Int64, limit: Int = 90) throws -> [RankSnapshot] {
        try queue.read { db in
            try RankSnapshot.filter(Column("keywordId") == keywordId)
                .order(Column("checkedAt").asc).limit(limit).fetchAll(db)
        }
    }
}
```

- [ ] **Step 4: Run storage tests**

Run: `swift test --filter StorageTests`
Expected: 2 tests PASS.

- [ ] **Step 5: Commit storage**

```bash
git add -A && git commit -m "feat: GRDB storage with apps, keywords, and rank snapshot history"
```

- [ ] **Step 6: Write the failing refresh engine test**

`Tests/PodiumKitTests/RefreshEngineTests.swift`:
```swift
import XCTest
import GRDB
@testable import PodiumKit

final class RefreshEngineTests: XCTestCase {
    func testRefreshRecordsSnapshotsAndDiffsChanges() async throws {
        let db = try PodiumDatabase(queue: DatabaseQueue())
        try db.upsertApp(TrackedApp(id: 1, name: "Buki", artworkURL: nil, rating: nil, ratingCount: nil))
        let kw1 = try db.addKeyword(appId: 1, term: "kids drawing", country: "us")
        let kw2 = try db.addKeyword(appId: 1, term: "art scrapbook", country: "us")
        try db.insertRankSnapshot(keywordId: kw1.id, rank: 10, at: Date(timeIntervalSince1970: 1))

        let ranks: [String: Int?] = ["kids drawing": 8, "art scrapbook": nil]
        let engine = RefreshEngine(db: db) { term, _, _ in ranks[term] ?? nil }

        let changes = try await engine.refreshAllKeywords()

        XCTAssertEqual(try db.latestRank(keywordId: kw1.id)?.rank, 8)
        XCTAssertEqual(try db.latestRank(keywordId: kw2.id)?.rank, nil)
        XCTAssertEqual(changes, [
            RankChange(keywordId: kw1.id, term: "kids drawing", country: "us", old: 10, new: 8)
        ])
    }
}
```

- [ ] **Step 7: Run to verify failure**

Run: `swift test --filter RefreshEngineTests`
Expected: compile error — `RefreshEngine` / `RankChange` not defined.

- [ ] **Step 8: Implement refresh engine**

`Sources/PodiumKit/Refresh/RefreshEngine.swift`:
```swift
import Foundation

public struct RankChange: Sendable, Equatable {
    public let keywordId: Int64
    public let term: String
    public let country: String
    public let old: Int?
    public let new: Int?
}

public struct RefreshEngine: Sendable {
    public typealias RankProvider = @Sendable (_ term: String, _ country: String, _ appId: Int) async throws -> Int?

    let db: PodiumDatabase
    let rankProvider: RankProvider
    let now: @Sendable () -> Date

    public init(
        db: PodiumDatabase,
        now: @escaping @Sendable () -> Date = { Date() },
        rankProvider: @escaping RankProvider
    ) {
        self.db = db
        self.now = now
        self.rankProvider = rankProvider
    }

    /// Convenience wiring for production: check ranks via the public App Store client.
    public init(db: PodiumDatabase, client: AppStoreSearchClient) {
        self.init(db: db) { term, country, appId in
            try await client.rank(ofApp: appId, term: term, country: country)
        }
    }

    /// Checks every tracked keyword, appends snapshots, and returns rank changes (old != new only).
    public func refreshAllKeywords() async throws -> [RankChange] {
        var changes: [RankChange] = []
        for keyword in try db.allKeywords() {
            let previous = try db.latestRank(keywordId: keyword.id)?.rank
            let current = try await rankProvider(keyword.term, keyword.country, keyword.appId)
            try db.insertRankSnapshot(keywordId: keyword.id, rank: current, at: now())
            if previous != current {
                changes.append(RankChange(
                    keywordId: keyword.id, term: keyword.term, country: keyword.country,
                    old: previous, new: current))
            }
        }
        return changes
    }
}
```

- [ ] **Step 9: Run all tests**

Run: `swift test`
Expected: full suite PASS (all tasks so far).

- [ ] **Step 10: Commit**

```bash
git add -A && git commit -m "feat: refresh engine with snapshot recording and rank-change diffing"
```

---

### Task 9: Smoke CLI + live contract verification

**Files:**
- Modify: `Sources/PodiumSmoke/main.swift` (replace entirely)

Purpose: manual, real-network verification. Organic mode needs no credentials at all. Ads mode uses env vars and verifies our request/response contracts against the live API — if Apple's field names differ from the Task 6 models, this run surfaces it immediately; fix models + fixtures in the same commit.

- [ ] **Step 1: Implement the CLI (replace main.swift)**

```swift
import Foundation
import PodiumKit

// Usage:
//   swift run podium-smoke rank <appId> <country> <term...>
//   swift run podium-smoke popularity <countryOrRegion>   (needs env credentials)
// Env for ads mode: PODIUM_CLIENT_ID, PODIUM_TEAM_ID, PODIUM_KEY_ID,
//                   PODIUM_PRIVATE_KEY_PATH, PODIUM_ORG_ID

let args = Array(CommandLine.arguments.dropFirst())

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}

guard let command = args.first else {
    fail("usage: podium-smoke rank <appId> <country> <term...> | popularity <countryOrRegion>")
}

switch command {
case "rank":
    guard args.count >= 4, let appId = Int(args[1]) else {
        fail("usage: podium-smoke rank <appId> <country> <term...>")
    }
    let country = args[2]
    let term = args[3...].joined(separator: " ")
    let client = AppStoreSearchClient()
    let rank = try await client.rank(ofApp: appId, term: term, country: country)
    if let app = try await client.lookup(appId: appId, country: country) {
        print("\(app.trackName): rating \(app.averageUserRating ?? 0) (\(app.userRatingCount ?? 0) ratings)")
    }
    print("rank for \"\(term)\" in \(country.uppercased()): \(rank.map(String.init) ?? "not in top 200")")

case "popularity":
    guard args.count == 2 else { fail("usage: podium-smoke popularity <countryOrRegion>") }
    let env = ProcessInfo.processInfo.environment
    guard let clientId = env["PODIUM_CLIENT_ID"], let teamId = env["PODIUM_TEAM_ID"],
          let keyId = env["PODIUM_KEY_ID"], let keyPath = env["PODIUM_PRIVATE_KEY_PATH"],
          let orgId = env["PODIUM_ORG_ID"].flatMap(Int.init) else {
        fail("missing env: PODIUM_CLIENT_ID, PODIUM_TEAM_ID, PODIUM_KEY_ID, PODIUM_PRIVATE_KEY_PATH, PODIUM_ORG_ID")
    }
    let pem = try String(contentsOfFile: keyPath, encoding: .utf8)
    let creds = AdsCredentials(
        clientId: clientId, teamId: teamId, keyId: keyId, privateKeyPEM: pem, orgId: orgId)
    let api = AdsAPIClient(credentials: creds, tokenProvider: TokenProvider(credentials: creds))
    let response = try await api.searchTermPopularity(
        SearchTermPopularityRequest(countryOrRegion: args[1]))
    for row in response.data.prefix(20) {
        print(String(format: "%3d  %3d  %@", row.rank, row.popularity, row.searchTerm))
    }

default:
    fail("unknown command \(command)")
}
```

- [ ] **Step 2: Build and run the organic smoke (no credentials needed)**

Run: `swift run podium-smoke rank 6797999335 us wardrobe outfit`
Expected: prints Samosi's name + rating, and a rank number or "not in top 200". Confirms live iTunes endpoints and our parsing.

- [ ] **Step 3: (When user's Apple Ads credentials exist) run the ads smoke**

Run:
```bash
PODIUM_CLIENT_ID=... PODIUM_TEAM_ID=... PODIUM_KEY_ID=... \
PODIUM_PRIVATE_KEY_PATH=$HOME/.podium/private-key.pem PODIUM_ORG_ID=... \
swift run podium-smoke popularity US
```
Expected: a 20-row table of official top search terms. If a 4xx or decoding error appears, compare the response body with the Task 6 models, adjust field names in `Insights.swift`/`Suggestions.swift` and both fixtures, re-run `swift test`, and include the correction in this task's commit. This step is blocked until the user completes the Apple Ads account setup — do not fake it; leave the checkbox unchecked and note it in the commit message.

- [ ] **Step 4: Run full suite one last time**

Run: `swift test`
Expected: all tests PASS.

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "feat: podium-smoke CLI for live rank checks and Ads API contract verification"
```

---

## Self-review (done at authoring time)

- **Spec coverage:** Auth (Tasks 2–4), AdsAPI insights/suggestions (Tasks 5–6), PublicStore (Task 7), Storage + Refresh/diffing (Task 8), live verification path (Task 9). Reports endpoints and popularity-snapshot storage intentionally deferred to Plan 2 alongside the Ads-performance screen that consumes them — noted here so Plan 2 picks them up.
- **Placeholder scan:** every step carries complete code or an exact command; the single deliberately-unchecked step (Task 9 Step 3) is gated on user credentials and says so.
- **Type consistency:** `PodiumError` defined once (Task 3) and used by Tasks 4–7; `AdsCredentials` (Task 4) used by 5 and 9; `TrackedKeyword.id` is non-optional `Int64` and `RefreshEngine` uses it as such.
