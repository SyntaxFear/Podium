import SwiftUI
import PodiumKit

struct RootView: View {
    @Environment(AppModel.self) private var model
    @State private var showAddApp = false
    @State private var appPendingRemoval: TrackedApp?

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
                    .contextMenu {
                        Button("Remove app…", role: .destructive) { appPendingRemoval = app }
                    }
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
                .buttonStyle(.glassProminent)
                .padding(10)
            }
        }
        .onChange(of: model.destination) { _, newValue in
            if case .app(let id) = newValue { model.select(appId: id) }
        }
        .confirmationDialog(
            "Remove \(appPendingRemoval?.name ?? "app")?",
            isPresented: Binding(
                get: { appPendingRemoval != nil },
                set: { if !$0 { appPendingRemoval = nil } })
        ) {
            Button("Remove app and history", role: .destructive) {
                if let app = appPendingRemoval { model.removeApp(app.id) }
                appPendingRemoval = nil
            }
            Button("Cancel", role: .cancel) { appPendingRemoval = nil }
        } message: {
            Text("All tracked keywords and rank history for this app will be deleted.")
        }
    }
}
