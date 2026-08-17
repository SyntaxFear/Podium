import SwiftUI

@main
struct PodiumApp: App {
    @State private var model = AppModel()
    @Environment(\.openWindow) private var openWindow

    var body: some Scene {
        WindowGroup(id: "main") {
            RootView()
                .environment(model)
                .frame(minWidth: 860, minHeight: 520)
        }

        Settings {
            SettingsView().environment(model)
        }

        MenuBarExtra("Podium", systemImage: "chart.line.uptrend.xyaxis") {
            if model.lastChanges.isEmpty {
                Text(model.lastRefreshAt.map {
                    "No rank changes · \($0.formatted(date: .omitted, time: .shortened))"
                } ?? "No data yet — refresh")
            } else {
                ForEach(model.lastChanges.prefix(5), id: \.keywordId) { change in
                    let from = change.old.map { "#\($0)" } ?? "–"
                    let to = change.new.map { "#\($0)" } ?? "out"
                    Text("\(change.term): \(from) → \(to)")
                }
            }
            Divider()
            Button("Refresh now") { Task { await model.refresh() } }
            Button("Open Podium") {
                NSApp.activate(ignoringOtherApps: true)
                openWindow(id: "main")
            }
            Divider()
            Button("Quit Podium") { NSApp.terminate(nil) }
        }
    }
}
