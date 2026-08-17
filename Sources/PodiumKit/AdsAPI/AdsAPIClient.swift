import Foundation

public struct AdsAPIClient: Sendable {
    /// Apple Ads Platform API v1 host (per official docs; supersedes api.searchads.apple.com).
    public static let defaultBaseURL = URL(string: "https://api.ads.apple.com/v1")!

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
            if let accountId = credentials.adAccountId ?? credentials.orgId {
                request.setValue("adAccountId=\(accountId)", forHTTPHeaderField: "X-AP-Context")
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
                if attempt > maxRetries {
                    if status == 429 { throw PodiumError.rateLimited }
                    throw PodiumError.http(status: status, body: String(decoding: data, as: UTF8.self))
                }
                let retryAfter = (response as? HTTPURLResponse)?
                    .value(forHTTPHeaderField: "Retry-After").flatMap(Double.init)
                await sleep(.seconds(retryAfter ?? Double(1 << (attempt - 1))))
                continue
            default:
                throw PodiumError.http(status: status, body: String(decoding: data, as: UTF8.self))
            }
        }
    }
}
