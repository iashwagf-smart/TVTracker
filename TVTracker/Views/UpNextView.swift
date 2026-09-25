import SwiftUI
import SwiftData

/// الشاشة الرئيسية: الحلقة التالية لكل مسلسل + الحلقات القادمة
struct UpNextView: View {
    @Environment(\.modelContext) private var context
    @Query(filter: #Predicate<Show> { $0.stateRaw == "watching" })
    private var shows: [Show]

    enum Mode: String, CaseIterable { case next = "التالي", upcoming = "القادم" }
    @State private var mode: Mode = .next

    private var toWatch: [Show] {
        shows.filter { $0.nextEpisode != nil }
            .sorted { ($0.lastWatchedAt ?? $0.addedAt) > ($1.lastWatchedAt ?? $1.addedAt) }
    }

    private var upcoming: [(day: Date, episodes: [Episode])] {
        let eps = shows.flatMap(\.episodes).filter { !$0.hasAired && $0.airDate != nil }
        let grouped = Dictionary(grouping: eps) { Calendar.current.startOfDay(for: $0.airDate!) }
        return grouped.keys.sorted().prefix(60).map { day in
            (day, grouped[day]!.sorted { ($0.airDate!, $0.show?.name ?? "") < ($1.airDate!, $1.show?.name ?? "") })
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Picker("", selection: $mode) {
                    ForEach(Mode.allCases, id: \.self) { Text($0.rawValue) }
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)

                switch mode {
                case .next: nextSection
                case .upcoming: upcomingSection
                }
            }
            .listStyle(.plain)
            .navigationTitle("المتابعة")
            .navigationDestination(for: Show.self) { ShowDetailView(show: $0) }
            .refreshable { await Library.refreshAll(in: context, force: true) }
            .overlay {
                if shows.isEmpty {
                    EmptyStateView(icon: "tv", title: "ما عندك مسلسلات",
                                   message: "روح لتبويب البحث وضيف المسلسلات اللي تتابعها")
                }
            }
            .animation(.default, value: toWatch.map(\.id))
        }
    }

    @ViewBuilder
    private var nextSection: some View {
        if toWatch.isEmpty && !shows.isEmpty {
            Text("خلصت كل الحلقات المتاحة 🎉")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .padding(.top, 40)
                .listRowSeparator(.hidden)
        }
        ForEach(toWatch) { show in
            if let ep = show.nextEpisode {
                NavigationLink(value: show) {
                    UpNextRow(show: show, episode: ep)
                }
                .swipeActions(edge: .leading) {
                    Button { withAnimation { Library.toggle(ep) } } label: {
                        Label("شاهدتها", systemImage: "checkmark")
                    }
                    .tint(.accentColor)
                }
            }
        }
    }

    @ViewBuilder
    private var upcomingSection: some View {
        if upcoming.isEmpty && !shows.isEmpty {
            Text("ما فيه حلقات قادمة معلنة")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .padding(.top, 40)
                .listRowSeparator(.hidden)
        }
        ForEach(upcoming, id: \.day) { group in
            Section {
                ForEach(group.episodes) { ep in
                    if let show = ep.show {
                        NavigationLink(value: show) {
                            UpcomingRow(show: show, episode: ep)
                        }
                    }
                }
            } header: {
                HStack {
                    Text(Formatters.dayLabel(group.day))
                    Spacer()
                    Text(Formatters.date(group.day)).foregroundStyle(.secondary)
                }
                .font(.subheadline.bold())
            }
        }
    }
}

private struct UpNextRow: View {
    let show: Show
    let episode: Episode

    var body: some View {
        HStack(spacing: 12) {
            PosterView(url: show.posterURL)
                .frame(width: 64)
            VStack(alignment: .leading, spacing: 4) {
                Text(show.name).font(.headline).lineLimit(1)
                Text(episode.code)
                    .font(.subheadline.monospacedDigit().bold())
                    .foregroundStyle(Color.accentColor)
                Text(episode.name).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                HStack(spacing: 8) {
                    ProgressBar(value: show.progress)
                    let left = show.remainingCount
                    Text(left == 1 ? "باقي حلقة" : "باقي \(left)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .fixedSize()
                }
            }
            Spacer(minLength: 4)
            WatchButton(isWatched: episode.isWatched) {
                withAnimation { Library.toggle(episode) }
            }
        }
        .padding(.vertical, 4)
    }
}

private struct UpcomingRow: View {
    let show: Show
    let episode: Episode

    var body: some View {
        HStack(spacing: 12) {
            PosterView(url: show.posterURL, cornerRadius: 6)
                .frame(width: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(show.name).font(.headline).lineLimit(1)
                Text("\(episode.code) · \(episode.name)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if let network = show.network {
                    Text(network).font(.caption).foregroundStyle(.tertiary)
                }
            }
            Spacer()
            if let d = episode.airDate {
                Text(d, style: .time)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
    }
}
