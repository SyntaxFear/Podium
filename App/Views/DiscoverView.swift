import SwiftUI
import PodiumKit

struct DiscoverView: View {
    @Environment(AppModel.self) private var model

    static let genres: [String] = [
        "ALL", "BOOKS", "BUSINESS", "DEVELOPER_TOOLS", "EDUCATION", "ENTERTAINMENT",
        "FINANCE", "FOOD_DRINK", "GAMES", "GRAPHICS_DESIGN", "HEALTH_FITNESS",
        "LIFESTYLE", "MEDICAL", "MUSIC", "NAVIGATION", "NEWS", "PHOTO_VIDEO",
        "PRODUCTIVITY", "PRODUCTIVITY_UTILITIES", "REFERENCE", "SHOPPING",
        "SOCIAL_NETWORKING", "SPORTS", "TRAVEL", "UTILITIES",
    ]

    @State private var selectedCountries: Set<String> = ["US"]
    @State private var genre = "ALL"
    @State private var granularity = SearchTermPopularityQuery.Granularity.weekly
    @State private var rows: [SearchTermPopularityRow] = []
    @State private var totalCount: Int?
    @State private var isLoading = false
    @State private var loadError: String?
    @State private var trackTargetAppId: Int?
    @State private var trackedTerms: Set<String> = []

    var body: some View {
        Group {
            if model.credentials == nil {
                ContentUnavailableView {
                    Label("Connect Apple Ads", systemImage: "key")
                } description: {
                    Text("Discover shows Apple's official most-searched terms — up to 500 per country and category — with popularity scores. Connect your free Apple Ads account to unlock it.")
                } actions: {
                    Button("Connect Apple Ads") { model.showConnectWizard = true }
                        .buttonStyle(.glassProminent)
                }
            } else {
                content
            }
        }
        .navigationTitle("Discover")
    }

    private var content: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Menu {
                    ForEach(AddKeywordSheet.countries, id: \.code) { entry in
                        Toggle(entry.name, isOn: Binding(
                            get: { selectedCountries.contains(entry.code.uppercased()) },
                            set: { on in
                                let code = entry.code.uppercased()
                                if on { selectedCountries.insert(code) }
                                else { selectedCountries.remove(code) }
                            }))
                    }
                } label: {
                    Label(
                        selectedCountries.isEmpty
                            ? "Countries"
                            : selectedCountries.sorted().joined(separator: ", "),
                        systemImage: "globe")
                        .lineLimit(1)
                }
                .frame(maxWidth: 240)

                Picker("Category", selection: $genre) {
                    ForEach(Self.genres, id: \.self) { name in
                        Text(name.replacingOccurrences(of: "_", with: " ").capitalized).tag(name)
                    }
                }
                .frame(maxWidth: 220)

                Picker("Period", selection: $granularity) {
                    Text("Weekly").tag(SearchTermPopularityQuery.Granularity.weekly)
                    Text("Monthly").tag(SearchTermPopularityQuery.Granularity.monthly)
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 180)

                Spacer()

                Picker("Track into", selection: $trackTargetAppId) {
                    ForEach(model.apps, id: \.id) { app in
                        Text(app.name).tag(Optional(app.id))
                    }
                }
                .frame(maxWidth: 200)

                Button {
                    Task { await load() }
                } label: {
                    if isLoading { ProgressView().controlSize(.small) }
                    else { Label("Load", systemImage: "arrow.clockwise") }
                }
                .buttonStyle(.glassProminent)
                .disabled(isLoading || selectedCountries.isEmpty)
            }
            .padding(12)
            Divider()
            if let loadError {
                ContentUnavailableView(
                    "Couldn't load", systemImage: "exclamationmark.triangle",
                    description: Text(loadError))
            } else if rows.isEmpty {
                ContentUnavailableView(
                    "Official top search terms", systemImage: "safari",
                    description: Text("Pick countries and a category, then press Load. Apple publishes up to 500 terms per country and category."))
            } else {
                table
                if let totalCount {
                    Text("\(rows.count) of \(totalCount) terms")
                        .font(.caption).foregroundStyle(.secondary)
                        .padding(6)
                }
            }
        }
        .onAppear {
            if trackTargetAppId == nil { trackTargetAppId = model.selectedAppId ?? model.apps.first?.id }
        }
    }

    private var table: some View {
        Table(rows) {
            TableColumn("#") { row in
                Text(row.rankInGenre.map(String.init) ?? "–")
                    .monospacedDigit().foregroundStyle(.secondary)
            }
            .width(44)
            TableColumn("Search term") { row in
                Text(row.searchTerm).fontWeight(.medium)
            }
            TableColumn("Country") { row in
                Text(row.countryOrRegion ?? "–").foregroundStyle(.secondary)
            }
            .width(64)
            TableColumn("Popularity") { row in
                if let score = row.searchPopularity1to100 {
                    HStack(spacing: 6) {
                        ProgressView(value: Double(score), total: 100).frame(width: 70)
                        Text("\(score)").monospacedDigit()
                    }
                } else { Text("–").foregroundStyle(.tertiary) }
            }
            .width(130)
            TableColumn("In category") { row in
                Text(row.searchPopularityInGenre.map(String.init) ?? "–").monospacedDigit()
            }
            .width(84)
            TableColumn("Scale 1–5") { row in
                Text(row.searchPopularity1to5.map { String(repeating: "●", count: $0) } ?? "–")
                    .foregroundStyle(.tint)
            }
            .width(70)
            TableColumn("Week") { row in
                Text(row.week ?? row.month ?? "–")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .width(90)
            TableColumn("") { row in
                if trackedTerms.contains(row.id) {
                    Label("Tracked", systemImage: "checkmark").font(.caption)
                        .foregroundStyle(.green)
                } else {
                    Button("Track") {
                        if let appId = trackTargetAppId {
                            model.trackTerm(
                                row.searchTerm, appId: appId,
                                country: (row.countryOrRegion ?? "US").lowercased())
                            trackedTerms.insert(row.id)
                        }
                    }
                    .buttonStyle(.link)
                    .disabled(trackTargetAppId == nil)
                }
            }
            .width(70)
        }
    }

    private func load() async {
        guard let api = model.adsAPI() else { return }
        isLoading = true
        loadError = nil
        trackedTerms.removeAll()
        let window = SearchTermPopularityQuery.latestWindow(granularity: granularity)
        var collected: [SearchTermPopularityRow] = []
        var total = 0
        do {
            for country in selectedCountries.sorted() {
                var filters = [APIFilter(field: "countryOrRegion", op: "EQUALS", value: [country])]
                if genre != "ALL" {
                    filters.append(APIFilter(field: "genre", op: "EQUALS", value: [genre]))
                }
                let response = try await api.searchTermPopularity(
                    SearchTermPopularityQuery(
                        timeRange: window, filters: filters,
                        sorting: [APISort(field: "rankInGenre", order: "ASC")],
                        pagination: APIPage(offset: 0, pageSize: 500)))
                collected.append(contentsOf: response.rows)
                total += response.pagination?.totalCount ?? response.rows.count
            }
            rows = collected
            totalCount = total
        } catch {
            loadError = "Apple's API said no: \(error)"
        }
        isLoading = false
    }
}
