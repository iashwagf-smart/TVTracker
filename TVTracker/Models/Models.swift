import Foundation
import SwiftData

/// حالة المسلسل عند المستخدم
enum TrackingState: String, Codable, CaseIterable, Identifiable {
    case watching   // أتابعه
    case later      // للمشاهدة لاحقاً
    case stopped    // توقفت عنه

    var id: String { rawValue }

    var title: String {
        switch self {
        case .watching: "أتابعه"
        case .later: "لاحقاً"
        case .stopped: "توقفت"
        }
    }

    var icon: String {
        switch self {
        case .watching: "play.circle.fill"
        case .later: "bookmark.fill"
        case .stopped: "pause.circle.fill"
        }
    }
}

@Model
final class Show {
    @Attribute(.unique) var id: Int
    var name: String
    var posterURL: String?
    var bannerURL: String?
    var summary: String?
    /// حالة العرض من المصدر: Running / Ended / To Be Determined ...
    var airStatus: String?
    var network: String?
    var genres: [String] = []
    var premiered: String?
    var runtime: Int?
    var rating: Double?
    var stateRaw: String = TrackingState.watching.rawValue
    var isFavorite: Bool = false
    var addedAt: Date = Date()
    var lastSynced: Date?

    @Relationship(deleteRule: .cascade, inverse: \Episode.show)
    var episodes: [Episode] = []

    init(id: Int, name: String) {
        self.id = id
        self.name = name
    }

    var state: TrackingState {
        get { TrackingState(rawValue: stateRaw) ?? .watching }
        set { stateRaw = newValue.rawValue }
    }

    var sortedEpisodes: [Episode] {
        episodes.sorted { ($0.season, $0.number) < ($1.season, $1.number) }
    }

    var airedEpisodes: [Episode] {
        sortedEpisodes.filter(\.hasAired)
    }

    var watchedCount: Int { episodes.filter(\.isWatched).count }

    var airedCount: Int { episodes.filter(\.hasAired).count }

    var remainingCount: Int { episodes.filter { $0.hasAired && !$0.isWatched }.count }

    var progress: Double {
        let total = airedCount
        return total == 0 ? 0 : Double(watchedCount) / Double(total)
    }

    /// أول حلقة معروضة ولم تُشاهد
    var nextEpisode: Episode? {
        sortedEpisodes.first { $0.hasAired && !$0.isWatched }
    }

    /// أقرب حلقة قادمة لم تُعرض بعد
    var upcomingEpisode: Episode? {
        sortedEpisodes.first { !$0.hasAired && $0.airDate != nil }
    }

    var lastWatchedAt: Date? {
        episodes.compactMap(\.watchedAt).max()
    }

    var isEnded: Bool { airStatus == "Ended" }

    /// شاهدت كل الحلقات والمسلسل انتهى
    var isCompleted: Bool { isEnded && airedCount > 0 && remainingCount == 0 }

    /// شاهدت كل المعروض والمسلسل مستمر
    var isUpToDate: Bool { !isEnded && airedCount > 0 && remainingCount == 0 }

    var seasons: [Int] {
        Array(Set(episodes.map(\.season))).sorted()
    }

    func episodes(inSeason season: Int) -> [Episode] {
        episodes.filter { $0.season == season }.sorted { $0.number < $1.number }
    }

    var airStatusArabic: String? {
        switch airStatus {
        case "Running": "مستمر"
        case "Ended": "منتهي"
        case "To Be Determined": "غير محدد"
        case "In Development": "قيد التطوير"
        case nil: nil
        default: airStatus
        }
    }
}

@Model
final class Episode {
    @Attribute(.unique) var id: Int
    var season: Int
    var number: Int
    var name: String
    var airDate: Date?
    var runtime: Int?
    var summary: String?
    var imageURL: String?
    var watchedAt: Date?
    var show: Show?

    init(id: Int, season: Int, number: Int, name: String) {
        self.id = id
        self.season = season
        self.number = number
        self.name = name
    }

    var isWatched: Bool { watchedAt != nil }

    var hasAired: Bool {
        guard let airDate else { return false }
        return airDate <= Date()
    }

    var code: String { String(format: "S%02dE%02d", season, number) }

    var effectiveRuntime: Int { runtime ?? show?.runtime ?? 0 }
}
