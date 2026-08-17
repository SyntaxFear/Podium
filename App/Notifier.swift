import Foundation
import UserNotifications
import PodiumKit

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
