import SwiftUI

struct AdsPerformanceView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Group {
            if model.credentials == nil {
                ContentUnavailableView {
                    Label("Connect Apple Ads", systemImage: "key")
                } description: {
                    Text("See impressions, taps, installs, and spend for your campaigns — read-only, Podium can never touch your budget.")
                } actions: {
                    Button("Connect Apple Ads") { model.showConnectWizard = true }
                        .buttonStyle(.borderedProminent)
                }
            } else {
                ContentUnavailableView {
                    Label("Reports land in the next update", systemImage: "chart.bar")
                } description: {
                    Text("Campaign reporting ships once the new Apple Ads reporting endpoints are verified against live accounts. Your connection is ready — nothing more to do here.")
                }
            }
        }
        .navigationTitle("Ads performance")
    }
}
