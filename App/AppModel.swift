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

    var rankSort: Int { rank ?? Int.max }
    var popularitySort: Int { popularity ?? -1 }
}

enum SidebarItem: Hashable {
    case app(Int)
    case discover
    case adsPerformance
}

@Observable
@MainActor
final class AppModel {
    var apps: [TrackedApp] = []
    var selectedAppId: Int?
    var destination: SidebarItem?
    var rows: [KeywordRow] = []
    var credentials: AdsCredentials?
    var isRefreshing = false
    var lastError: String?
    var showOnboarding = false
    var showConnectWizard = false
    var lastChanges: [RankChange] = []

    var lastRefreshAt: Date? {
        get { UserDefaults.standard.object(forKey: "lastRefreshAt") as? Date }
        set { UserDefaults.standard.set(newValue, forKey: "lastRefreshAt") }
    }

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
        destination = selectedAppId.map(SidebarItem.app)
        showOnboarding = apps.isEmpty
            && !UserDefaults.standard.bool(forKey: "onboardingDone")

        Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                let autoRefreshSetting = UserDefaults.standard.object(forKey: "autoRefresh")
                guard autoRefreshSetting == nil || UserDefaults.standard.bool(forKey: "autoRefresh") else { return }
                let last = self.lastRefreshAt ?? .distantPast
                if Date().timeIntervalSince(last) > 20 * 3600 {
                    await self.refresh()
                }
            }
        }
    }

    func adsAPI() -> AdsAPIClient? {
        guard let credentials else { return nil }
        return AdsAPIClient(
            credentials: credentials,
            tokenProvider: TokenProvider(credentials: credentials))
    }

    func trackTerm(_ term: String, appId: Int, country: String) {
        try? db.addKeyword(appId: appId, term: term.lowercased(), country: country.lowercased())
        if selectedAppId == appId { reloadRows() }
    }

    func deleteKeyword(_ id: Int64) {
        try? db.deleteKeyword(id: id)
        reloadRows()
    }

    func removeApp(_ id: Int) {
        try? db.deleteApp(id: id)
        reloadApps()
        if selectedAppId == id {
            selectedAppId = apps.first?.id
            destination = selectedAppId.map(SidebarItem.app)
            reloadRows()
        }
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
        destination = .app(app.trackId)
    }

    func addKeyword(term: String, country: String) {
        addKeywords(terms: [term], countries: [country])
    }

    func addKeywords(terms: [String], countries: [String]) {
        guard let appId = selectedAppId else { return }
        for term in terms {
            let trimmed = term.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !trimmed.isEmpty else { continue }
            for country in countries {
                try? db.addKeyword(appId: appId, term: trimmed, country: country.lowercased())
            }
        }
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
            let changes = try await engine.refreshAllKeywords()
            lastChanges = changes
            lastRefreshAt = Date()
            if UserDefaults.standard.bool(forKey: "notifyOnChanges") {
                await Notifier.post(changes: changes)
            }
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
        guard credentials != nil, let appId = selectedAppId, !rows.isEmpty else { return }
        guard let api = adsAPI() else { return }
        let service = PopularityService(api: api)
        let terms = rows.map(\.term)
        let countries = Array(Set(rows.map { $0.country.uppercased() }))
        guard let map = try? await service.popularity(appId: appId, for: terms, countries: countries) else { return }
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
