import SwiftUI
import Charts
import PodiumKit

struct KeywordsView: View {
    @Environment(AppModel.self) private var model
    @State private var showAddKeyword = false
    @State private var showCompare = false
    @State private var detailRow: KeywordRow?
    @State private var selection = Set<KeywordRow.ID>()
    @State private var sortOrder = [KeyPathComparator(\KeywordRow.rankSort)]

    private var appName: String {
        model.apps.first(where: { $0.id == model.selectedAppId })?.name ?? ""
    }

    private var sortedRows: [KeywordRow] {
        model.rows.sorted(using: sortOrder)
    }

    var body: some View {
        Group {
            if model.rows.isEmpty {
                ContentUnavailableView(
                    "No keywords yet", systemImage: "key",
                    description: Text("Add the search terms people would use to find \(appName)."))
            } else {
                Table(sortedRows, selection: $selection, sortOrder: $sortOrder) {
                    TableColumn("Keyword", value: \.term) { row in
                        Text(row.term).fontWeight(.medium)
                    }
                    TableColumn("Popularity", value: \.popularitySort) { row in
                        if let popularity = row.popularity {
                            HStack(spacing: 6) {
                                ProgressView(value: Double(popularity), total: 100)
                                    .frame(width: 60)
                                Text("\(popularity)").monospacedDigit()
                            }
                        } else {
                            Text(model.credentials == nil ? "—" : "…")
                                .foregroundStyle(.tertiary)
                                .help(model.credentials == nil
                                    ? "Connect Apple Ads to see official popularity"
                                    : "No official score for this term yet")
                        }
                    }
                    .width(120)
                    TableColumn("My rank", value: \.rankSort) { row in
                        HStack(spacing: 4) {
                            Text(row.rank.map { "#\($0)" } ?? "–")
                                .monospacedDigit().fontWeight(.semibold)
                            if let delta = row.delta, delta != 0 {
                                Text(delta > 0 ? "▲\(delta)" : "▼\(-delta)")
                                    .font(.caption)
                                    .foregroundStyle(delta > 0 ? .green : .red)
                            }
                        }
                    }
                    .width(90)
                    TableColumn("30 days") { row in
                        sparkline(row.history)
                    }
                    .width(130)
                    TableColumn("Country", value: \.country) { row in
                        Text(row.country.uppercased()).foregroundStyle(.secondary)
                    }
                    .width(70)
                    TableColumn("") { row in
                        Button("History") { detailRow = row }
                            .buttonStyle(.link)
                    }
                    .width(60)
                }
                .contextMenu(forSelectionType: KeywordRow.ID.self) { ids in
                    if !ids.isEmpty {
                        Button("Stop tracking", role: .destructive) {
                            ids.forEach { model.deleteKeyword($0) }
                        }
                    }
                } primaryAction: { ids in
                    if let id = ids.first, let row = model.rows.first(where: { $0.id == id }) {
                        detailRow = row
                    }
                }
                .onDeleteCommand {
                    selection.forEach { model.deleteKeyword($0) }
                    selection.removeAll()
                }
            }
        }
        .navigationTitle(appName)
        .navigationSubtitle("\(model.rows.count) keywords")
        .toolbar {
            ToolbarItem {
                Button {
                    showAddKeyword = true
                } label: {
                    Label("Add keyword", systemImage: "plus")
                }
            }
            ToolbarItem {
                Button {
                    showCompare = true
                } label: {
                    Label("Compare", systemImage: "person.2")
                }
            }
            ToolbarItem {
                Button {
                    Task { await model.refresh() }
                } label: {
                    if model.isRefreshing { ProgressView().controlSize(.small) }
                    else { Label("Refresh", systemImage: "arrow.clockwise") }
                }
                .disabled(model.isRefreshing)
            }
        }
        .sheet(isPresented: $showAddKeyword) { AddKeywordSheet() }
        .sheet(isPresented: $showCompare) { CompareSheet() }
        .sheet(item: $detailRow) { row in RankHistorySheet(row: row) }
        .task(id: model.selectedAppId) { await model.loadPopularity() }
        .onChange(of: model.selectedAppId) { _, _ in selection.removeAll() }
        .onChange(of: model.rows) { _, _ in model.reloadCompetitors() }
        .overlay(alignment: .bottom) {
            if let error = model.lastError {
                Text(error)
                    .font(.caption).foregroundStyle(.white)
                    .padding(8)
                    .background(.red.opacity(0.85), in: Capsule())
                    .padding()
            }
        }
    }

    @ViewBuilder
    private func sparkline(_ history: [RankSnapshot]) -> some View {
        let points = history.filter { $0.rank != nil }
        if points.count < 2 {
            Text("collecting…").font(.caption2).foregroundStyle(.tertiary)
        } else {
            Chart(points, id: \.id) { snapshot in
                LineMark(
                    x: .value("Date", snapshot.checkedAt),
                    y: .value("Rank", snapshot.rank ?? 200))
            }
            .chartYScale(domain: .automatic(reversed: true))
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
            .frame(height: 24)
        }
    }
}
