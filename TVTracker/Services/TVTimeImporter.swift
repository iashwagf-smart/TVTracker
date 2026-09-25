import Foundation
import SwiftData

/// استيراد ملفات CSV من بيانات TV Time (اللي تطلبها منهم كنسخة من بياناتك)
/// مثل: seen_episode.csv و followed_tv_show.csv و tracking-prod-records.csv
/// الأعمدة تتغير بين نسخ التصدير، فنتعرف عليها بالاسم بشكل مرن.
enum TVTimeImporter {

    struct Record {
        var showName: String
        var tvdbID: Int?
        var season: Int?
        var episode: Int?
        var date: Date?

        var showKey: String { tvdbID.map { "tvdb:\($0)" } ?? "name:\(showName.lowercased())" }
    }

    struct Summary {
        var showsImported = 0
        var episodesMarked = 0
        var failedShows: [String] = []
    }

    enum ImportError: LocalizedError {
        case noUsableColumns
        var errorDescription: String? { "ما لقيت أعمدة مسلسلات في الملفات" }
    }

    // MARK: - Parsing

    private static let showNameColumns = ["tv_show_name", "show_name", "series_name", "tv_show", "show", "series", "title", "name"]
    private static let showIDColumns = ["tv_show_id", "show_id", "series_id", "tvdb_id", "tvdb_show_id", "thetvdb_id"]
    private static let seasonColumns = ["episode_season_number", "season_number", "season"]
    private static let episodeColumns = ["episode_number", "number", "episode"]
    private static let dateColumns = ["watched_at", "seen_at", "created_at", "updated_at", "date"]
    private static let typeColumns = ["type", "entity_type"]

    static func parse(urls: [URL]) throws -> [Record] {
        var records: [Record] = []
        for url in urls {
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            let data = try Data(contentsOf: url)
            guard let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else { continue }
            records += parse(csv: text)
        }
        if records.isEmpty { throw ImportError.noUsableColumns }
        return records
    }

    static func parse(csv text: String) -> [Record] {
        let rows = csvRows(text)
        guard let header = rows.first else { return [] }
        let names = header.map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: "\u{FEFF}", with: "")
                .lowercased()
                .replacingOccurrences(of: " ", with: "_")
        }
        func column(_ candidates: [String]) -> Int? {
            for c in candidates { if let i = names.firstIndex(of: c) { return i } }
            return nil
        }
        let nameCol = column(showNameColumns)
        let idCol = column(showIDColumns)
        guard nameCol != nil || idCol != nil else { return [] }
        let seasonCol = column(seasonColumns)
        let episodeCol = column(episodeColumns)
        let dateCol = column(dateColumns)
        let typeCol = column(typeColumns)

        var result: [Record] = []
        for row in rows.dropFirst() {
            func value(_ i: Int?) -> String? {
                guard let i, i < row.count else { return nil }
                let v = row[i].trimmingCharacters(in: .whitespacesAndNewlines)
                return v.isEmpty ? nil : v
            }
            if let type = value(typeCol)?.lowercased(), type.contains("movie") { continue }
            let name = value(nameCol) ?? ""
            let id = value(idCol).flatMap { Int($0) }
            guard !name.isEmpty || id != nil else { continue }
            result.append(Record(
                showName: name,
                tvdbID: id,
                season: value(seasonCol).flatMap { Int($0) },
                episode: value(episodeCol).flatMap { Int($0) },
                date: value(dateCol).flatMap(parseDate)
            ))
        }
        return result
    }

    /// قارئ CSV يدعم النصوص بين علامات تنصيص
    static func csvRows(_ text: String) -> [[String]] {
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var inQuotes = false
        var iterator = Array(text.unicodeScalars).makeIterator()
        var pending: Unicode.Scalar? = nil

        func next() -> Unicode.Scalar? {
            if let p = pending { pending = nil; return p }
            return iterator.next()
        }

        while let c = next() {
            if inQuotes {
                if c == "\"" {
                    if let n = next() {
                        if n == "\"" { field.unicodeScalars.append("\"") } else { inQuotes = false; pending = n }
                    } else {
                        inQuotes = false
                    }
                } else {
                    field.unicodeScalars.append(c)
                }
            } else {
                switch c {
                case "\"": inQuotes = true
                case ",": row.append(field); field = ""
                case "\n", "\r":
                    if c == "\r", let n = next(), n != "\n" { pending = n }
                    row.append(field); field = ""
                    if !(row.count == 1 && row[0].isEmpty) { rows.append(row) }
                    row = []
                default: field.unicodeScalars.append(c)
                }
            }
        }
        if !field.isEmpty || !row.isEmpty {
            row.append(field)
            rows.append(row)
        }
        return rows
    }

    private static let dateFormatters: [DateFormatter] = [
        "yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd'T'HH:mm:ss.SSSZ", "yyyy-MM-dd'T'HH:mm:ssZ", "yyyy-MM-dd HH:mm", "yyyy-MM-dd",
    ].map { format in
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = format
        return f
    }

    static func parseDate(_ s: String) -> Date? {
        if let d = TVMazeAPI.isoFormatter.date(from: s) { return d }
        for f in dateFormatters { if let d = f.date(from: s) { return d } }
        return nil
    }

    // MARK: - Import

    @MainActor
    static func run(urls: [URL], context: ModelContext,
                    progress: @escaping (Int, Int) -> Void) async throws -> Summary {
        let records = try parse(urls: urls)
        let groups = Dictionary(grouping: records, by: \.showKey)
        var summary = Summary()
        var done = 0
        progress(0, groups.count)

        for (_, group) in groups.sorted(by: { $0.key < $1.key }) {
            let sample = group.first!
            let displayName = group.first(where: { !$0.showName.isEmpty })?.showName ?? sample.showName
            do {
                let remote: TVMazeShow
                if let tvdb = group.compactMap(\.tvdbID).first,
                   let found = try? await TVMazeAPI.lookup(tvdbID: tvdb) {
                    remote = found
                } else if !displayName.isEmpty {
                    remote = try await TVMazeAPI.singleSearch(displayName)
                } else {
                    throw URLError(.fileDoesNotExist)
                }
                let show = try await Library.add(remote, in: context)
                summary.showsImported += 1

                var index: [String: Episode] = [:]
                for ep in show.episodes { index["\(ep.season)x\(ep.number)"] = ep }
                for r in group {
                    guard let s = r.season, let e = r.episode, let ep = index["\(s)x\(e)"] else { continue }
                    if ep.watchedAt == nil {
                        ep.watchedAt = r.date ?? Date()
                        summary.episodesMarked += 1
                    }
                }
                try? context.save()
            } catch {
                summary.failedShows.append(displayName.isEmpty ? "#\(sample.tvdbID ?? 0)" : displayName)
            }
            done += 1
            progress(done, groups.count)
        }
        Library.commit(context)
        return summary
    }
}
