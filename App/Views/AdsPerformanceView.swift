import SwiftUI
import Charts
import PodiumKit

struct AdsPerformanceView: View {
    @Environment(AppModel.self) private var model
    @State private var level: ReportLevel = .keywords
    @State private var days = 30
    @State private var rows: [ReportRow] = []
    @State private var grandTotal: ReportMetrics?
    @State private var isLoading = false
    @State private var loadError: String?

    var body: some View {
        Group {
            if model.credentials == nil {
                ContentUnavailableView {
                    Label("Connect Apple Ads", systemImage: "key")
                } description: {
                    Text("See impressions, taps, installs, spend, and Apple's own bid suggestions for your campaigns — read-only, Podium can never touch your budget.")
                } actions: {
                    Button("Connect Apple Ads") { model.showConnectWizard = true }
                        .buttonStyle(.glassProminent)
                }
            } else {
                content
            }
        }
        .navigationTitle("Ads performance")
    }

    private var content: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Picker("Level", selection: $level) {
                    ForEach(ReportLevel.allCases, id: \.self) { level in
                        Text(level.displayName).tag(level)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 420)

                Picker("Window", selection: $days) {
                    Text("7 days").tag(7)
                    Text("30 days").tag(30)
                    Text("90 days").tag(90)
                }
                .frame(maxWidth: 140)

                Spacer()

                Button {
                    Task { await load() }
                } label: {
                    if isLoading { ProgressView().controlSize(.small) }
                    else { Label("Load", systemImage: "arrow.clockwise") }
                }
                .buttonStyle(.glassProminent)
                .disabled(isLoading)
            }
            .padding(12)
            Divider()

            if let grandTotal {
                summaryStrip(grandTotal)
                Divider()
            }

            if let loadError {
                ContentUnavailableView(
                    "Couldn't load", systemImage: "exclamationmark.triangle",
                    description: Text(loadError))
            } else if rows.isEmpty {
                ContentUnavailableView(
                    "No data yet", systemImage: "chart.bar",
                    description: Text("Press Load to pull \(level.displayName.lowercased()) performance for the last \(days) days. If you have no active campaigns, this will stay empty."))
            } else {
                table
            }
        }
    }

    private func summaryStrip(_ totals: ReportMetrics) -> some View {
        GlassEffectContainer(spacing: 12) {
            HStack(spacing: 12) {
                metric("Spend", totals.localSpend.map { String(format: "$%.2f", $0.value) } ?? "–")
                metric("Impressions", totals.impressions.map(formatted) ?? "–")
                metric("Taps", totals.taps.map(formatted) ?? "–")
                metric("Installs", totals.tapInstalls.map(formatted) ?? "–")
                if let cpi = totals.tapInstallCPI?.value, cpi > 0 {
                    metric("Avg CPI", String(format: "$%.2f", cpi))
                }
                Spacer()
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
    }

    private func metric(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.title3.bold())
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 12))
    }

    private func formatted(_ n: Int) -> String {
        n.formatted(.number.grouping(.automatic))
    }

    private var table: some View {
        Table(rows) {
            TableColumn("Name") { row in
                VStack(alignment: .leading, spacing: 2) {
                    Text(rowLabel(row)).fontWeight(.medium)
                    if let status = row.displayStatus ?? row.status {
                        Text(status).font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
            TableColumn("Spend") { row in
                Text(row.totalMetrics?.localSpend.map { String(format: "$%.2f", $0.value) } ?? "–")
                    .monospacedDigit()
            }
            .width(80)
            TableColumn("Impr.") { row in
                Text(row.totalMetrics?.impressions.map(formatted) ?? "–").monospacedDigit()
            }
            .width(80)
            TableColumn("Taps") { row in
                Text(row.totalMetrics?.taps.map(formatted) ?? "–").monospacedDigit()
            }
            .width(70)
            TableColumn("Installs") { row in
                Text(row.totalMetrics?.tapInstalls.map(formatted) ?? "–").monospacedDigit()
            }
            .width(70)
            TableColumn("CPI") { row in
                if let cpi = row.totalMetrics?.tapInstallCPI?.value, cpi > 0 {
                    Text(String(format: "$%.2f", cpi)).monospacedDigit()
                } else { Text("–") }
            }
            .width(70)
            TableColumn("Apple's bid tip") { row in
                if let suggestion = row.insights?.bidRecommendation?.suggestedBidAmount {
                    Text(String(format: "$%.2f", suggestion)).monospacedDigit().foregroundStyle(.tint)
                } else { Text("–").foregroundStyle(.tertiary) }
            }
            .width(110)
            TableColumn("Country") { row in
                Text(row.countryOrRegion ?? "–").foregroundStyle(.secondary)
            }
            .width(70)
        }
    }

    private func rowLabel(_ row: ReportRow) -> String {
        row.searchTermText ?? row.text ?? row.name ?? "—"
    }

    private func load() async {
        guard let api = model.adsAPI() else { return }
        isLoading = true
        loadError = nil
        do {
            let response = try await api.report(
                level, query: ReportsQuery(timeRange: ReportsQuery.trailingDays(days)))
            rows = response.rows
            grandTotal = response.grandTotal
        } catch {
            loadError = "Apple's API said no: \(error). If you have no active campaigns, this is expected."
            rows = []
            grandTotal = nil
        }
        isLoading = false
    }
}
