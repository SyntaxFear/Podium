import SwiftUI
import PodiumKit

struct CompareSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var showAddCompetitor = false

    private var appName: String {
        model.apps.first(where: { $0.id == model.selectedAppId })?.name ?? "your app"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Compare").font(.title2.bold())
                    Text("\(appName) vs. tracked competitors, on your shared keywords")
                        .font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Add competitor") { showAddCompetitor = true }
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3).foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.cancelAction)
            }
            .padding(16)
            Divider()

            if model.competitorRows.isEmpty {
                ContentUnavailableView {
                    Label("No competitors yet", systemImage: "person.2")
                } description: {
                    Text("Add a competitor app to see their rank next to yours on every keyword you track.")
                } actions: {
                    Button("Add competitor") { showAddCompetitor = true }
                        .buttonStyle(.borderedProminent)
                }
            } else if model.rows.isEmpty {
                ContentUnavailableView(
                    "Track a keyword first", systemImage: "key",
                    description: Text("Add keywords to \(appName) to compare ranks."))
            } else {
                table
            }
        }
        .frame(width: 700, height: 460)
        .sheet(isPresented: $showAddCompetitor) { AddCompetitorSheet() }
    }

    private var table: some View {
        ScrollView([.horizontal, .vertical]) {
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 10) {
                GridRow {
                    Text("Keyword").font(.caption.bold()).foregroundStyle(.secondary)
                    Text(appName).font(.caption.bold())
                    ForEach(model.competitorRows) { competitor in
                        HStack(spacing: 4) {
                            Text(competitor.name).font(.caption.bold()).lineLimit(1)
                            Button {
                                model.removeCompetitor(competitor.id)
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.caption2).foregroundStyle(.tertiary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                Divider().gridCellColumns(2 + model.competitorRows.count)

                ForEach(model.rows) { row in
                    GridRow {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(row.term)
                            Text(row.country.uppercased()).font(.caption2).foregroundStyle(.tertiary)
                        }
                        rankBadge(row.rank, isMine: true)
                        ForEach(model.competitorRows) { competitor in
                            rankBadge(competitor.ranks[row.id].flatMap { $0 }, isMine: false)
                        }
                    }
                }
            }
            .padding(16)
        }
    }

    @ViewBuilder
    private func rankBadge(_ rank: Int?, isMine: Bool) -> some View {
        if let rank {
            Text("#\(rank)")
                .fontWeight(isMine ? .bold : .regular)
                .foregroundStyle(isMine ? .primary : .secondary)
        } else {
            Text("–").foregroundStyle(.tertiary)
        }
    }
}

struct AddCompetitorSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var results: [StoreApp] = []
    @State private var isSearching = false

    var body: some View {
        VStack(spacing: 0) {
            TextField("Search the App Store for a competitor", text: $query)
                .textFieldStyle(.roundedBorder)
                .padding()
                .onSubmit { search() }
            List(results, id: \.trackId) { app in
                HStack(spacing: 10) {
                    AsyncImage(url: app.artworkUrl100.flatMap(URL.init)) { image in
                        image.resizable()
                    } placeholder: {
                        RoundedRectangle(cornerRadius: 8).fill(.quaternary)
                    }
                    .frame(width: 36, height: 36)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    Text(app.trackName)
                    Spacer()
                    Button("Add") {
                        model.addCompetitor(app)
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .overlay {
                if isSearching { ProgressView() }
                else if results.isEmpty {
                    ContentUnavailableView(
                        "Search for a competitor", systemImage: "magnifyingglass",
                        description: Text("Type a name and press Return."))
                }
            }
        }
        .frame(width: 460, height: 400)
        .overlay(alignment: .topTrailing) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3).foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.cancelAction)
            .padding(10)
        }
    }

    private func search() {
        isSearching = true
        Task {
            results = (try? await model.storeClient.search(term: query, country: "us")) ?? []
            isSearching = false
        }
    }
}
