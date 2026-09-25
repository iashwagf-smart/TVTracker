import WidgetKit
import SwiftUI
import SwiftData
import AppIntents

// MARK: - Data

struct UpNextItem: Identifiable {
    let id: Int            // episode id
    let showName: String
    let code: String
    let episodeName: String
    let remaining: Int
    let poster: UIImage?
}

struct UpNextEntry: TimelineEntry {
    let date: Date
    let items: [UpNextItem]
    var isPlaceholder = false

    static let placeholder = UpNextEntry(date: Date(), items: [
        UpNextItem(id: 1, showName: "Severance", code: "S02E05", episodeName: "Trojan's Horse", remaining: 6, poster: nil),
        UpNextItem(id: 2, showName: "The Bear", code: "S03E02", episodeName: "Next", remaining: 9, poster: nil),
        UpNextItem(id: 3, showName: "Shōgun", code: "S01E07", episodeName: "A Stick of Time", remaining: 4, poster: nil),
    ], isPlaceholder: true)
}

struct UpNextProvider: TimelineProvider {
    func placeholder(in context: Context) -> UpNextEntry { .placeholder }

    func getSnapshot(in context: Context, completion: @escaping (UpNextEntry) -> Void) {
        if context.isPreview {
            completion(.placeholder)
            return
        }
        Task {
            completion(await Self.load(limit: Self.limit(for: context.family)))
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<UpNextEntry>) -> Void) {
        Task {
            let entry = await Self.load(limit: Self.limit(for: context.family))
            let next = Calendar.current.date(byAdding: .hour, value: 1, to: Date()) ?? Date()
            completion(Timeline(entries: [entry], policy: .after(next)))
        }
    }

    static func limit(for family: WidgetFamily) -> Int {
        switch family {
        case .systemSmall: 1
        case .systemMedium: 2
        default: 5
        }
    }

    @MainActor
    static func load(limit: Int) async -> UpNextEntry {
        let context = SharedStore.container.mainContext
        let descriptor = FetchDescriptor<Show>(predicate: #Predicate { $0.stateRaw == "watching" })
        let shows = (try? context.fetch(descriptor)) ?? []
        let ranked = shows
            .filter { $0.nextEpisode != nil }
            .sorted { ($0.lastWatchedAt ?? $0.addedAt) > ($1.lastWatchedAt ?? $1.addedAt) }
            .prefix(limit)

        var items: [UpNextItem] = []
        for show in ranked {
            guard let ep = show.nextEpisode else { continue }
            items.append(UpNextItem(
                id: ep.id,
                showName: show.name,
                code: ep.code,
                episodeName: ep.name,
                remaining: show.remainingCount,
                poster: await loadImage(show.posterURL)
            ))
        }
        return UpNextEntry(date: Date(), items: items)
    }

    private static func loadImage(_ string: String?) async -> UIImage? {
        guard let string, let url = URL(string: string),
              let result = try? await URLSession.shared.data(from: url),
              let image = UIImage(data: result.0) else { return nil }
        // نصغّر الصورة عشان ذاكرة الويدجت محدودة
        let size = CGSize(width: 120, height: 180)
        return UIGraphicsImageRenderer(size: size).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
    }
}

// MARK: - Views

private let accent = Color(red: 1, green: 0.83, blue: 0)

struct UpNextWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: UpNextEntry

    var body: some View {
        Group {
            if entry.items.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.title)
                        .foregroundStyle(accent)
                    Text("ما عندك حلقات متبقية")
                        .font(.caption)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                }
            } else if family == .systemSmall, let item = entry.items.first {
                SmallItemView(item: item)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Text("التالي")
                        .font(.caption.bold())
                        .foregroundStyle(accent)
                    ForEach(entry.items) { item in
                        RowItemView(item: item)
                    }
                    Spacer(minLength: 0)
                }
            }
        }
        .redacted(reason: entry.isPlaceholder ? .placeholder : [])
        .containerBackground(for: .widget) {
            LinearGradient(colors: [Color(white: 0.13), Color(white: 0.04)], startPoint: .top, endPoint: .bottom)
        }
    }
}

private struct PosterThumb: View {
    let image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                ZStack {
                    Color(white: 0.2)
                    Image(systemName: "tv").foregroundStyle(.secondary)
                }
            }
        }
        .aspectRatio(2/3, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
    }
}

private struct CheckButton: View {
    let episodeID: Int

    var body: some View {
        Button(intent: MarkEpisodeWatchedIntent(episodeID: episodeID)) {
            Image(systemName: "checkmark.circle.fill")
                .font(.title2)
                .foregroundStyle(accent)
        }
        .buttonStyle(.plain)
    }
}

private struct SmallItemView: View {
    let item: UpNextItem

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .top) {
                PosterThumb(image: item.poster).frame(width: 44)
                Spacer()
                CheckButton(episodeID: item.id)
            }
            Spacer(minLength: 0)
            Text(item.showName).font(.subheadline.bold()).lineLimit(1)
            Text(item.code).font(.caption.monospacedDigit().bold()).foregroundStyle(accent)
            Text(item.episodeName).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
        }
    }
}

private struct RowItemView: View {
    let item: UpNextItem

    var body: some View {
        HStack(spacing: 10) {
            PosterThumb(image: item.poster).frame(width: 30)
            VStack(alignment: .leading, spacing: 1) {
                Text(item.showName).font(.subheadline.bold()).lineLimit(1)
                HStack(spacing: 4) {
                    Text(item.code).monospacedDigit().foregroundStyle(accent)
                    Text(item.episodeName).foregroundStyle(.secondary).lineLimit(1)
                }
                .font(.caption)
            }
            Spacer(minLength: 4)
            Text("\(item.remaining)")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
            CheckButton(episodeID: item.id)
        }
    }
}

// MARK: - Widget

struct UpNextWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "UpNextWidget", provider: UpNextProvider()) { entry in
            UpNextWidgetView(entry: entry)
        }
        .configurationDisplayName("الحلقة التالية")
        .description("حلقاتك الجاية مع زر تعليمها كمشاهدة.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

@main
struct TVTrackerWidgetBundle: WidgetBundle {
    var body: some Widget {
        UpNextWidget()
    }
}
