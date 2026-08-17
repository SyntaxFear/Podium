import SwiftUI
import PodiumKit

extension SearchTermPopularity: @retroactive Identifiable {
    public var id: String { searchTerm }
}

struct DiscoverView: View {
    @Environment(AppModel.self) private var model

    static let genres: [(name: String, id: Int?)] = [
        ("All categories", nil), ("Books", 6018), ("Business", 6000),
        ("Developer Tools", 6026), ("Education", 6017), ("Entertainment", 6016),
        ("Finance", 6015), ("Food & Drink", 6023), ("Games", 6014),
        ("Graphics & Design", 6027), ("Health & Fitness", 6013), ("Lifestyle", 6012),
        ("Medical", 6020), ("Music", 6011), ("Navigation", 6010), ("News", 6009),
        ("Photo & Video", 6008), ("Productivity", 6007), ("Reference", 6006),
        ("Shopping", 6024), ("Social Networking", 6005), ("Sports", 6004),
        ("Travel", 6003), ("Utilities", 6002),
    ]

    @State private var country = "US"
    @State private var genreId: Int?
    @State private var granularity: SearchTermPopularityRequest.Granularity = .weekly
    @State private var terms: [SearchTermPopularity] = []
    @State private var isLoading = false
    @State private var loadError: String?
    @State private var trackTargetAppId: Int?

    var body: some View {
        Group {
            if model.credentials == nil {
                ContentUnavailableView {
                    Label("Connect Apple Ads", systemImage: "key")
                } description: {
                    Text("Discover shows Apple's official most-searched terms and popularity scores. Connect your free Apple Ads account to unlock it.")
                } actions: {
                    Button("Connect Apple Ads") { model.showConnectWizard = true }
                        .buttonStyle(.borderedProminent)
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
                Picker("Country", selection: $country) {
                    ForEach(AddKeywordSheet.countries, id: \.code) { entry in
                        Text(entry.name).tag(entry.code.uppercased())
                    }
                }
                .frame(maxWidth: 200)
                Picker("Category", selection: $genreId) {
                    ForEach(Self.genres, id: \.id) { genre in
                        Text(genre.name).tag(genre.id)
                    }
                }
                .frame(maxWidth: 220)
                Picker("Period", selection: $granularity) {
                    Text("Weekly").tag(SearchTermPopularityRequest.Granularity.weekly)
                    Text("Monthly").tag(SearchTermPopularityRequest.Granularity.monthly)
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
                .disabled(isLoading)
            }
            .padding(12)
            Divider()
            if let loadError {
                ContentUnavailableView(
                    "Couldn't load", systemImage: "exclamationmark.triangle",
                    description: Text(loadError))
            } else if terms.isEmpty {
                ContentUnavailableView(
                    "Official top search terms", systemImage: "safari",
                    description: Text("Pick a country and category, then press Load."))
            } else {
                Table(terms) {
                    TableColumn("#") { term in
                        Text("\(term.rank)").monospacedDigit().foregroundStyle(.secondary)
                    }
                    .width(40)
                    TableColumn("Search term") { term in
                        Text(term.searchTerm).fontWeight(.medium)
                    }
                    TableColumn("Popularity") { term in
                        HStack(spacing: 6) {
                            ProgressView(value: Double(term.popularity), total: 100)
                                .frame(width: 80)
                            Text("\(term.popularity)").monospacedDigit()
                        }
                    }
                    .width(140)
                    TableColumn("") { term in
                        Button("Track") {
                            if let appId = trackTargetAppId {
                                model.trackTerm(term.searchTerm, appId: appId, country: country.lowercased())
                            }
                        }
                        .buttonStyle(.link)
                        .disabled(trackTargetAppId == nil)
                    }
                    .width(60)
                }
            }
        }
        .onAppear { if trackTargetAppId == nil { trackTargetAppId = model.selectedAppId ?? model.apps.first?.id } }
    }

    private func load() async {
        guard let api = model.adsAPI() else { return }
        isLoading = true
        loadError = nil
        do {
            let response = try await api.searchTermPopularity(
                SearchTermPopularityRequest(countryOrRegion: country, genreId: genreId, granularity: granularity))
            terms = response.data
        } catch {
            loadError = "Apple's API said no: \(error). If this persists, your API credentials may lack permissions."
        }
        isLoading = false
    }
}
