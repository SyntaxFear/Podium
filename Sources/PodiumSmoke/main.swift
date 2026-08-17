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

case "seed":
    // Dev helper: podium-smoke seed <appId> <country> <terms-comma-separated> [demoHistoryDays]
    // Adds the app + keywords with a real current rank snapshot. With demoHistoryDays > 0 it
    // also writes deterministic synthetic history — for screenshots and UI work only.
    guard args.count >= 4, let appId = Int(args[1]) else {
        fail("usage: podium-smoke seed <appId> <country> <terms-comma-separated> [demoHistoryDays]")
    }
    let country = args[2]
    let terms = args[3].split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
    let demoDays = args.count >= 5 ? (Int(args[4]) ?? 0) : 0
    let db = try PodiumDatabase(path: PodiumPaths.databaseURL().path)
    let client = AppStoreSearchClient()
    guard let app = try await client.lookup(appId: appId, country: country) else {
        fail("app \(appId) not found in \(country)")
    }
    try db.upsertApp(TrackedApp(
        id: app.trackId, name: app.trackName, artworkURL: app.artworkUrl100,
        rating: app.averageUserRating, ratingCount: app.userRatingCount))
    var rng: UInt64 = 42
    func pseudoRandom(_ bound: Int) -> Int {
        rng = rng &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        return Int(rng >> 33) % bound
    }
    for term in terms {
        let keyword = try db.addKeyword(appId: appId, term: term.lowercased(), country: country.lowercased())
        let current = try await client.rank(ofApp: appId, term: term, country: country)
        if demoDays > 0 {
            var rank = current ?? (15 + pseudoRandom(40))
            for day in stride(from: demoDays, through: 1, by: -1) {
                rank = max(1, min(200, rank + pseudoRandom(7) - 3))
                try db.insertRankSnapshot(
                    keywordId: keyword.id, rank: rank,
                    at: Date().addingTimeInterval(TimeInterval(-day * 86_400)))
            }
        }
        try db.insertRankSnapshot(keywordId: keyword.id, rank: current, at: Date())
        print("\(term): rank \(current.map(String.init) ?? "–")")
    }
    print("seeded \(terms.count) keywords for \(app.trackName)")

default:
    fail("unknown command \(command)")
}
