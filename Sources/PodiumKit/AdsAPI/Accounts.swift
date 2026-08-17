import Foundation

/// GET /v1/me — identity of the authenticated caller.
public struct MeInfo: Decodable, Sendable, Equatable {
    public let orgId: Int?
    public let userId: Int?
}

/// GET /v1/acls — ad accounts and roles the caller can access.
public struct UserAcl: Decodable, Sendable, Equatable {
    public struct AdAccountRef: Decodable, Sendable, Equatable {
        public let id: Int?
        public let name: String?
        public let orgId: Int?
    }
    public let adAccount: AdAccountRef?
    public let roles: [String]?
}

/// Some endpoints wrap payloads in {"data": …}; tolerate both shapes.
struct DataEnvelope<T: Decodable>: Decodable {
    let data: T
}

extension AdsAPIClient {
    public func me() async throws -> MeInfo {
        do {
            let wrapped: DataEnvelope<MeInfo> = try await get("me")
            return wrapped.data
        } catch {
            return try await get("me")
        }
    }

    public func acls() async throws -> [UserAcl] {
        do {
            let wrapped: DataEnvelope<[UserAcl]> = try await get("acls")
            return wrapped.data
        } catch {
            return try await get("acls")
        }
    }
}
