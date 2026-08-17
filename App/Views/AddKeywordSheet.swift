import SwiftUI

struct AddKeywordSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var term = ""
    @State private var country = "us"

    static let countries: [(code: String, name: String)] = [
        ("us", "United States"), ("gb", "United Kingdom"), ("de", "Germany"),
        ("fr", "France"), ("es", "Spain"), ("it", "Italy"), ("nl", "Netherlands"),
        ("ge", "Georgia"), ("tr", "Türkiye"), ("pl", "Poland"), ("br", "Brazil"),
        ("mx", "Mexico"), ("ca", "Canada"), ("au", "Australia"), ("in", "India"),
        ("jp", "Japan"), ("kr", "South Korea"), ("cn", "China"), ("ae", "UAE"),
        ("sa", "Saudi Arabia"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Track a keyword").font(.title2.bold())
            TextField("Keyword", text: $term, prompt: Text("e.g. kids drawing"))
                .textFieldStyle(.roundedBorder)
                .onSubmit(add)
            Picker("Country", selection: $country) {
                ForEach(Self.countries, id: \.code) { entry in
                    Text(entry.name).tag(entry.code)
                }
            }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Track") { add() }
                    .buttonStyle(.borderedProminent)
                    .disabled(term.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 380)
    }

    private func add() {
        model.addKeyword(term: term, country: country)
        dismiss()
    }
}
