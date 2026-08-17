import Foundation
import Observation
import PodiumKit

struct KeywordRow: Identifiable, Equatable {
    let id: Int64
    let term: String
    let country: String
    let rank: Int?
    let previousRank: Int?
    let popularity: Int?
    let history: [RankSnapshot]

    var delta: Int? {
        guard let rank, let previousRank else { return nil }
        return previousRank - rank
    }
}

@Observable
@MainActor
final class AppModel {
    var apps: [TrackedApp] = []
    var selectedAppId: Int?
    var rows: [KeywordRow] = []
    var credentials: AdsCredentials?
    var isRefreshing = false
    var lastError: String?
    var showOnboarding = false
    var showConnectWizard = false

    let db: PodiumDatabase
    let storeClient = AppStoreSearchClient()
    private let credentialsStore = CredentialsStore(store: KeychainSecretStore())

    init() {
        do {
            let url = try PodiumPaths.databaseURL()
            self.db = try PodiumDatabase(path: url.path)
        } catch {
            fatalError("Cannot open Podium database: \(error)")
        }
        credentials = try? credentialsStore.load()
        reloadApps()
        if let first = apps.first { select(appId: first.id) }
        showOnboarding = apps.isEmpty
            && !UserDefaults.standard.bool(forKey: "onboardingDone")
    }

    func reloadApps() {
        apps = (try? db.allApps()) ?? []
    }

    func select(appId: Int) {
        selectedAppId = appId
        reloadRows()
    }

    func reloadRows() {
        guard let appId = selectedAppId else { rows = []; return }
        let keywords = (try? db.keywords(appId: appId)) ?? []
        rows = keywords.map { keyword in
            let history = (try? db.rankHistory(keywordId: keyword.id)) ?? []
            let latest = history.last
            let previous = history.dropLast().last
            return KeywordRow(
                id: keyword.id, term: keyword.term, country: keyword.country,
                rank: latest?.rank, previousRank: previous?.rank,
                popularity: nil, history: history)
        }
    }

    func addApp(_ app: StoreApp) {
        try? db.upsertApp(TrackedApp(
            id: app.trackId, name: app.trackName, artworkURL: app.artworkUrl100,
            rating: app.averageUserRating, ratingCount: app.userRatingCount))
        reloadApps()
        select(appId: app.trackId)
    }

    func addKeyword(term: String, country: String) {
        guard let appId = selectedAppId else { return }
        let trimmed = term.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { return }
        try? db.addKeyword(appId: appId, term: trimmed, country: country)
        reloadRows()
        Task { await refresh() }
    }

    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        lastError = nil
        defer { isRefreshing = false }
        do {
            let engine = RefreshEngine(db: db, client: storeClient)
            _ = try await engine.refreshAllKeywords()
            for app in apps {
                if let fresh = try? await storeClient.lookup(appId: app.id, country: "us") {
                    try? db.upsertApp(TrackedApp(
                        id: fresh.trackId, name: fresh.trackName,
                        artworkURL: fresh.artworkUrl100,
                        rating: fresh.averageUserRating, ratingCount: fresh.userRatingCount))
                }
            }
            reloadApps()
            reloadRows()
            await loadPopularity()
        } catch {
            lastError = "Refresh failed: \(error)"
        }
    }

    func loadPopularity() async {
        guard let credentials, !rows.isEmpty else { return }
        let api = AdsAPIClient(
            credentials: credentials,
            tokenProvider: TokenProvider(credentials: credentials))
        let service = PopularityService(api: api)
        let terms = rows.map(\.term)
        let countries = Array(Set(rows.map { $0.country.uppercased() }))
        guard let map = try? await service.popularity(for: terms, countries: countries) else { return }
        rows = rows.map { row in
            KeywordRow(
                id: row.id, term: row.term, country: row.country,
                rank: row.rank, previousRank: row.previousRank,
                popularity: map[row.term.lowercased()], history: row.history)
        }
    }

    func finishOnboarding(with credentials: AdsCredentials?) {
        if let credentials {
            try? credentialsStore.save(credentials)
            self.credentials = credentials
        }
        UserDefaults.standard.set(true, forKey: "onboardingDone")
        showOnboarding = false
        showConnectWizard = false
    }

    func disconnectAds() {
        try? credentialsStore.clear()
        credentials = nil
    }
}
