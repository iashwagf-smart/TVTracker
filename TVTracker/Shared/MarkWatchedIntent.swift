import AppIntents
import SwiftData
import WidgetKit

/// زر ✓ في الويدجت
struct MarkEpisodeWatchedIntent: AppIntent {
    static var title: LocalizedStringResource = "تعليم الحلقة كمشاهدة"
    static var isDiscoverable: Bool = false

    @Parameter(title: "Episode ID")
    var episodeID: Int

    init() {}

    init(episodeID: Int) {
        self.episodeID = episodeID
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        let context = SharedStore.container.mainContext
        let id = episodeID
        var descriptor = FetchDescriptor<Episode>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        if let episode = try context.fetch(descriptor).first, episode.watchedAt == nil {
            let now = Date()
            episode.watchedAt = now
            try context.save()
            SharedStore.recordWidgetMark(episodeID: id, date: now)
        }
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}
