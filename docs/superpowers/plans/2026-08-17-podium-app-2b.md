# Podium Mac App — Plan 2B: Discover, Settings, Menu Bar, Notifications

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Complete Podium V1's remaining surfaces: the Discover screen (official top search terms + keyword suggestions), an honest Ads-performance placeholder, a Settings window with CSV export and credentials management, a menu bar presence, rank-change notifications, and daily auto-refresh.

**Architecture:** Sidebar navigation moves from app-id selection to a `SidebarItem` enum (apps / discover / ads). All new pure logic (CSV export) goes into PodiumKit with tests. Notifications and menu bar live in the app target. The same `AppModel` instance is shared across WindowGroup, Settings, and MenuBarExtra scenes.

**Tech Stack:** SwiftUI (macOS 15+), UserNotifications, Swift Charts, PodiumKit.

**Conventions:** run from `/Users/bitcoin/Desktop/Podium`. Package tests: `swift test`. App build: `xcodegen generate && xcodebuild -project Podium.xcodeproj -scheme Podium -configuration Debug -derivedDataPath .build/xcode build`. Work on branch `feat/podium-app-2b`; commit per task; merge to main + push at the end.

---

### Task 1: PodiumKit — CSVExporter (TDD)

**Files:**
- Create: `Sources/PodiumKit/Storage/CSVExporter.swift`
- Test: `Tests/PodiumKitTests/CSVExporterTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
@testable import PodiumKit

final class CSVExporterTests: XCTestCase {
    func testExportsHistoryWithEscaping() {
        let keyword = TrackedKeyword(id: 1, appId: 9, term: "kids, \"art\"", country: "us")
        let history = [
            RankSnapshot(id: 1, keywordId: 1, rank: 12, checkedAt: Date(timeIntervalSince1970: 0)),
            RankSnapshot(id: 2, keywordId: 1, rank: nil, checkedAt: Date(timeIntervalSince1970: 86_400)),
        ]
        let csv = CSVExporter.keywordHistoryCSV(keyword: keyword, history: history)
        let lines = csv.split(separator: "\n").map(String.init)
        XCTAssertEqual(lines[0], "date,term,country,rank")
        XCTAssertTrue(lines[1].hasPrefix("1970-01-01"))
        XCTAssertTrue(lines[1].contains("\"kids, \"\"art\"\"\""))
        XCTAssertTrue(lines[1].hasSuffix(",us,12"))
        XCTAssertTrue(lines[2].hasSuffix(",us,"))
    }
}
```

- [ ] **Step 2: Run to verify failure**

Run: `swift test --filter CSVExporterTests`
Expected: compile error — `CSVExporter` not defined.

- [ ] **Step 3: Implement**

`Sources/PodiumKit/Storage/CSVExporter.swift`:
```swift
import Foundation

public enum CSVExporter {
    public static func keywordHistoryCSV(keyword: TrackedKeyword, history: [RankSnapshot]) -> String {
        let formatter = ISO8601DateFormatter()
        var lines = ["date,term,country,rank"]
        for snapshot in history {
            let rank = snapshot.rank.map(String.init) ?? ""
            lines.append(
                "\(formatter.string(from: snapshot.checkedAt)),\(escape(keyword.term)),\(keyword.country),\(rank)")
        }
        return lines.joined(separator: "\n")
    }

    static func escape(_ field: String) -> String {
        guard field.contains(",") || field.contains("\"") || field.contains("\n") else { return field }
        return "\"\(field.replacingOccurrences(of: "\"", with: "\"\""))\""
    }
}
```

- [ ] **Step 4: Run tests, commit**

Run: `swift test --filter CSVExporterTests` → PASS, then:
```bash
git add -A && git commit -m "feat: CSV exporter for keyword rank history"
```

---

### Task 2: Sidebar destinations + Discover screen

**Files:**
- Modify: `App/AppModel.swift` (add SidebarItem, destination, adsAPI helper, trackTerm)
- Modify: `App/Views/RootView.swift` (selection by SidebarItem, enable Discover/Ads rows)
- Create: `App/Views/DiscoverView.swift`

- [ ] **Step 1: AppModel additions**

Add to `App/AppModel.swift` (top level, below `KeywordRow`):
```swift
enum SidebarItem: Hashable {
    case app(Int)
    case discover
    case adsPerformance
}
```

Add properties to `AppModel`:
```swift
    var destination: SidebarItem?
```

