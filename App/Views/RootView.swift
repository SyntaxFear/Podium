import SwiftUI
import PodiumKit

struct RootView: View {
    @Environment(AppModel.self) private var model
    @State private var showAddApp = false

    var body: some View {
        @Bindable var model = model
        Group {
            if model.showOnboarding {
                WizardView()
            } else {
                NavigationSplitView {
                    sidebar
                } detail: {
                    if model.selectedAppId != nil {
                        KeywordsView()
                    } else {
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
        return List(selection: $model.selectedAppId) {
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
                    .tag(app.id)
                }
                Button {
                    showAddApp = true
                } label: {
                    Label("Add app", systemImage: "plus")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.tint)
            }
            Section("Coming next") {
                Label("Discover", systemImage: "safari").foregroundStyle(.tertiary)
                Label("Ads performance", systemImage: "chart.bar").foregroundStyle(.tertiary)
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
        .onChange(of: model.selectedAppId) { _, newValue in
            if let newValue { model.select(appId: newValue) }
        }
    }
}
