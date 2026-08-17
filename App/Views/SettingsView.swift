import SwiftUI
import PodiumKit
import UniformTypeIdentifiers

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @AppStorage("notifyOnChanges") private var notifyOnChanges = false
    @AppStorage("autoRefresh") private var autoRefresh = true
    @State private var exportAppId: Int?

    var body: some View {
        Form {
            Section("Apple Ads") {
                if model.credentials != nil {
                    LabeledContent("Status", value: "Connected")
                    Button("Disconnect", role: .destructive) { model.disconnectAds() }
                } else {
                    LabeledContent("Status", value: "Not connected")
                    Button("Connect Apple Ads") { model.showConnectWizard = true }
                }
            }
            Section("Refresh") {
                Toggle("Refresh automatically every day", isOn: $autoRefresh)
                LabeledContent(
                    "Last refresh",
                    value: model.lastRefreshAt?.formatted(date: .abbreviated, time: .shortened) ?? "Never")
            }
            Section("Notifications") {
                Toggle("Notify me when a rank changes", isOn: $notifyOnChanges)
                    .onChange(of: notifyOnChanges) { _, enabled in
                        if enabled { Task { _ = await Notifier.requestPermission() } }
                    }
            }
            Section("Export") {
                Picker("App", selection: $exportAppId) {
                    ForEach(model.apps, id: \.id) { app in
                        Text(app.name).tag(Optional(app.id))
                    }
                }
                Button("Export keyword history as CSV") { exportCSV() }
                    .disabled(exportAppId == nil)
            }
        }
        .formStyle(.grouped)
        .frame(width: 440)
        .onAppear { if exportAppId == nil { exportAppId = model.apps.first?.id } }
    }

    private func exportCSV() {
        guard let appId = exportAppId else { return }
        let keywords = (try? model.db.keywords(appId: appId)) ?? []
        var csv = "date,term,country,rank"
        for keyword in keywords {
            let history = (try? model.db.rankHistory(keywordId: keyword.id)) ?? []
            let body = CSVExporter.keywordHistoryCSV(keyword: keyword, history: history)
            csv += "\n" + body.split(separator: "\n").dropFirst().joined(separator: "\n")
        }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.nameFieldStringValue = "podium-keywords.csv"
        if panel.runModal() == .OK, let url = panel.url {
            try? csv.write(to: url, atomically: true, encoding: .utf8)
        }
    }
}
