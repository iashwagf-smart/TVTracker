import Foundation
import SwiftData

/// قاعدة بيانات مشتركة بين التطبيق والويدجت (App Group)
enum SharedStore {
    static var appGroup: String? {
        Bundle.main.object(forInfoDictionaryKey: "AppGroup") as? String
    }

    static let container: ModelContainer = {
        let schema = Schema([Show.self, Episode.self])
        var configs: [ModelConfiguration] = []
        if let group = appGroup,
           FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group) != nil {
            configs.append(ModelConfiguration(schema: schema, groupContainer: .identifier(group)))
        }
        // لو الـ App Group مو مفعل (مثل التثبيت عن طريق SideStore) نستخدم مجلد التطبيق العادي
        configs.append(ModelConfiguration(schema: schema, groupContainer: .none))
        for config in configs {
            if let container = try? ModelContainer(for: schema, configurations: config) {
                return container
            }
        }
        // آخر حل: قاعدة بيانات مؤقتة بالذاكرة بدل ما يقفل التطبيق
        return try! ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true))
    }()

    // MARK: - علامات الويدجت
    // الويدجت يكتب في قاعدة البيانات مباشرة، لكن التطبيق لو كان مفتوح بالخلفية
    // ما يشوف التغيير، فنسجل العلامات هنا ويطبقها التطبيق لما يرجع.

    private static let pendingKey = "pendingWidgetMarks"

    static var defaults: UserDefaults {
        appGroup.flatMap { UserDefaults(suiteName: $0) } ?? .standard
    }

    static func recordWidgetMark(episodeID: Int, date: Date) {
        var marks = defaults.dictionary(forKey: pendingKey) as? [String: Double] ?? [:]
        marks[String(episodeID)] = date.timeIntervalSince1970
        defaults.set(marks, forKey: pendingKey)
    }

    static func takeWidgetMarks() -> [Int: Date] {
        let marks = defaults.dictionary(forKey: pendingKey) as? [String: Double] ?? [:]
        defaults.removeObject(forKey: pendingKey)
        var result: [Int: Date] = [:]
        for (key, value) in marks {
            if let id = Int(key) { result[id] = Date(timeIntervalSince1970: value) }
        }
        return result
    }
}
