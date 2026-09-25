import Foundation
import SwiftData
import UserNotifications

/// إشعارات محلية وقت نزول الحلقات الجديدة للمسلسلات اللي تتابعها
@MainActor
enum EpisodeNotifications {
    private static let enabledKey = "notificationsEnabled"
    /// iOS يسمح بـ 64 إشعار معلّق كحد أقصى
    private static let maxPending = 60

    static var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: enabledKey) }
        set { UserDefaults.standard.set(newValue, forKey: enabledKey) }
    }

    /// يطلب الإذن ويرجع هل انقبل
    static func enable(context: ModelContext) async -> Bool {
        let granted = (try? await UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        isEnabled = granted
        await reschedule(context: context)
        return granted
    }

    static func disable() {
        isEnabled = false
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
    }

    static func reschedule(context: ModelContext) async {
        let center = UNUserNotificationCenter.current()
        center.removeAllPendingNotificationRequests()
        guard isEnabled else { return }

        let now = Date()
        let descriptor = FetchDescriptor<Episode>(
            predicate: #Predicate { $0.airDate != nil && $0.watchedAt == nil },
            sortBy: [SortDescriptor(\.airDate)]
        )
        let upcoming = ((try? context.fetch(descriptor)) ?? [])
            .filter { ep in
                guard let date = ep.airDate, date > now else { return false }
                return ep.show?.state == .watching
            }
            .prefix(maxPending)

        for ep in upcoming {
            guard let date = ep.airDate, let show = ep.show else { continue }
            let content = UNMutableNotificationContent()
            content.title = show.name
            content.body = "نزلت \(ep.code)" + (ep.name.isEmpty ? "" : " · \(ep.name)")
            content.sound = .default
            content.threadIdentifier = "show-\(show.id)"

            let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
            let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
            let request = UNNotificationRequest(identifier: "ep-\(ep.id)", content: content, trigger: trigger)
            try? await center.add(request)
        }
    }
}
