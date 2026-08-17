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
