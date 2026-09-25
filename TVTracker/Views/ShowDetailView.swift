import SwiftUI
import SwiftData

struct ShowDetailView: View {
    @Bindable var show: Show
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var expandedSeasons: Set<Int> = []
    @State private var isRefreshing = false
    @State private var confirmDelete = false
    @State private var selectedEpisode: Episode?

    var body: some View {
        List {
            header
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)

            if let next = show.nextEpisode {
                Section("الحلقة التالية") {
                    EpisodeRow(episode: next, showCode: true) { selectedEpisode = next }
                }
            } else if let upcoming = show.upcomingEpisode, let date = upcoming.airDate {
                Section("الحلقة القادمة") {
                    HStack {
                        Text("\(upcoming.code) · \(upcoming.name)").lineLimit(1)
                        Spacer()
                        Text(Formatters.dayLabel(date)).foregroundStyle(Color.accentColor)
                    }
                }
            }

            ForEach(show.seasons, id: \.self) { season in
                seasonSection(season)
            }

            if let summary = show.summary, !summary.isEmpty {
                Section("القصة") {
                    Text(summary).font(.callout).foregroundStyle(.secondary)
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(show.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbar }
        .refreshable { try? await Library.refresh(show, in: context) }
        .sheet(item: $selectedEpisode) { ep in
            EpisodeDetailSheet(episode: ep)
                .presentationDetents([.medium, .large])
        }
        .confirmationDialog("حذف \(show.name)؟", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("حذف المسلسل وسجل المشاهدة", role: .destructive) {
                let target = show
                dismiss()
                // نحذف بعد ما تسكر الصفحة عشان ما تنعرض بيانات محذوفة
                Task {
                    try? await Task.sleep(nanoseconds: 500_000_000)
                    context.delete(target)
                    try? context.save()
                }
            }
        }
        .onAppear {
            if expandedSeasons.isEmpty {
                // نفتح الموسم اللي فيه الحلقة التالية
                if let s = show.nextEpisode?.season { expandedSeasons = [s] }
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        ZStack(alignment: .bottom) {
            Color.black
                .frame(height: 260)
                .overlay {
                    AsyncImage(url: show.bannerURL.flatMap(URL.init(string:))) { img in
                        img.resizable().scaledToFill().blur(radius: 2)
                    } placeholder: { Color.black }
                }
                .overlay(LinearGradient(colors: [.black.opacity(0.2), .black.opacity(0.95)],
                                        startPoint: .top, endPoint: .bottom))
                .clipped()

            HStack(alignment: .bottom, spacing: 14) {
                PosterView(url: show.posterURL)
                    .frame(width: 100)
                    .shadow(radius: 8)
                VStack(alignment: .leading, spacing: 6) {
                    Text(show.name).font(.title2.bold()).lineLimit(2)
                    HStack(spacing: 6) {
                        if let network = show.network { Text(network) }
                        if let status = show.airStatusArabic { Text("· \(status)") }
                    }
                    .font(.caption).foregroundStyle(.secondary)
                    Text("\(show.watchedCount) من \(show.airedCount) حلقة")
                        .font(.caption.monospacedDigit())
                    ProgressBar(value: show.progress, height: 5)
                    if show.remainingCount > 0 {
                        let minutes = show.airedEpisodes.filter { !$0.isWatched }.reduce(0) { $0 + $1.effectiveRuntime }
                        Text("باقي \(Formatters.duration(minutes: minutes))")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
            .padding()
        }
        .frame(height: 260, alignment: .bottom)
    }

    // MARK: - Seasons

    @ViewBuilder
    private func seasonSection(_ season: Int) -> some View {
        let eps = show.episodes(inSeason: season)
        let aired = eps.filter(\.hasAired)
        let watched = aired.filter(\.isWatched).count
        let allWatched = !aired.isEmpty && watched == aired.count
        let isExpanded = expandedSeasons.contains(season)

        Section {
            Button {
                withAnimation {
                    if isExpanded { expandedSeasons.remove(season) } else { expandedSeasons.insert(season) }
                }
            } label: {
                HStack {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.forward")
                        .foregroundStyle(.secondary)
                        .frame(width: 16)
                    Text("الموسم \(season)").font(.headline)
                    Spacer()
                    Text("\(watched)/\(eps.count)")
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.secondary)
                    WatchButton(isWatched: allWatched) {
                        withAnimation {
                            if allWatched { Library.markUnwatched(eps) } else { Library.markWatched(eps) }
                        }
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                ForEach(eps) { ep in
                    EpisodeRow(episode: ep, showCode: false) { selectedEpisode = ep }
                }
            }
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                show.isFavorite.toggle()
            } label: {
                Image(systemName: show.isFavorite ? "heart.fill" : "heart")
                    .foregroundStyle(show.isFavorite ? Color.red : Color.primary)
            }
        }
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Picker("الحالة", selection: $show.stateRaw) {
                    ForEach(TrackingState.allCases) { state in
                        Label(state.title, systemImage: state.icon).tag(state.rawValue)
                    }
                }
                Divider()
                Button {
                    withAnimation { Library.markWatched(show.episodes) }
                } label: {
                    Label("شاهدت كل الحلقات", systemImage: "checkmark.circle")
                }
                Button {
                    Task {
                        isRefreshing = true
                        try? await Library.refresh(show, in: context)
                        isRefreshing = false
                    }
                } label: {
                    Label("تحديث الحلقات", systemImage: "arrow.clockwise")
                }
                Divider()
                Button(role: .destructive) {
                    confirmDelete = true
                } label: {
                    Label("حذف المسلسل", systemImage: "trash")
                }
            } label: {
                if isRefreshing { ProgressView() } else { Image(systemName: "ellipsis.circle") }
            }
        }
    }
}

// MARK: - Episode row

struct EpisodeRow: View {
    let episode: Episode
    let showCode: Bool
    let onTap: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Text(showCode ? episode.code : "\(episode.number)")
                .font(.subheadline.monospacedDigit().bold())
                .foregroundStyle(episode.isWatched ? Color.secondary : Color.accentColor)
                .frame(minWidth: showCode ? 70 : 28, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text(episode.name.isEmpty ? "حلقة \(episode.number)" : episode.name)
                    .lineLimit(1)
                    .foregroundStyle(episode.isWatched ? .secondary : .primary)
                Text(episode.hasAired ? Formatters.date(episode.airDate)
                                      : "تُعرض \(episode.airDate.map(Formatters.dayLabel) ?? "قريباً")")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            Spacer()
            if episode.hasAired {
                WatchButton(isWatched: episode.isWatched) {
                    withAnimation { Library.toggle(episode) }
                }
            } else {
                Image(systemName: "clock").foregroundStyle(.tertiary)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
        .contextMenu {
            if episode.hasAired {
                Button {
                    withAnimation { Library.markUpTo(episode) }
                } label: {
                    Label("شاهدتها وكل اللي قبلها", systemImage: "checkmark.circle.badge.plus")
                }
                Button {
                    withAnimation { Library.toggle(episode) }
                } label: {
                    Label(episode.isWatched ? "ما شاهدتها" : "شاهدتها",
                          systemImage: episode.isWatched ? "xmark.circle" : "checkmark.circle")
                }
            }
        }
    }
}

// MARK: - Episode sheet

struct EpisodeDetailSheet: View {
    @Bindable var episode: Episode

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if let url = episode.imageURL.flatMap(URL.init(string:)) {
                        AsyncImage(url: url) { $0.resizable().scaledToFit() } placeholder: {
                            Color(white: 0.15).aspectRatio(16/9, contentMode: .fit)
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    Text(episode.show?.name ?? "").font(.subheadline).foregroundStyle(.secondary)
                    Text(episode.name).font(.title3.bold())
                    HStack(spacing: 12) {
                        Text(episode.code).monospacedDigit()
                        Text(Formatters.date(episode.airDate))
                        if episode.effectiveRuntime > 0 { Text("\(episode.effectiveRuntime) د") }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)

                    if episode.hasAired {
                        Button {
                            withAnimation { Library.toggle(episode) }
                        } label: {
                            Label(episode.isWatched ? "شاهدتها" : "علّمها كمشاهدة",
                                  systemImage: episode.isWatched ? "checkmark.circle.fill" : "circle")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(episode.isWatched ? Color.gray : Color.accentColor)
                        .foregroundStyle(episode.isWatched ? Color.white : Color.black)

                        if let watchedAt = episode.watchedAt {
                            DatePicker("تاريخ المشاهدة", selection: Binding(
                                get: { watchedAt },
                                set: { episode.watchedAt = $0 }
                            ), in: ...Date())
                            .font(.footnote)
                        }
                    }

                    if let summary = episode.summary, !summary.isEmpty {
                        Text(summary).font(.callout).foregroundStyle(.secondary)
                    }
                }
                .padding()
            }
        }
    }
}
