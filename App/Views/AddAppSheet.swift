import SwiftUI
import PodiumKit

struct AddAppSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var results: [StoreApp] = []
    @State private var isSearching = false

    var body: some View {
        VStack(spacing: 0) {
            TextField("Search the App Store (or paste an app name)", text: $query)
                .textFieldStyle(.roundedBorder)
                .padding()
                .onSubmit { search() }
            List(results, id: \.trackId) { app in
                HStack(spacing: 10) {
                    AsyncImage(url: app.artworkUrl100.flatMap(URL.init)) { image in
                        image.resizable()
                    } placeholder: {
                        RoundedRectangle(cornerRadius: 8).fill(.quaternary)
                    }
                    .frame(width: 36, height: 36)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    VStack(alignment: .leading) {
                        Text(app.trackName)
                        if let rating = app.averageUserRating {
                            Text("★ \(rating, specifier: "%.1f") · \(app.userRatingCount ?? 0) ratings")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    Button("Track") {
                        model.addApp(app)
                        dismiss()
                    }
                    .buttonStyle(.glassProminent)
                }
            }
            .overlay {
                if isSearching { ProgressView() }
                else if results.isEmpty && !query.isEmpty {
                    ContentUnavailableView.search(text: query)
                } else if results.isEmpty {
                    ContentUnavailableView(
                        "Search for an app", systemImage: "magnifyingglass",
                        description: Text("Type a name and press Return."))
                }
            }
        }
        .frame(width: 480, height: 420)
        .overlay(alignment: .topTrailing) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.cancelAction)
            .padding(10)
        }
    }

    private func search() {
        isSearching = true
        Task {
            results = (try? await model.storeClient.search(term: query, country: "us")) ?? []
            isSearching = false
        }
    }
}
