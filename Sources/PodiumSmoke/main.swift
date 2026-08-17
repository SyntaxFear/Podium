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
