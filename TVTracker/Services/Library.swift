import Foundation
import SwiftData

/// كل عمليات الإضافة والتحديث والتعليم كمشاهد
@MainActor
enum Library {

    static func existingShow(id: Int, in context: ModelContext) -> Show? {
        var descriptor = FetchDescriptor<Show>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    @discardableResult
    static func add(_ remote: TVMazeShow, state: TrackingState = .watching, in context: ModelContext) async throws -> Show {
        if let existing = existingShow(id: remote.id, in: context) {
            return existing
        }
        let episodes = try await TVMazeAPI.episodes(showID: remote.id)
        if let existing = existingShow(id: remote.id, in: context) {
            return existing
        }
        let show = Show(id: remote.id, name: remote.name)
        show.state = state
        apply(remote, to: show)
        context.insert(show)
        merge(episodes, into: show, in: context)
        show.lastSynced = Date()
        try? context.save()
        return show
    }

    static func refresh(_ show: Show, in context: ModelContext) async throws {
        async let remote = TVMazeAPI.show(id: show.id)
        async let episodes = TVMazeAPI.episodes(showID: show.id)
        let (r, eps) = try await (remote, episodes)
        apply(r, to: show)
        merge(eps, into: show, in: context)
        show.lastSynced = Date()
        try? context.save()
    }

    /// يحدّث المسلسلات اللي ما انتهت (أو كل شيء لو force)
    static func refreshAll(in context: ModelContext, force: Bool = false) async {
        let shows = (try? context.fetch(FetchDescriptor<Show>())) ?? []
        let staleDate = Date().addingTimeInterval(-6 * 3600)
        for show in shows {
            let isStale = (show.lastSynced ?? .distantPast) < staleDate
            guard force || (isStale && !show.isEnded) else { continue }
            try? await refresh(show, in: context)
        }
    }

    private static func apply(_ remote: TVMazeShow, to show: Show) {
        show.name = remote.name
        show.posterURL = remote.image?.medium ?? remote.image?.original
        show.bannerURL = remote.image?.original ?? remote.image?.medium
        show.summary = remote.summary?.strippingHTML
        show.airStatus = remote.status
        show.network = remote.channelName
        show.genres = remote.genres ?? []
        show.premiered = remote.premiered
        show.runtime = remote.averageRuntime ?? remote.runtime
        show.rating = remote.rating?.average
    }

    private static func merge(_ remote: [TVMazeEpisode], into show: Show, in context: ModelContext) {
        var existing = Dictionary(show.episodes.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        for r in remote {
            guard let number = r.number else { continue }
            let ep: Episode
            if let found = existing.removeValue(forKey: r.id) {
                ep = found
            } else {
                ep = Episode(id: r.id, season: r.season, number: number, name: r.name ?? "")
                context.insert(ep)
                ep.show = show
            }
            ep.season = r.season
            ep.number = number
            ep.name = r.name ?? ""
            ep.airDate = r.date
            ep.runtime = r.runtime
            ep.summary = r.summary?.strippingHTML
            ep.imageURL = r.image?.medium
        }
        // حلقات انحذفت من المصدر: نحذفها إذا ما شاهدتها
        for (_, orphan) in existing where !orphan.isWatched {
            context.delete(orphan)
        }
    }

    // MARK: - المشاهدة

    static func toggle(_ episode: Episode) {
        episode.watchedAt = episode.isWatched ? nil : Date()
    }

    static func markWatched(_ episodes: [Episode]) {
        let now = Date()
        for ep in episodes where !ep.isWatched && ep.hasAired {
            ep.watchedAt = now
        }
    }

    static func markUnwatched(_ episodes: [Episode]) {
        for ep in episodes { ep.watchedAt = nil }
    }

    /// يعلّم هذه الحلقة وكل ما قبلها كمشاهدة
    static func markUpTo(_ episode: Episode) {
        guard let show = episode.show else { return }
        let before = show.sortedEpisodes.filter {
            ($0.season, $0.number) <= (episode.season, episode.number)
        }
        markWatched(before)
    }
}

// MARK: - النسخ الاحتياطي

struct Backup: Codable {
    struct ShowEntry: Codable {
        var id: Int
        var name: String
        var state: String
        var isFavorite: Bool
        var addedAt: Date
        var watched: [WatchedEntry]
    }
    struct WatchedEntry: Codable {
        var episodeID: Int
        var watchedAt: Date
    }
    var version = 1
    var exportedAt = Date()
    var shows: [ShowEntry]
}

@MainActor
extension Library {
    static func exportBackup(from context: ModelContext) throws -> URL {
        let shows = try context.fetch(FetchDescriptor<Show>())
        let backup = Backup(shows: shows.map { s in
            Backup.ShowEntry(
                id: s.id, name: s.name, state: s.stateRaw, isFavorite: s.isFavorite, addedAt: s.addedAt,
                watched: s.episodes.compactMap { e in
                    e.watchedAt.map { Backup.WatchedEntry(episodeID: e.id, watchedAt: $0) }
                })
        })
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(backup)
        let stamp = TVMazeAPI.dayFormatter.string(from: Date())
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("TVTracker-\(stamp).json")
        try data.write(to: url)
        return url
    }

    /// يرجع عدد المسلسلات اللي تم استيرادها
    static func importBackup(from url: URL, into context: ModelContext) async throws -> Int {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let backup = try decoder.decode(Backup.self, from: data)

        var count = 0
        for entry in backup.shows {
            let show: Show
            if let existing = existingShow(id: entry.id, in: context) {
                show = existing
            } else {
                let remote = try await TVMazeAPI.show(id: entry.id)
                show = try await add(remote, in: context)
            }
            show.stateRaw = entry.state
            show.isFavorite = entry.isFavorite
            show.addedAt = entry.addedAt
            let watched = Dictionary(entry.watched.map { ($0.episodeID, $0.watchedAt) }, uniquingKeysWith: { a, _ in a })
            for ep in show.episodes {
                if let date = watched[ep.id] { ep.watchedAt = date }
            }
            count += 1
        }
        try? context.save()
        return count
    }
}