Replace `select(appId:)` wiring: keep `selectedAppId` but set it whenever destination is `.app`. Add:
```swift
    func adsAPI() -> AdsAPIClient? {
        guard let credentials else { return nil }
        return AdsAPIClient(
            credentials: credentials,
            tokenProvider: TokenProvider(credentials: credentials))
    }

    func trackTerm(_ term: String, appId: Int, country: String) {
        try? db.addKeyword(appId: appId, term: term.lowercased(), country: country.lowercased())
        if selectedAppId == appId { reloadRows() }
    }
```

In `init`, after `if let first = apps.first { select(appId: first.id) }` add:
```swift
        destination = selectedAppId.map(SidebarItem.app)
```

- [ ] **Step 2: DiscoverView**

`App/Views/DiscoverView.swift`:
```swift
import SwiftUI
import PodiumKit

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
                Table(terms, id: \.searchTerm) {
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
```

- [ ] **Step 3: RootView rewiring**

Replace the `sidebar` property and detail switch in `App/Views/RootView.swift` entirely with:
```swift
    var body: some View {
        @Bindable var model = model
        Group {
            if model.showOnboarding {
                WizardView()
            } else {
                NavigationSplitView {
                    sidebar
                } detail: {
                    switch model.destination {
                    case .app:
                        KeywordsView()
                    case .discover:
                        DiscoverView()
                    case .adsPerformance:
                        AdsPerformanceView()
                    case nil:
                        ContentUnavailableView(
                            "Add your first app",
                            systemImage: "plus.app",
                            description: Text("Track any App Store app — start with your own."))
                    }
                }
            }
        }
        .sheet(isPresented: $showAddApp) { AddAppSheet() }
        .sheet(isPresented: $model.showConnectWizard) {
            WizardView(connectOnly: true)
                .frame(width: 640, height: 560)
        }
    }

    private var sidebar: some View {
        @Bindable var model = model
        return List(selection: $model.destination) {
            Section("My apps") {
                ForEach(model.apps, id: \.id) { app in
                    HStack(spacing: 10) {
                        AsyncImage(url: app.artworkURL.flatMap(URL.init)) { image in
                            image.resizable()
                        } placeholder: {
                            RoundedRectangle(cornerRadius: 6).fill(.quaternary)
                        }
                        .frame(width: 26, height: 26)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        VStack(alignment: .leading, spacing: 1) {
                            Text(app.name).lineLimit(1)
                            if let rating = app.rating, rating > 0 {
                                Text("★ \(rating, specifier: "%.1f") · \(app.ratingCount ?? 0)")
                                    .font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                    }
                    .tag(SidebarItem.app(app.id))
                }
                Button {
                    showAddApp = true
                } label: {
                    Label("Add app", systemImage: "plus")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.tint)
            }
            Section("Research") {
                Label("Discover", systemImage: "safari").tag(SidebarItem.discover)
                Label("Ads performance", systemImage: "chart.bar").tag(SidebarItem.adsPerformance)
            }
        }
        .navigationSplitViewColumnWidth(min: 190, ideal: 220)
        .safeAreaInset(edge: .bottom) {
            if model.credentials == nil {
                Button {
                    model.showConnectWizard = true
                } label: {
                    Label("Connect Apple Ads", systemImage: "key")
                        .frame(maxWidth: .infinity)
                }
                .padding(10)
            }
        }
        .onChange(of: model.destination) { _, newValue in
            if case .app(let id) = newValue { model.select(appId: id) }
        }
    }
```

- [ ] **Step 4: Stub AdsPerformanceView so this task builds**

Create `App/Views/AdsPerformanceView.swift` (completed in Task 3):
```swift
import SwiftUI

struct AdsPerformanceView: View {
    var body: some View { Text("Ads performance") }
}
```

- [ ] **Step 5: Build + commit**

Run the standard build. Expected: `BUILD SUCCEEDED`.
```bash
git add -A && git commit -m "feat: sidebar destinations and Discover screen with official top terms"
```

---

### Task 3: Ads performance placeholder + Settings window

**Files:**
- Modify: `App/Views/AdsPerformanceView.swift` (replace stub)
- Create: `App/Views/SettingsView.swift`
- Modify: `App/PodiumApp.swift` (add Settings scene)
- Modify: `App/AppModel.swift` (add lastRefreshAt, notifyOnChanges, autoRefresh flags)

- [ ] **Step 1: Replace AdsPerformanceView**

```swift
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
```

- [ ] **Step 2: AppModel additions**

Add properties to `AppModel`:
```swift
    var lastChanges: [RankChange] = []
    var lastRefreshAt: Date? {
        get { UserDefaults.standard.object(forKey: "lastRefreshAt") as? Date }
        set { UserDefaults.standard.set(newValue, forKey: "lastRefreshAt") }
    }
```

