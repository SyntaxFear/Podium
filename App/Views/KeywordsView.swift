import SwiftUI
import Charts
import PodiumKit

struct KeywordsView: View {
    @Environment(AppModel.self) private var model
    @State private var showAddKeyword = false
    @State private var detailRow: KeywordRow?

    private var appName: String {
        model.apps.first(where: { $0.id == model.selectedAppId })?.name ?? ""
    }

    var body: some View {
        Group {
            if model.rows.isEmpty {
                ContentUnavailableView(
                    "No keywords yet", systemImage: "key",
                    description: Text("Add the search terms people would use to find \(appName)."))
            } else {
                Table(model.rows) {
                    TableColumn("Keyword") { row in
                        Text(row.term).fontWeight(.medium)
                    }
                    TableColumn("Popularity") { row in
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
                    TableColumn("My rank") { row in
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
                    TableColumn("Country") { row in
                        Text(row.country.uppercased()).foregroundStyle(.secondary)
                    }
                    .width(70)
                    TableColumn("") { row in
                        Button("History") { detailRow = row }
                            .buttonStyle(.link)
                    }
                    .width(60)
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
                    Task { await model.refresh() }
                } label: {
                    if model.isRefreshing { ProgressView().controlSize(.small) }
                    else { Label("Refresh", systemImage: "arrow.clockwise") }
                }
                .disabled(model.isRefreshing)
            }
        }
        .sheet(isPresented: $showAddKeyword) { AddKeywordSheet() }
        .sheet(item: $detailRow) { row in RankHistorySheet(row: row) }
        .task { await model.loadPopularity() }
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
