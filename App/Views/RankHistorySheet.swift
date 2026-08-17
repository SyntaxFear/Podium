import SwiftUI
import Charts
import PodiumKit

struct RankHistorySheet: View {
    @Environment(\.dismiss) private var dismiss
    let row: KeywordRow

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading) {
                    Text(row.term).font(.title2.bold())
                    Text("Rank history · \(row.country.uppercased())")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Close") { dismiss() }
            }
            let points = row.history.filter { $0.rank != nil }
            if points.count < 2 {
                ContentUnavailableView(
                    "Not enough data yet", systemImage: "chart.xyaxis.line",
                    description: Text("Refresh daily for a few days and the chart fills in."))
                    .frame(height: 260)
            } else {
                Chart(points, id: \.id) { snapshot in
                    LineMark(
                        x: .value("Date", snapshot.checkedAt),
                        y: .value("Rank", snapshot.rank ?? 200))
                    PointMark(
                        x: .value("Date", snapshot.checkedAt),
                        y: .value("Rank", snapshot.rank ?? 200))
                }
                .chartYScale(domain: .automatic(reversed: true))
                .chartYAxisLabel("Rank (lower is better)")
                .frame(height: 260)
            }
        }
        .padding(24)
        .frame(width: 560)
    }
}
