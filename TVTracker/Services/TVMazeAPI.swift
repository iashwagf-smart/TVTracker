import Foundation

/// واجهة TVmaze المجانية — لا تحتاج مفتاح API
struct TVMazeShow: Decodable, Identifiable, Hashable {
    let id: Int
    let name: String
    let genres: [String]?
    let status: String?
    let runtime: Int?
    let averageRuntime: Int?
    let premiered: String?
    let rating: Rating?
    let network: Channel?
    let webChannel: Channel?
    let image: ImageSet?
    let summary: String?

    struct Rating: Decodable, Hashable { let average: Double? }
    struct Channel: Decodable, Hashable { let name: String }
    struct ImageSet: Decodable, Hashable {
        let medium: String?
        let original: String?
    }

    var year: String? { premiered.map { String($0.prefix(4)) } }
    var channelName: String? { network?.name ?? webChannel?.name }
}

struct TVMazeEpisode: Decodable {
    let id: Int
    let name: String?
    let season: Int
    let number: Int?
    let airdate: String?
    let airstamp: String?
    let runtime: Int?
    let image: TVMazeShow.ImageSet?
    let summary: String?

    var date: Date? {
        if let airstamp, let d = TVMazeAPI.isoFormatter.date(from: airstamp) { return d }
        if let airdate, !airdate.isEmpty { return TVMazeAPI.dayFormatter.date(from: airdate) }
        return nil
    }
}

private struct SearchResult: Decodable {
    let show: TVMazeShow
}

enum TVMazeAPI {
    private static let base = URL(string: "https://api.tvmaze.com")!

    static let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    static func search(_ query: String) async throws -> [TVMazeShow] {
        var comps = URLComponents(url: base.appendingPathComponent("search/shows"), resolvingAgainstBaseURL: false)!
        comps.queryItems = [URLQueryItem(name: "q", value: query)]
        let results: [SearchResult] = try await get(comps.url!)
        return results.map(\.show)
    }

    static func show(id: Int) async throws -> TVMazeShow {
        try await get(base.appendingPathComponent("shows/\(id)"))
    }

    static func episodes(showID: Int) async throws -> [TVMazeEpisode] {
        let all: [TVMazeEpisode] = try await get(base.appendingPathComponent("shows/\(showID)/episodes"))
        return all.filter { $0.number != nil }
    }

    private static func get<T: Decodable>(_ url: URL, attempt: Int = 0) async throws -> T {
        let (data, response) = try await URLSession.shared.data(from: url)
        if let http = response as? HTTPURLResponse, http.statusCode == 429, attempt < 3 {
            // TVmaze يحد الطلبات؛ ننتظر ونعيد المحاولة
            try await Task.sleep(nanoseconds: UInt64(attempt + 1) * 1_500_000_000)
            return try await get(url, attempt: attempt + 1)
        }
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw URLError(.badServerResponse)
        }
        return try JSONDecoder().decode(T.self, from: data)
    }
}

extension String {
    /// إزالة وسوم HTML من الملخصات
    var strippingHTML: String {
        replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