In `refresh()`, replace `_ = try await engine.refreshAllKeywords()` with:
```swift
            let changes = try await engine.refreshAllKeywords()
            lastChanges = changes
            lastRefreshAt = Date()
            if UserDefaults.standard.bool(forKey: "notifyOnChanges") {
                await Notifier.post(changes: changes)
            }
```

- [ ] **Step 3: SettingsView**

`App/Views/SettingsView.swift`:
```swift
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
```

- [ ] **Step 4: Notifier + Settings scene**

Create `App/Notifier.swift`:
```swift
import Foundation
import UserNotifications

enum Notifier {
    static func requestPermission() async -> Bool {
        let center = UNUserNotificationCenter.current()
        return (try? await center.requestAuthorization(options: [.alert, .badge])) ?? false
    }

    static func post(changes: [RankChange]) async {
        let meaningful = changes.filter { $0.old != $0.new }
        guard !meaningful.isEmpty else { return }
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized else { return }

        let content = UNMutableNotificationContent()
        content.title = "Keyword rankings moved"
        content.body = meaningful.prefix(3).map { change in
            let from = change.old.map { "#\($0)" } ?? "–"
            let to = change.new.map { "#\($0)" } ?? "out of top 200"
            return "\(change.term): \(from) → \(to)"
        }.joined(separator: "\n")
        let request = UNNotificationRequest(
            identifier: UUID().uuidString, content: content, trigger: nil)
        try? await center.add(request)
    }
}
```

In `App/PodiumApp.swift`, add after the WindowGroup scene:
```swift
        Settings {
            SettingsView().environment(model)
        }
```

- [ ] **Step 5: Build + commit**

Run the standard build. Expected: `BUILD SUCCEEDED`.
```bash
git add -A && git commit -m "feat: settings window with CSV export, notifications, ads placeholder"
```

---

### Task 4: Menu bar + daily auto-refresh

**Files:**
- Modify: `App/PodiumApp.swift` (MenuBarExtra)
- Modify: `App/AppModel.swift` (auto-refresh timer)

- [ ] **Step 1: Auto-refresh timer in AppModel**

At the end of `AppModel.init`, add:
```swift
        Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { _ in
            Task { @MainActor in
                guard UserDefaults.standard.bool(forKey: "autoRefresh") || UserDefaults.standard.object(forKey: "autoRefresh") == nil else { return }
                let last = self.lastRefreshAt ?? .distantPast
                if Date().timeIntervalSince(last) > 20 * 3600 {
                    await self.refresh()
                }
            }
        }
```

- [ ] **Step 2: MenuBarExtra scene**

In `App/PodiumApp.swift`, add after the Settings scene:
```swift
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
                NSApp.windows.first?.makeKeyAndOrderFront(nil)
            }
            Divider()
            Button("Quit Podium") { NSApp.terminate(nil) }
        }
```

- [ ] **Step 3: Build + commit**

Run the standard build. Expected: `BUILD SUCCEEDED`.
```bash
git add -A && git commit -m "feat: menu bar summary and daily auto-refresh"
```

---

### Task 5: Verify, merge, push

- [ ] **Step 1:** `swift test` → all package tests pass (25).
- [ ] **Step 2:** Clean build → `BUILD SUCCEEDED`; launch the app; verify sidebar shows Discover + Ads performance; Discover shows the connect prompt (no credentials yet); Settings window opens via ⌘,; menu bar icon appears.
- [ ] **Step 3:** Merge and push:
```bash
git checkout main && git merge feat/podium-app-2b --no-edit && git branch -d feat/podium-app-2b && git push origin main
```

## Self-review (done at authoring time)

- **Spec coverage (2B slice):** Discover (top terms + track action) ✓, Ads placeholder honest-state ✓, Settings (credentials, refresh, notifications, CSV export) ✓, menu bar ✓, notifications ✓, daily refresh ✓. Campaign reports remain deferred pending live contract verification — stated in-product.
- **Placeholder scan:** the single stub (AdsPerformanceView in Task 2) is replaced in Task 3; all other steps carry complete code.
- **Type consistency:** `SidebarItem` defined once (Task 2) and used by RootView; `Notifier` (Task 3) called from AppModel.refresh and SettingsView; `CSVExporter.keywordHistoryCSV(keyword:history:)` matches Task 1; `AddKeywordSheet.countries` reused by DiscoverView (already public within module).
