import SwiftUI

struct AddKeywordSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var input = ""
    @State private var selectedCountries: Set<String> = ["us"]

    static let countries: [(code: String, name: String)] = [
        ("us", "United States"), ("gb", "United Kingdom"), ("de", "Germany"),
        ("fr", "France"), ("es", "Spain"), ("it", "Italy"), ("nl", "Netherlands"),
        ("ge", "Georgia"), ("tr", "Türkiye"), ("pl", "Poland"), ("br", "Brazil"),
        ("mx", "Mexico"), ("ca", "Canada"), ("au", "Australia"), ("in", "India"),
        ("jp", "Japan"), ("kr", "South Korea"), ("cn", "China"), ("ae", "UAE"),
        ("sa", "Saudi Arabia"),
    ]

    private var parsedTerms: [String] {
        input
            .split(whereSeparator: { $0.isNewline || $0 == "," })
            .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
            .filter { !$0.isEmpty }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Track keywords").font(.title2.bold())
            Text("One per line or comma-separated — add as many as you want.")
                .font(.callout).foregroundStyle(.secondary)
            TextEditor(text: $input)
                .font(.body)
                .frame(height: 110)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(.quaternary))
                .overlay(alignment: .topLeading) {
                    if input.isEmpty {
                        Text("kids drawing\nart scrapbook, coloring book")
                            .foregroundStyle(.tertiary)
                            .padding(.top, 8).padding(.leading, 6)
                            .allowsHitTesting(false)
                    }
                }

            Text("Countries").font(.headline)
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), alignment: .leading)], alignment: .leading, spacing: 6) {
                    ForEach(Self.countries, id: \.code) { entry in
                        Toggle(isOn: Binding(
                            get: { selectedCountries.contains(entry.code) },
                            set: { on in
                                if on { selectedCountries.insert(entry.code) }
                                else { selectedCountries.remove(entry.code) }
                            })) {
                            Text(entry.name).lineLimit(1)
                        }
                        .toggleStyle(.checkbox)
                    }
                }
            }
            .frame(height: 130)

            HStack {
                Text(summary).font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Track all") { add() }
                    .buttonStyle(.borderedProminent)
                    .disabled(parsedTerms.isEmpty || selectedCountries.isEmpty)
            }
        }
        .padding(24)
        .frame(width: 480)
    }

    private var summary: String {
        let pairs = parsedTerms.count * selectedCountries.count
        guard pairs > 0 else { return "Nothing to track yet" }
        return "\(parsedTerms.count) keywords × \(selectedCountries.count) countries = \(pairs) tracked pairs"
    }

    private func add() {
        model.addKeywords(terms: parsedTerms, countries: Array(selectedCountries))
        dismiss()
    }
}
